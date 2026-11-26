#if canImport(SwiftUI)
import SwiftUI
import Observation
import RidgelineCore
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

/// App-wide state. Everything is saved to one local file after each change, so the app works with no signal.
@MainActor @Observable
public final class AppModel {
    public var data: AppData
    public var saveError: String?
    /// Whether a server address and token are saved. Kept as a value so screens do not read the Keychain on every redraw.
    public private(set) var serverConfigured = false
    /// True when the owner pasted their own Anthropic key, so the assistant works without a server.
    public var ownAssistantKeySet = false
    /// A short message about something that just happened (for example an invoice was created). The user can dismiss it.
    public var notice: String?
    /// True while the owner is looking at the app as an employee would see it.
    public var previewingEmployee = false
    /// Team sync's in-memory state (AppModel+TeamSync.swift).
    public let teamSyncRuntime = TeamSyncRuntime()
    /// The last route worked out for today's jobs, shown as numbers on the Home map. It is checked against today's jobs before use.
    public var plannedRoute: RoutePlanResult?
    /// The assistant chat on screen, the conversation as the AI service needs it, and what is happening now.
    public var assistantLines: [AssistantLine] = []
    var assistantHistory: [AssistantMessage] = []
    public var assistantBusy = false
    /// How much of this month's assistant allowance is used, as a percent. Nil until the server says.
    public var assistantUsedPercent: Int?
    /// Things that happened outside the chat (the owner tapped Send), told to the assistant with the next question.
    var assistantUpdates: [String] = []
    /// The name clients see on the map for this device's truck.
    public var sharingLabel = "Truck 1"
    #if canImport(CoreLocation)
    public let truckSharer = LiveLocationSharer()
    #if canImport(StoreKit)
    let purchases = PurchaseStore()
    #endif
    #endif
    /// The storm the crew is logging visits under. Both the Today and Storm screens use it.
    public var stormName: String = Date().formatted(.dateTime.month(.abbreviated).day())
    /// True while saving is switched off to protect an unreadable data file.
    public var savingIsBlocked: Bool { savingBlocked }
    public func dismissLoadNotice() { if !savingBlocked { loadNotice = nil } }
    /// Set when the saved file could not be read: the app started empty and the old file was kept.
    public var loadNotice: String?
    private var savingBlocked = false
    /// Latest forecast summary for the depot, from the National Weather Service.
    public var forecast: WeatherWindowSummary?
    public var winterAlerts: [WinterAlert] = []
    public var weatherStatus: String?
    /// NWS asks apps to identify themselves. Put your app name and a contact address here before release.
    public var weatherUserAgent = "RidgelineOps/3.0 (support through the App Store page)"
    #if canImport(MapKit)
    /// Kept for the life of the app so repeat planning reuses answers for a few minutes, in memory only.
    private let appleETA = CachedETASource(base: MapKitETASource())
    #endif
    let store: FileStore?   // internal so AppModel+SavedCopies.swift can list the saved copies
    /// Where photos are kept, next to the data file. nil when there is no place to save (previews, tests).
    public let photoStorage: PhotoStorage?

    public init(store: FileStore? = AppModel.defaultStore(), photoStorage: PhotoStorage? = AppModel.defaultPhotoStorage()) {
        self.store = store
        self.photoStorage = photoStorage
        let recovery = store?.loadOrRecover()
        self.data = recovery?.data ?? AppData()
        self.loadNotice = recovery?.notice
        self.savingBlocked = !(recovery?.safeToSave ?? true)
        refreshServerFlag()
        if let run = data.activeStormRun { stormName = run.stormName }   // keep logging under the storm in progress after a restart
        // Every site gets its private page link up front, so a link in a message always matches a saved one.
        let before = data.portalLinks.count
        data.ensurePortalLinks(now: Date())
        if data.portalLinks.count != before { save() }
        #if canImport(StoreKit)
        purchases.onEntitlement = { [weak self] tier in
            guard let self, self.data.subscription.plan != tier else { return }
            self.data.subscription.plan = tier
            self.save()
        }
        #endif
        // The 14-day free trial starts on first launch, with every feature unlocked.
        if data.subscription.trialStart == nil && data.subscription.plan == nil {
            data.subscription = .startTrial(at: Date())
            save()
        }
    }

    nonisolated public static func defaultStore() -> FileStore? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return FileStore(url: base.appendingPathComponent("RidgelineOps/data.json"))
    }

    nonisolated public static func defaultPhotoStorage() -> PhotoStorage? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return PhotoStorage(directory: base.appendingPathComponent("RidgelineOps/Photos"))
    }

    /// Applies a change to a copy and keeps it only if it worked. Returns a message to show, or nil on success.
    @discardableResult
    public func edit(_ change: (inout AppData) throws -> Void) -> String? {
        var copy = data
        do { try change(&copy) } catch { return Self.describe(error) }
        data = copy
        save()
        return nil
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case OperationError.notFound: return "That item no longer exists."
        case OperationError.alreadyClockedIn: return "Already clocked in."
        case OperationError.notClockedIn: return "Not clocked in."
        case OperationError.emptyName: return "Enter a name first."
        case OperationError.hasInvoices: return "This client has invoices, which are your records, so they stay. Void or keep them instead."
        case AccountError.missingIdentifier: return "Apple did not return an account identifier."
        case AccountError.differentAccount: return "A different Apple account is already set up here. Delete the account and data first to switch."
        case TeamError.emptyName: return "Enter a name first."
        case TeamError.limitReached(let limit): return "Your plan allows up to \(limit) employees. Switch someone off, or move up to the Max plan."
        case TeamError.notFound: return "That person no longer exists."
        case LoginError.invalidEmail: return "Enter a valid email address."
        case LoginError.invalidUsername: return "Usernames use 3 to 32 letters, numbers, dots, dashes or underscores."
        case LoginError.usernameTaken: return "That username is taken. Pick another."
        case LoginError.weakPassword(let why): return why
        case LoginError.ownerLoginExists: return "This business already has an owner login."
        case LoginError.ownerProtected: return "This business is protected. Sign in with the owner login."
        case LoginError.notFound: return "That login no longer exists."
        case LoginError.wrongPassword: return "The current password is not right."
        case RequestError.notFound: return "That request no longer exists."
        case RequestError.alreadyDecided: return "That request was already answered."
        case QuoteError.expired: return "This quote has expired."
        case QuoteError.alreadyDecided: return "This quote was already accepted or declined."
        case QuoteError.notAccepted: return "Accept the quote first."
        case InvoiceError.notEditable: return "This invoice can no longer be edited."
        case InvoiceError.exceedsBalance: return "That is more than the balance due."
        default: return "Something went wrong: \(error.localizedDescription)"
        }
    }

    public func save() {
        guard !savingBlocked else {
            saveError = "Changes are not being saved because the existing data file could not be read or set aside."
            return
        }
        do {
            try store?.save(data)
            saveError = nil
            teamSyncDidSave()                                // AppModel+TeamSync.swift: sync about 5 seconds later
        } catch {
            saveError = "Could not save: \(error.localizedDescription)"
        }
    }

    public var subscriptionState: SubscriptionState { data.subscription.state(now: Date()) }
    public func canUse(_ feature: Feature) -> Bool { data.subscription.canUse(feature, now: Date()) }

    public func customerName(for site: Site) -> String {
        data.customers.first { $0.id == site.customerID }?.name ?? "Unknown customer"
    }

    // MARK: weather

    /// Loads the forecast for the next `hours` at the depot. Customer addresses are never sent.
    public func refreshWeather(hours: Double = 24) async {
        guard let depot = data.depot else {
            weatherStatus = "Set your yard location first."
            return
        }
        let client = NWSClient(userAgent: weatherUserAgent)
        do {
            let grid = try await client.forecast(near: depot)
            let now = Date()
            forecast = grid.summary(from: now, to: now.addingTimeInterval(hours * 3600))
            winterAlerts = (try? await client.activeWinterAlerts(near: depot)) ?? []
            weatherStatus = "Forecast updated for the next \(Int(hours)) hours."
        } catch {
            weatherStatus = "Weather unavailable (\(error.localizedDescription)). You can still enter conditions by hand."
        }
    }

    // MARK: your data

    /// A backup waiting for the user to confirm replacing the data on this device.
    public var pendingRestore: RestoreResult?
    /// The copy of the data saved just before the last restore, so it can be shared out of the app.
    public var lastSafetyCopy: URL?

    /// Writes a full backup and spreadsheets to a temporary folder so they can be shared. Returns their locations.
    public func prepareExport() -> (backup: URL?, csvs: [URL], problem: String?) {
        let now = Date()
        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("RidgelineExport-\(stamp)")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let backup = dir.appendingPathComponent("ridgeline-backup.json")
            try DataExport.backupJSON(data).write(to: backup, options: .atomic)
            var csvs: [URL] = []
            for file in DataExport.csvFiles(data, now: now) {
                let url = dir.appendingPathComponent(file.name)
                try Data(file.content.utf8).write(to: url, options: .atomic)
                csvs.append(url)
            }
            return (backup, csvs, nil)
        } catch {
            return (nil, [], "Could not prepare the export: \(error.localizedDescription)")
        }
    }

    /// Reads a chosen backup file and holds it until the user confirms. Returns a message on failure.
    public func readBackup(at url: URL) -> String? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            pendingRestore = try DataExport.restore(from: try Data(contentsOf: url))
            return nil
        } catch BackupError.newerVersion {
            return "That backup was made by a newer version of the app. Update the app first."
        } catch BackupError.unreadable {
            return "That file is not a Ridgeline Ops backup."
        } catch {
            return "Could not read the file: \(error.localizedDescription)"
        }
    }

    /// Replaces the data on this device with the pending backup, after saving a safety copy of what is there now.
    public func applyPendingRestore() -> String {
        guard let result = pendingRestore else { return "Nothing to restore." }
        guard !savingBlocked else {
            pendingRestore = nil
            return "Saving is switched off because the existing data file could not be read, so nothing was restored."
        }
        var safetyNote = ""
        if let folder = store?.url.deletingLastPathComponent() {
            let stamp = Int(Date().timeIntervalSince1970)
            let safety = folder.appendingPathComponent("before-restore-\(stamp).json")
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try DataExport.backupJSON(data).write(to: safety, options: .atomic)
                lastSafetyCopy = safety
                safetyNote = " Your previous data was saved as a safety copy; you can share it below."
            } catch {
                pendingRestore = nil
                return "Could not save a safety copy of your current data, so nothing was changed."
            }
        } else {
            safetyNote = " No safety copy of your previous data could be made on this device."
        }
        pendingRestore = nil
        var restored = DataExport.preparedForDevice(result.data, current: data)   // signs everyone out; keeps this device's owner login
        restored.subscription = data.subscription          // a backup never changes this device's trial or plan
        data = restored
        save()
        var message = "Restored \(result.customerCount) customers, \(result.siteCount) sites, \(result.invoiceCount) invoices and \(result.visitCount) visits. Settings such as the yard location and drive-time source now come from the backup. Sign in again to keep going." + safetyNote
        if !result.visitLogVerified {
            message += " Warning: the proof-of-service log in this backup failed its tamper check, so proof packets will say so."
        }
        return message
    }

    // MARK: invoices

    /// Creates a draft invoice for the storms not yet billed on this contract. Returns a message for the user.
    @discardableResult
    public func createInvoice(for contract: SnowContract) -> String {
        guard let site = data.sites.first(where: { $0.id == contract.siteID }) else { return "Site not found." }
        let visits = data.visitLog.records(forSite: site.id).map { $0.asBillingVisit() }
        let existing = data.invoices.filter { $0.siteID == site.id }
        let next = InvoicePlanner.nextBilling(terms: contract.terms, visits: visits, existing: existing)
        let number = InvoiceNumbering.next(existing: data.invoices.map(\.number))
        let invoice = Invoice.fromBilling(next.result, number: number, customerID: site.customerID, siteID: site.id, issueDate: Date(), netDays: data.profile.netDays)
        var message = "Nothing new to bill."
        if !invoice.lines.isEmpty {
            data.invoices.append(invoice)
            save()
            message = "Created draft \(number) for \(invoice.total.formatted)."
        }
        if !next.heldBack.isEmpty {
            message += " \(next.heldBack.count) visit(s) were added after their storm was invoiced and are not billed automatically."
        }
        return message
    }

    public func updateInvoice(id: UUID, _ change: (inout Invoice) throws -> Void) -> String? {
        guard let i = data.invoices.firstIndex(where: { $0.id == id }) else { return "Invoice not found." }
        var copy = data.invoices[i]
        do { try change(&copy) } catch { return Self.describe(error) }
        data.invoices[i] = copy
        save()
        return nil
    }

    public func invoicesCSV() -> String {
        InvoiceCSV.export(data.invoices, customerName: { id in data.customers.first { $0.id == id }?.name ?? "" }, now: Date())
    }

    // MARK: account

    public func signIn(appleUserID: String, name: String, email: String) -> String? {
        edit { try $0.signIn(appleUserID: appleUserID, displayName: name, email: email, now: Date()) }
    }

    public func signOut() { edit { $0.signOut() } }

    /// Signs out if the person removed this app from their Apple sign-in settings.
    public func checkAppleCredential() async {
        #if canImport(AuthenticationServices)
        guard let id = data.account?.appleUserID else { return }
        let state = try? await ASAuthorizationAppleIDProvider().credentialState(forUserID: id)
        if state == .revoked || state == .notFound {
            data.signOut()
            save()
            notice = "You were signed out because Apple sign-in was removed for this app."
        }
        #endif
    }

    /// Deletes the account and everything stored on this device: records, photos, the saved server token and safety copies.
    /// The trial or plan stays, because it belongs to the device's Apple account.
    public func deleteAccountAndData() {
        stopSharing()                                        // no truck position is sent after the account is gone
        teamSyncForget()                                     // signs out of team sync; the business in the cloud is left alone
        assistantLines = []; assistantHistory = []; assistantUpdates = []
        try? photoStorage?.deleteAll()
        UserDefaults.standard.removeObject(forKey: "crewMemberName")
        let temp = FileManager.default.temporaryDirectory
        if let names = try? FileManager.default.contentsOfDirectory(atPath: temp.path) {
            for name in names where name.hasPrefix("RidgelineExport-") { try? FileManager.default.removeItem(at: temp.appendingPathComponent(name)) }
        }
        if savingBlocked, let file = store?.url {          // the person chose to delete everything, so an unreadable file goes too
            try? FileManager.default.removeItem(at: file)
            savingBlocked = false
            loadNotice = nil
        }
        #if canImport(Security)
        KeychainStore.save("", for: Self.routingTokenKey)
        KeychainStore.save("", for: Self.assistantKeyKey)
        ownAssistantKeySet = false
        #endif
        #if canImport(MapKit)
        appleETA.clear()
        #endif
        if let folder = store?.url.deletingLastPathComponent(),
           let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) {
            for name in names where name.hasPrefix("before-restore-") || name.contains(".unreadable-") {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
            }
        }
        if let store {                                       // rolling and daily copies of the data file go too
            for copy in store.dailyCopyURLs() + [store.backupURL] { try? FileManager.default.removeItem(at: copy) }
        }
        data = data.erasedCopy()
        serverConfigured = false
        forecast = nil; winterAlerts = []; pendingRestore = nil; lastSafetyCopy = nil; notice = nil
        save()
    }

    // MARK: client portal, requests and storm messages

    func refreshServerFlag() {
        serverConfigured = portalClient() != nil
        #if canImport(Security)
        ownAssistantKeySet = !(KeychainStore.load(Self.assistantKeyKey) ?? "").isEmpty
        #endif
    }

    func portalClient() -> PortalClient? {
        #if canImport(Security)
        guard let url = RoutingServerSettings.validatedURL(data.routingServerURL),
              let token = KeychainStore.load(Self.routingTokenKey), !token.isEmpty else { return nil }
        return PortalClient(baseURL: url, token: token)
        #else
        return nil
        #endif
    }

    /// The storm the owner is working on, created the first time it is needed.
    public func ensureStorm(inches: Double) -> StormEvent {
        if let found = data.storms.first(where: { $0.name == stormName }) { return found }
        let storm = StormEvent(name: stormName, start: Date(), forecastInches: inches)
        edit { $0.storms.append(storm) }
        return storm
    }

    /// Fetches new client requests from the server and adds them to the inbox.
    public func refreshRequests() async -> String {
        guard let client = portalClient() else { return "Set up your server in Settings to receive client requests." }
        let resent = await retryUnsyncedDecisions()
        do {
            let incoming = try await client.fetchRequests()
            var added = 0
            edit { added = $0.importRequests(incoming) }
            var text = added == 0 ? "No new requests." : "\(added) new request\(added == 1 ? "" : "s")."
            if resent > 0 { text += " Sent \(resent) earlier answer\(resent == 1 ? "" : "s") to client pages." }
            return text
        } catch {
            return "Could not reach your server."
        }
    }

    /// Answers given here that the client's page has not been told about yet (for example the server was unreachable).
    func retryUnsyncedDecisions() async -> Int {
        guard let client = portalClient() else { return 0 }
        var done = 0
        for r in data.unsyncedDecisions {
            guard let remote = r.remoteID else { continue }
            do {
                try await client.decide(remoteRequestID: remote, accept: r.status == .accepted, message: r.responseMessage)
                edit { $0.markDecisionSynced(id: r.id) }
                done += 1
            } catch {
                if (error as? PortalError) == .server(409) || (error as? PortalError) == .server(404) {   // already answered, or the server no longer has it
                    edit { $0.markDecisionSynced(id: r.id) }
                    done += 1
                }
            }
        }
        return done
    }

    /// Accepts or declines a request. The answer is saved here first, then shown on the client's page.
    public func decideRequest(_ id: UUID, accept: Bool, message: String) async -> String {
        guard let request = data.serviceRequests.first(where: { $0.id == id }) else { return "That request no longer exists." }
        if let problem = edit({ try $0.decideRequest(id: id, accept: accept, message: message, now: Date()) }) { return problem }
        guard let remote = request.remoteID, let client = portalClient() else { return accept ? "Accepted." : "Declined." }
        do {
            try await client.decide(remoteRequestID: remote, accept: accept, message: message)
            edit { $0.markDecisionSynced(id: id) }
            _ = await republishPortal()
            return accept ? "Accepted. The client can see your answer." : "Declined. The client can see your answer."
        } catch {
            return "Saved here, but the client's page was not updated. It will be sent the next time you check for requests."
        }
    }

    /// Plans from the saved data. Page links are saved before this is called, so a link in a message is a real one.
    public func broadcastPlan(storm: StormEvent, inches: Double, urgent: Bool) -> BroadcastPlan {
        StormBroadcast.plan(data: data, storm: storm, forecastInches: inches, now: Date(), urgent: urgent)
    }

    public func prepareClientPages() { edit { $0.ensurePortalLinks(now: Date()) } }

    /// A fresh storm name for today that no earlier storm uses.
    public func startNewStorm() {
        stormName = StormNaming.uniqueName(base: Date().formatted(.dateTime.month(.abbreviated).day()), existing: data.storms.map(\.name))
    }

    func portalSnapshot(storm: StormEvent, inches: Double, routeStart: Date?, offsets: [UUID: Double]) -> PortalSnapshot {
        let served = Set(DispatchRules.effectiveSites(sites: data.sites, inches: inches, stormID: storm.id, requests: data.serviceRequests).map(\.id))
        return PortalSnapshotBuilder.build(data: data, storm: storm, forecastInches: inches, servedSiteIDs: served,
                                           visitStormName: storm.name, routeStart: routeStart, arrivalOffsets: offsets,
                                           weather: PortalWeather.make(from: forecast, alerts: winterAlerts))
    }

    /// Keeps the client pages current (status, bills) after something changes. Does nothing without a server or a storm.
    public func republishPortal() async -> String? {
        guard let client = portalClient(), let storm = data.storms.first(where: { $0.name == stormName }) else { return nil }
        do {
            try await client.publish(portalSnapshot(storm: storm, inches: storm.effectiveInches, routeStart: nil, offsets: [:]))
            return nil
        } catch {
            return "Could not update client pages."
        }
    }

    /// Publishes the client pages, then sends the storm messages that are allowed to go out now. Messages held for
    /// quiet hours stay unsent and are planned again next time. Only messages that really went out are recorded.
    public func sendBroadcast(storm: StormEvent, inches: Double, plan: BroadcastPlan, routeStart: Date, offsets: [UUID: Double]) async -> String {
        guard let client = portalClient() else { return "Set up your server in Settings first." }
        edit { $0.ensurePortalLinks(now: Date()); if !$0.storms.contains(where: { $0.id == storm.id }) { $0.storms.append(storm) } }
        let now = Date()
        let due = plan.messages.filter { $0.sendAfter <= now }
        let held = plan.messages.count - due.count
        do {
            try await client.publish(portalSnapshot(storm: storm, inches: inches, routeStart: routeStart, offsets: offsets))
        } catch {
            return "Could not publish the client pages, so no messages were sent."
        }
        var sent: [PlannedMessage] = []
        if !due.isEmpty {
            do {
                let ok = try await client.sendEmails(due)
                sent = zip(due, ok).filter { $0.1 }.map { $0.0 }
            } catch {
                return "Client pages are up to date, but the messages could not be sent. Nothing was recorded as sent."
            }
        }
        edit { $0.recordSent(sent, stormID: storm.id, at: Date()) }
        var text = "Sent \(sent.count) message\(sent.count == 1 ? "" : "s")."
        if sent.count < due.count { text += " \(due.count - sent.count) failed and can be tried again." }
        if held > 0 { text += " \(held) are waiting for quiet hours to end." }
        return text
    }

    // MARK: reminders and imports

    public func reminderPlan() -> ReminderPlan { ReminderPlanner.plan(data: data, now: Date()) }

    /// Sends the reminders that are due now. Only reminders that really went out are recorded, which also enforces the pause between them.
    public func sendReminders() async -> String {
        guard let client = portalClient() else { return "Set up your server in Settings first." }
        let plan = reminderPlan()
        let now = Date()
        let due = zip(plan.messages, plan.invoiceNumbers).filter { $0.0.sendAfter <= now }
        if due.isEmpty { return plan.messages.isEmpty ? "No reminders are due." : "Reminders are waiting for quiet hours to end." }
        do {
            let ok = try await client.sendEmails(due.map { $0.0 })
            let sent = zip(due, ok).filter { $0.1 }.map { $0.0.1 }
            edit { $0.recordReminders(sent, at: Date()) }
            var text = "Sent \(sent.count) reminder\(sent.count == 1 ? "" : "s")."
            if sent.count < due.count { text += " \(due.count - sent.count) failed and can be tried again." }
            return text
        } catch {
            return "Could not send reminders. Nothing was recorded as sent."
        }
    }

    /// Reads a chosen spreadsheet file (CSV) for client import. Returns the report, or a message if the file cannot be read.
    public func readImportFile(at url: URL) -> (report: ImportReport?, problem: String?) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return (nil, "Could not read that file.") }
        guard data.count <= 2_000_000 else { return (nil, "That file is larger than 2 MB. Split it and import in parts.") }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return (nil, "That file is not text.") }
        return (ClientImport.clients(from: text, existing: self.data), nil)
    }

    // MARK: routing server

    public static let routingTokenKey = "routingToken"
    public static let assistantKeyKey = "anthropicAPIKey"
    public static let assistantDeviceKey = "assistantDeviceID"

    /// The planner for the chosen source. `isLive` is false for the offline estimate; `label` names the source for the user.
    /// `onReport` receives what Apple Maps measured for this one planning run.
    func routePlanner(onReport: (@Sendable (SampledReport) -> Void)? = nil) -> (planner: RoutePlanner, isLive: Bool, label: String) {
        if data.routingProvider == .appleMaps {
            #if canImport(MapKit)
            let source = SampledMatrixSource(etaSource: appleETA, onReport: onReport)
            return (RoutePlanner(matrixSource: source), true, "Apple Maps on this device")
            #endif
        }
        if data.routingProvider == .server {
            #if canImport(Security)
            if let url = RoutingServerSettings.validatedURL(data.routingServerURL), let token = KeychainStore.load(Self.routingTokenKey), !token.isEmpty {
                let source = FallbackMatrixSource(primary: ProxyMatrixSource(baseURL: url, token: token), secondary: ProviderMatrixSource())
                return (RoutePlanner(matrixSource: source), true, "your routing server")
            }
            #endif
        }
        return (RoutePlanner(), false, "the offline estimate")
    }

    /// True when a routing server token is stored in the keychain.
    public var hasRoutingToken: Bool {
        #if canImport(Security)
        if let token = KeychainStore.load(Self.routingTokenKey), !token.isEmpty { return true }
        #endif
        return false
    }

    public func setRoutingProvider(_ provider: RoutingProvider) {
        data.routingProvider = provider
        save()
    }

    /// Saves the server address and token. A blank token keeps the one already stored.
    /// Returns a message for the user.
    public func saveRoutingServer(address: String, token: String) -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            data.routingServerURL = ""
            #if canImport(Security)
            KeychainStore.save("", for: Self.routingTokenKey)
            #endif
            save()
            refreshServerFlag()
            return "Server removed."
        }
        guard RoutingServerSettings.validatedURL(trimmed) != nil else { return "The address must start with https://." }
        let newToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        #if canImport(Security)
        if newToken.isEmpty {
            guard hasRoutingToken else { return "Enter the access code." }
        } else if !KeychainStore.save(newToken, for: Self.routingTokenKey) {
            return "Could not store the access code securely."
        }
        #endif
        data.routingServerURL = trimmed
        save()
        refreshServerFlag()
        return "Saved."
    }

    public func setDepot(latitude: Double, longitude: Double) {
        data.depot = Coordinate(latitude: latitude, longitude: longitude)
        save()
    }

    // MARK: edits

    @discardableResult
    public func addCustomerWithSite(name: String, phone: String, email: String = "", emailConsent: Bool = false, address: String, priority: Int,
                                    triggerInches: Double, perPushRate: Money, seasonPrice: Money? = nil, coordinate: Coordinate?) -> UUID {
        let consent = emailConsent && ContactValidation.isValidEmail(email)
        let customer = Customer(name: name, phone: phone, email: email, emailConsent: consent,
                                consentRecordedAt: consent ? Date() : nil,
                                consentSource: consent ? "Owner confirmed the client agreed when adding them" : "")
        let site = Site(customerID: customer.id, address: address, latitude: coordinate?.latitude,
                        longitude: coordinate?.longitude, priority: priority, triggerInches: triggerInches)
        data.customers.append(customer)
        data.sites.append(site)
        data.contracts.append(SnowContract(siteID: site.id, season: Self.currentSeason(),
                                           terms: seasonPrice.map { ContractTerms.seasonal(total: $0) } ?? ContractTerms.perPush(rate: perPushRate)))
        data.ensurePortalLinks(now: Date())
        save()
        return customer.id
    }

    /// Saves a visit. If automatic invoices are on, it also creates the invoice (and emails it if you chose that and
    /// the client agreed), then refreshes the client page.
    public func record(_ visit: VisitRecord) {
        data.visitLog.append(visit)
        data.markStormJobDone(after: visit)   // StormMode.swift
        let outcome = data.autoInvoice(afterVisit: visit, now: Date())
        save()
        if outcome.invoice != nil { notice = outcome.note }
        if let message = outcome.message, let invoice = outcome.invoice {
            if let client = portalClient() {
                Task { await sendInvoiceEmail(message, number: invoice.number, client: client) }
            } else {
                notice = "Draft invoice \(invoice.number) created. Set up your server in Settings to email it."
            }
        }
        Task { _ = await republishPortal() }
    }

    func sendInvoiceEmail(_ message: PlannedMessage, number: String, client: PortalClient) async {
        let ok = (try? await client.sendEmails([message]))?.first == true
        if ok {
            edit { try $0.markInvoiceSent(number: number, at: Date()) }
            notice = "Invoice \(number) was emailed to the client."
        } else {
            notice = "Invoice \(number) was created but could not be emailed. It stays a draft."
        }
        _ = await republishPortal()
    }

    public func loadDemoData() {
        // Adds sample customers only while there are none, and never removes anything else.
        guard data.customers.isEmpty, data.sites.isEmpty, data.contracts.isEmpty else { return }
        var d = data
        if d.companyName.isEmpty { d.companyName = AppData.sampleCompanyName }
        if d.depot == nil { d.depot = AppData.sampleYard }
        if d.crews.isEmpty { d.crews = [Crew(name: "Truck 1")] }
        func add(_ name: String, _ address: String, _ dLat: Double, _ dLon: Double, _ priority: Int,
                 _ trigger: Double, _ terms: ContractTerms) {
            let c = Customer(name: name, phone: AppData.samplePhone)
            let s = Site(customerID: c.id, address: address, latitude: 44.9778 + dLat, longitude: -93.2650 + dLon,
                         priority: priority, triggerInches: trigger,
                         instructions: priority == 1 ? "Clear fire lane first." : "")
            d.customers.append(c)
            d.sites.append(s)
            d.contracts.append(SnowContract(siteID: s.id, season: Self.currentSeason(), terms: terms))
        }
        add("Lakeside Clinic", "100 Lake St", 0.010, 0.012, 1, 1, .hybrid(seasonalBase: Money(dollars: 900), includedPushes: 8, overagePerPush: Money(dollars: 85)))
        add("Oak Ridge HOA", "22 Oak Ridge Rd", 0.030, -0.020, 2, 2, .seasonal(total: Money(dollars: 1400)))
        add("Pat Miller", "14 Elm Ave", 0.015, 0.030, 3, 2, .perPush(rate: Money(dollars: 55)))
        add("Sam's Auto", "410 Industrial Pkwy", -0.020, 0.040, 2, 3, .perInch(tiers: [DepthTier(minInches: 3, rate: Money(dollars: 120)), DepthTier(minInches: 8, rate: Money(dollars: 200))]))
        add("Dana Reyes", "7 Birch Ct", 0.040, 0.010, 3, 2, .perPush(rate: Money(dollars: 50), counting: .perVisit))
        add("Maple Plaza", "900 Maple Blvd", -0.010, -0.030, 1, 2, .timeAndMaterials(hourly: Money(dollars: 110), materialsMarkupPercent: 15))
        data = d
        save()
    }

    static func currentSeason(now: Date = Date()) -> String {
        let cal = Calendar.current
        let y = cal.component(.year, from: now)
        let m = cal.component(.month, from: now)
        let start = m >= 7 ? y : y - 1
        return "\(start)-\(String(format: "%02d", (start + 1) % 100))"
    }
}
#endif

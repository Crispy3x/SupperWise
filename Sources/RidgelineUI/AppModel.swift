#if canImport(SwiftUI)
import SwiftUI
import Observation
import RidgelineCore

/// App-wide state. Everything is saved to one local file after each change, so the app works with no signal.
@MainActor @Observable
public final class AppModel {
    public var data: AppData
    public var saveError: String?
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
    public var weatherUserAgent = "RidgelineOpsApp"
    #if canImport(MapKit)
    /// Kept for the life of the app so repeat planning reuses answers for a few minutes, in memory only.
    private let appleETA = CachedETASource(base: MapKitETASource())
    #endif
    private let store: FileStore?
    /// Where photos are kept, next to the data file. nil when there is no place to save (previews, tests).
    public let photoStorage: PhotoStorage?

    public init(store: FileStore? = AppModel.defaultStore(), photoStorage: PhotoStorage? = AppModel.defaultPhotoStorage()) {
        self.store = store
        self.photoStorage = photoStorage
        let recovery = store?.loadOrRecover()
        self.data = recovery?.data ?? AppData()
        self.loadNotice = recovery?.notice
        self.savingBlocked = !(recovery?.safeToSave ?? true)
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
        var restored = result.data
        restored.subscription = data.subscription          // a backup never changes this device's trial or plan
        data = restored
        save()
        var message = "Restored \(result.customerCount) customers, \(result.siteCount) sites, \(result.invoiceCount) invoices and \(result.visitCount) visits. Settings such as the yard location and drive-time source now come from the backup." + safetyNote
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
        let invoice = Invoice.fromBilling(next.result, number: number, customerID: site.customerID, siteID: site.id, issueDate: Date())
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
        do { try change(&copy) } catch { return "Could not change the invoice: \(error)" }
        data.invoices[i] = copy
        save()
        return nil
    }

    public func invoicesCSV() -> String {
        InvoiceCSV.export(data.invoices, customerName: { id in data.customers.first { $0.id == id }?.name ?? "" }, now: Date())
    }

    // MARK: routing server

    public static let routingTokenKey = "routingToken"

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
            return "Routing server removed."
        }
        guard RoutingServerSettings.validatedURL(trimmed) != nil else { return "The address must start with https://." }
        let newToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        #if canImport(Security)
        if newToken.isEmpty {
            guard hasRoutingToken else { return "Enter the access token." }
        } else if !KeychainStore.save(newToken, for: Self.routingTokenKey) {
            return "Could not store the token securely."
        }
        #endif
        data.routingServerURL = trimmed
        save()
        return "Saved."
    }

    public func setDepot(latitude: Double, longitude: Double) {
        data.depot = Coordinate(latitude: latitude, longitude: longitude)
        save()
    }

    // MARK: edits

    public func addCustomerWithSite(name: String, phone: String, address: String, priority: Int,
                                    triggerInches: Double, perPushRate: Money, coordinate: Coordinate?) {
        let customer = Customer(name: name, phone: phone)
        let site = Site(customerID: customer.id, address: address, latitude: coordinate?.latitude,
                        longitude: coordinate?.longitude, priority: priority, triggerInches: triggerInches)
        data.customers.append(customer)
        data.sites.append(site)
        data.contracts.append(SnowContract(siteID: site.id, season: Self.currentSeason(),
                                           terms: .perPush(rate: perPushRate)))
        save()
    }

    public func record(_ visit: VisitRecord) {
        data.visitLog.append(visit)
        save()
    }

    public func loadDemoData() {
        // Adds sample customers only while there are none, and never removes anything else.
        guard data.customers.isEmpty, data.sites.isEmpty, data.contracts.isEmpty else { return }
        var d = data
        if d.companyName.isEmpty { d.companyName = "Demo Plowing" }
        if d.depot == nil { d.depot = Coordinate(latitude: 44.9778, longitude: -93.2650) }
        if d.crews.isEmpty { d.crews = [Crew(name: "Truck 1")] }
        func add(_ name: String, _ address: String, _ dLat: Double, _ dLon: Double, _ priority: Int,
                 _ trigger: Double, _ terms: ContractTerms) {
            let c = Customer(name: name, phone: "555-0100")
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

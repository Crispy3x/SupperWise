#if canImport(SwiftUI)
import SwiftUI
import Observation
import RidgelineCore

/// App-wide state. Everything is saved to one local file after each change, so the app works with no signal.
@MainActor @Observable
public final class AppModel {
    public var data: AppData
    public var saveError: String?
    /// Set when the saved file could not be read: the app started empty and the old file was kept.
    public var loadNotice: String?
    private var savingBlocked = false
    /// Latest forecast summary for the depot, from the National Weather Service.
    public var forecast: WeatherWindowSummary?
    public var winterAlerts: [WinterAlert] = []
    public var weatherStatus: String?
    /// NWS asks apps to identify themselves. Put your app name and a contact address here before release.
    public var weatherUserAgent = "RidgelineOpsApp"
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

    /// The planner to use: the routing server (live traffic) when it is set up, otherwise the offline estimate.
    /// The second value says which one, for showing to the user.
    func routePlanner() -> (planner: RoutePlanner, usingServer: Bool) {
        #if canImport(Security)
        if let url = RoutingServerSettings.validatedURL(data.routingServerURL), let token = KeychainStore.load(Self.routingTokenKey), !token.isEmpty {
            let source = FallbackMatrixSource(primary: ProxyMatrixSource(baseURL: url, token: token), secondary: ProviderMatrixSource())
            return (RoutePlanner(matrixSource: source), true)
        }
        #endif
        return (RoutePlanner(), false)
    }

    public var hasRoutingToken: Bool {
        #if canImport(Security)
        return !(KeychainStore.load(Self.routingTokenKey) ?? "").isEmpty
        #else
        return false
        #endif
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

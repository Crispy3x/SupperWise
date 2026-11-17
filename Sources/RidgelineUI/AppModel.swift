#if canImport(SwiftUI)
import SwiftUI
import Observation
import RidgelineCore

/// App-wide state. Everything is saved to one local file after each change, so the app works with no signal.
@MainActor @Observable
public final class AppModel {
    public var data: AppData
    public var saveError: String?
    /// Latest forecast summary for the depot, from the National Weather Service.
    public var forecast: WeatherWindowSummary?
    public var winterAlerts: [WinterAlert] = []
    public var weatherStatus: String?
    /// NWS asks apps to identify themselves. Put your app name and a contact address here before release.
    public var weatherUserAgent = "RidgelineOpsApp"
    private let store: FileStore?

    public init(store: FileStore? = AppModel.defaultStore()) {
        self.store = store
        self.data = (try? store?.load()) ?? AppData()
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

    public func save() {
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
        var d = AppData()
        d.companyName = "Demo Plowing"
        d.subscription = data.subscription
        d.depot = Coordinate(latitude: 44.9778, longitude: -93.2650)
        let crew = Crew(name: "Truck 1")
        d.crews = [crew]
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

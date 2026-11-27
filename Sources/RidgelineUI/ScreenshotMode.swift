#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Debug builds only: launching with `-uiShot <name>` fills the app with sample data and opens one screen, so the
/// build machine can take a picture of every screen. It never runs in App Store builds.
enum ScreenshotMode {
    static var shot: String? {
        #if DEBUG
        let s = UserDefaults.standard.string(forKey: "uiShot")
        return (s?.isEmpty ?? true) ? nil : s
        #else
        return nil
        #endif
    }
    static var light: Bool { UserDefaults.standard.bool(forKey: "uiLight") }
    /// `-uiAnchor 0.5` starts scrolling pages half-way down, `1` at the bottom, so long pages can be photographed in parts.
    static var anchor: UnitPoint? {
        #if DEBUG
        let y = UserDefaults.standard.double(forKey: "uiAnchor")
        return y > 0 ? UnitPoint(x: 0.5, y: min(y, 1)) : nil
        #else
        return nil
        #endif
    }

    /// The route planner's panel height for the route pictures: mostly map, the usual half, or the full stop list.
    static var routeDetent: PresentationDetent {
        switch shot {
        case "routeMap": return .height(220)
        case "routeList": return .large
        default: return .medium
        }
    }

    /// A full morning of residential stops for the route pictures, already put in the best order.
    static func addRouteDay(_ d: inout AppData, today: Date, at: (Int, Int, Int) -> Date) {
        let homes: [(String, String, Double, Double)] = [
            ("Chris Walker", "18 Juniper Ln", 0.022, 0.018), ("Megan Hart", "305 Cedar Ave", 0.026, 0.004),
            ("Tom Nguyen", "42 Hawthorne Dr", 0.034, -0.008), ("Lisa Romero", "9 Aspen Way", 0.012, -0.036),
            ("Ben Carter", "77 Willow St", -0.004, -0.042), ("Ava Brooks", "260 Summit Ave", -0.016, -0.018),
            ("Ryan Patel", "15 Lakeview Ter", -0.026, 0.006), ("Grace Kim", "88 River Rd", -0.030, 0.026),
            ("Jake Olson", "131 Prairie Ct", -0.012, 0.052), ("Nora Fields", "6 Elmwood Pl", 0.006, 0.048),
            ("Eli Turner", "402 Pine St", 0.044, 0.036), ("Zoe Martin", "51 Spruce Rd", 0.050, -0.020),
            ("Owen Price", "23 Ridge Ct", 0.002, 0.024), ("Mia Lopez", "70 Harbor Ln", -0.036, -0.032),
        ]
        for (i, h) in homes.enumerated() {
            let c = Customer(name: h.0, phone: AppData.samplePhone)
            let s = Site(customerID: c.id, address: h.1, latitude: AppData.sampleYard.latitude + h.2,
                         longitude: AppData.sampleYard.longitude + h.3, priority: 3, triggerInches: 2)
            d.customers.append(c)
            d.sites.append(s)
            _ = try? d.addJob(title: i % 4 == 3 ? "Plow and salt" : "Plow driveway", kind: .snowPlowing, customerID: c.id,
                              siteID: s.id, start: at(0, 11, i * 15), durationMinutes: 15, now: Date())
        }
        d.routeSettings.defaultBreak = RouteBreak(minutes: 30, afterHours: 3)
        let stops = d.plannerStops(on: today)
        guard let start = d.routeStartCoordinate ?? stops.first?.coordinate else { return }
        let plan = RouteDayPlanner.optimize(stops: stops, start: start, end: d.routeFinishCoordinate(start: start),
                                            startTime: d.routeStartTime(on: today), breakRule: d.routeSettings.defaultBreak,
                                            provider: HaversineDriveTime())
        d.setRouteOrder(plan.stops.map(\.stop.id), on: today, optimized: true)
    }

    /// Screens shown on their own, outside the main shell.
    static let standalone: Set<String> = ["welcome", "onboarding", "clientDetail", "invoices", "quickInvoice", "jobEditor", "jobDetail", "invoiceDetail", "stormStart", "addMember", "paywall"]

    @MainActor static func prepare(_ model: AppModel) {
        guard let shot else { return }
        if shot == "welcome" { return }
        var d = AppData()
        d.subscription = .startTrial(at: Date().addingTimeInterval(-2 * 86_400))
        try? d.startOwnerSessionWithoutLogin(now: Date())
        if shot == "onboarding" { model.data = d; return }
        d.companyName = "Ridge Plow & Lawn"
        d.profile.onboardingCompletedAt = Date()
        d.profile.services = [.snowPlowing, .salting, .mowing]
        if light { d.profile.appearance = "light" }
        if shot != "tutorial" { d.tutorialsSeen = ["owner"] }
        d.grantAssistantConsent(now: Date())
        model.data = d
        model.loadDemoData()
        d = model.data
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            cal.date(byAdding: .minute, value: hour * 60 + minute, to: cal.date(byAdding: .day, value: dayOffset, to: today) ?? today) ?? today
        }
        let plan: [(Int, Int, Int, String, JobKind)] = [(0, 7, 30, "Plow and salt", .snowPlowing), (0, 8, 15, "Plow driveway", .snowPlowing),
                                                        (0, 9, 0, "Plow lot", .snowPlowing), (0, 10, 30, "Salt walkways", .salting),
                                                        (1, 8, 0, "Fall cleanup", .cleanup), (1, 13, 0, "Mow and trim", .lawnCare), (3, 9, 0, "Plow and salt", .snowPlowing)]
        for (i, p) in plan.enumerated() where !d.sites.isEmpty {
            let site = d.sites[i % d.sites.count]
            _ = try? d.addJob(title: p.3, kind: p.4, customerID: site.customerID, siteID: site.id, start: at(p.0, p.1, p.2),
                              durationMinutes: 45, now: Date())
        }
        if let first = d.jobs.first { try? d.setJobStatus(.done, id: first.id) }
        if shot.hasPrefix("route") { addRouteDay(&d, today: today, at: at) }
        _ = try? d.addJob(title: "Order more salt", start: at(0, 15), isTask: true, now: Date())
        let prices = d.priceList
        for (i, c) in d.customers.prefix(3).enumerated() where !prices.isEmpty {
            let picks = [QuickInvoicePick(service: prices[i % prices.count], quantity: i + 1)]
            if let inv = try? d.createQuickInvoice(customerID: c.id, picks: picks, now: Date().addingTimeInterval(Double(-i) * 9 * 86_400)),
               let idx = d.invoices.firstIndex(where: { $0.id == inv.id }) {
                try? d.invoices[idx].markSent(at: Date().addingTimeInterval(Double(-i) * 9 * 86_400))
                if i == 0 { try? d.invoices[idx].record(ManualPayment(amount: inv.total, date: Date().addingTimeInterval(-86_400), method: .check)) }
            }
        }
        model.data = d
        if shot == "assistant" {
            model.ownAssistantKeySet = true
            model.assistantLines = [
                AssistantLine(kind: .user, text: "What's on for today?"),
                AssistantLine(kind: .assistant, text: "You have 4 jobs today. Plow and salt at Lakeside Clinic is done. Next is Plow driveway at Oak Ridge HOA at 8:15 AM, then Pat Miller at 9:00 and Sam's Auto at 10:30."),
                AssistantLine(kind: .user, text: "Invoice Pat Miller for a driveway push"),
                AssistantLine(kind: .assistant, text: "Done. I made a draft invoice for Pat Miller: Driveway push, $45.00. Tap it in Invoices to send.", actions: ["Created invoice INV-0004 for Pat Miller"]),
            ]
        }
    }

    @MainActor @ViewBuilder static func standaloneView(_ model: AppModel) -> some View {
        switch shot {
        case "clientDetail":
            if let c = model.data.customers.first { NavigationStack { ClientDetailView(customerID: c.id).pageBackground() } }
        case "invoices": NavigationStack { InvoicesView().environment(\.embeddedInStack, true) }
        case "quickInvoice": QuickInvoiceSheet()
        case "jobEditor": JobEditorSheet()
        case "jobDetail":
            if let j = model.data.jobs.first(where: { !$0.isTask && $0.status == .scheduled }) { JobDetailSheet(jobID: j.id) }
        case "invoiceDetail":
            if let inv = model.data.invoices.last { InvoiceDetailSheet(number: inv.number) }
        case "stormStart": StartStormSheet()
        case "addMember": AddMemberSheet()
        case "paywall": PaywallGate()
        default: EmptyView()
        }
    }
}

extension AppModel {
    /// The app's model. In a debug build started for screenshots it is filled with sample data and never saved to disk.
    @MainActor static func launch() -> AppModel {
        guard ScreenshotMode.shot != nil else { return AppModel() }
        let model = AppModel(store: nil, photoStorage: nil)
        ScreenshotMode.prepare(model)
        return model
    }
}
#endif

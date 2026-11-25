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

    /// Screens shown on their own, outside the main shell.
    static let standalone: Set<String> = ["welcome", "onboarding", "clientDetail", "invoices", "quickInvoice", "jobEditor"]

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
    }

    @MainActor @ViewBuilder static func standaloneView(_ model: AppModel) -> some View {
        switch shot {
        case "clientDetail":
            if let c = model.data.customers.first { NavigationStack { ClientDetailView(customerID: c.id).pageBackground() } }
        case "invoices": NavigationStack { InvoicesView().environment(\.embeddedInStack, true) }
        case "quickInvoice": QuickInvoiceSheet()
        case "jobEditor": JobEditorSheet()
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

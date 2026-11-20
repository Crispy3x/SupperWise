#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

// MARK: - Timesheets

/// Hours and pay owed for a week, a month or any dates, per person, with the shifts under it.
struct TimesheetsView: View {
    @Environment(AppModel.self) private var model
    @State private var period: TimesheetPeriod = .thisWeek
    @State private var from = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var to = Date()

    private var interval: DateInterval {
        period.interval(now: Date(), custom: min(from, to)...max(from, to))
    }

    var body: some View {
        let report = TimesheetReport.compute(for: model.data, interval: interval, now: Date())
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 4) {
                        ForEach(TimesheetPeriod.allCases, id: \.self) { p in
                            Button { period = p } label: {
                                Text(p.title).font(.title3.weight(period == p ? .semibold : .regular)).lineLimit(1).minimumScaleFactor(0.7)
                                    .foregroundStyle(period == p ? Color.primary : Color.secondary)
                                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                                    .background(period == p ? Look.field : Color.clear, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4).background(Look.card, in: Capsule()).overlay(Capsule().stroke(Look.stroke, lineWidth: 1))
                    if period == .custom {
                        Card(padding: 12) {
                            VStack(spacing: 8) {
                                DatePicker("From", selection: $from, displayedComponents: .date)
                                DatePicker("To", selection: $to, displayedComponents: .date)
                            }
                        }
                    }
                    Text(rangeText).font(.title3).foregroundStyle(.secondary)
                    Card {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) { CapsLabel(text: "Hours"); Text(String(format: "%.1f", report.totalHours)).font(.system(size: 40, weight: .bold, design: .rounded)) }
                            Spacer()
                            Rectangle().fill(Look.stroke).frame(width: 1, height: 60)
                            Spacer()
                            VStack(alignment: .leading, spacing: 6) { CapsLabel(text: "Pay owed"); Text(report.payOwed.formatted).font(.system(size: 40, weight: .bold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1) }
                        }
                    }
                    if !report.missingRates.isEmpty {
                        Label("Set hourly pay in Team to count pay for \(report.missingRates.joined(separator: ", ")).", systemImage: "info.circle")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                    CapsLabel(text: "Timesheet")
                    if report.rows.isEmpty {
                        Text("No shifts in this period. Team members clock in and out from Time clock.").font(.title3).foregroundStyle(.secondary)
                    }
                    ForEach(report.rows) { row in
                        Card(padding: 14) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(row.name).font(.headline)
                                    Spacer()
                                    Text(String(format: "%.1f h", row.hours)).font(.headline)
                                }
                                Text(row.rate.map { "\(row.pay.formatted) at \($0.formatted) an hour" } ?? "No hourly pay set").font(.footnote).foregroundStyle(.secondary)
                                ForEach(report.entries.filter { $0.memberName.lowercased() == row.name.lowercased() }.prefix(8)) { e in
                                    HStack {
                                        Text(e.start.formatted(date: .abbreviated, time: .shortened)).font(.footnote)
                                        Spacer()
                                        Text(e.end == nil ? "on the clock" : String(format: "%.1f h", e.hours(now: Date()))).font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    NavigationLink { TimeClockView().environment(\.embeddedInStack, true).circleBack().pageBackground() } label: {
                        Label("Clock in or out", systemImage: "clock.badge.checkmark").font(.title3.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 16)
                            .background(Look.pill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 100)
            }
        }
        .background(Look.page)
        .navigationTitle("Timesheets")
    }

    private var rangeText: String {
        let f = DateFormatter.make("MMM d")
        let last = interval.end.addingTimeInterval(-1)
        return "\(f.string(from: interval.start)) \u{2013} \(f.string(from: min(last, Date())))"
    }
}

// MARK: - Subscription

/// The plan, the free trial and what each plan includes. Plans are bought with the Apple ID.
struct SubscriptionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var tier: PlanTier = .pro
    @State private var annual = true
    @State private var loaded = false

    private var statusText: String {
        switch model.subscriptionState {
        case .trial(let days): return "Free trial, \(days) day\(days == 1 ? "" : "s") left"
        case .active(let t): return t == .max ? "Max plan" : "Pro plan"
        case .expired: return "Trial ended"
        }
    }

    private var badge: String {
        switch model.subscriptionState {
        case .trial: return "Free trial"
        case .active(let t): return t == .max ? "Max" : "Pro"
        case .expired: return "Trial ended"
        }
    }

    private var features: [String] {
        var f = ["Client and lead management", "Jobs, calendar and scheduling", "Smart route planning with Apple Maps",
                 "Quotes and invoices, emailed as a PDF with your pay links", "Client page with live truck map and arrival time",
                 "Client requests, thank-you messages and tips", "Time clock and timesheets", "Proof of service for every visit",
                 "AI assistant for invoices, jobs and routes", "Employees never pay: up to \(TeamRules.employeeLimit(for: tier)) on this plan"]
        if tier == .max { f += ["Custom permissions for each person", "Storm automation and subcontractor tools"] }
        return f
    }

    var body: some View {
        let tint = Theme.accent(model.data.profile.accentColor)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(model.data.companyName.isEmpty ? "Ridgeline Ops" : model.data.companyName, systemImage: "creditcard").font(.largeTitle.bold()).lineLimit(1).minimumScaleFactor(0.6)
                    Spacer()
                    Text(badge).font(.title3.weight(.medium)).foregroundStyle(tint).padding(.horizontal, 18).padding(.vertical, 12)
                        .background(tint.opacity(0.15), in: Capsule()).overlay(Capsule().stroke(tint.opacity(0.5), lineWidth: 1))
                }
                Card {
                    VStack(spacing: 14) {
                        HStack { CapsLabel(text: "Status"); Spacer(); Text(statusText).font(.title3.weight(.semibold)) }
                        if let end = model.data.subscription.trialEnd, model.data.subscription.plan == nil {
                            Divider()
                            HStack { CapsLabel(text: "Trial ends"); Spacer(); Text(end.formatted(date: .long, time: .omitted)).font(.title3.weight(.semibold)) }
                        }
                    }
                }
                Text("Everything is unlocked during your free trial. You pay for the plan; your employees never pay.")
                    .font(.title3).foregroundStyle(.secondary)
                Card {
                    VStack(alignment: .leading, spacing: 16) {
                        PillChoice(options: [(PlanTier.pro, "Pro", nil), (PlanTier.max, "Max", nil)], selection: $tier)
                        PillChoice(options: [(false, "Monthly", nil), (true, "Yearly", nil)], selection: $annual)
                        purchaseArea
                        CapsLabel(text: "Everything included")
                        ForEach(features, id: \.self) { f in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: "checkmark").font(.callout.weight(.bold)).foregroundStyle(.green)
                                    .frame(width: 34, height: 34).background(Color.green.opacity(0.15), in: Circle())
                                Text(f).font(.title3)
                            }
                        }
                    }
                }
                legalLinks
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 110)
        }
        .onAppear { if !loaded { tier = model.data.seatPlan; loaded = true } }
        .background(Look.page)
    }

    @ViewBuilder private var purchaseArea: some View {
        #if canImport(StoreKit)
        let store = model.purchases
        if let product = store.product(tier, annual: annual) {
            let trial = model.data.subscription.plan == nil
            VStack(spacing: 8) {
                Text(product.displayPrice).font(.system(size: 48, weight: .bold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
                Text(annual ? "per year, per crew" : "per month, per crew").font(.title3).foregroundStyle(.secondary)
                if annual, let monthly = store.product(tier, annual: false) {
                    let ratio = NSDecimalNumber(decimal: product.price / (monthly.price * 12)).doubleValue
                    let save = Int((1 - ratio) * 100 + 0.5)
                    if save > 0 { Text("Save about \(save)% compared with monthly").font(.callout).foregroundStyle(.green) }
                }
                if trial {
                    Text("Your \(Pricing.trialDays)-day free trial is running. You can subscribe at any time; billing starts when you subscribe.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                Button { Task { await store.purchase(product) } } label: {
                    Text(store.purchasing ? "Working..." : "Subscribe").font(.title3.weight(.semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Theme.accent(model.data.profile.accentColor), in: Capsule())
                }
                .buttonStyle(.plain).disabled(store.purchasing)
                Text("\(product.displayPrice) \(annual ? "per year" : "per month"), charged to your Apple ID. It renews on its own until you cancel in Settings on your iPhone, at least 24 hours before the renewal date.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        } else if store.loading {
            HStack { ProgressView(); Text("Loading plans...") }.frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 8) {
                Text(store.loadFailed ? "Could not load plans. Check your connection and try again." : "Plans are not available yet. Everything stays unlocked while you try the app.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Try again") { Task { await store.load() } }.font(.callout.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
        }
        if let message = store.message { Text(message).font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity) }
        #else
        Text("Plans are bought on iPhone and iPad.").font(.callout).foregroundStyle(.secondary)
        #endif
    }

    private var legalLinks: some View {
        VStack(spacing: 10) {
            #if canImport(StoreKit)
            Button("Restore purchases") { Task { await model.purchases.restore() } }.font(.callout.weight(.semibold))
            #endif
            HStack(spacing: 18) {
                NavigationLink("Privacy Policy") { LegalView(title: "Privacy Policy", text: LegalText.privacy).circleBack() }
                if let url = URL(string: StoreProducts.termsURL) { Link("Terms of Use", destination: url) }
                NavigationLink("Support") { LegalView(title: "Support", text: LegalText.support).circleBack() }
            }
            .font(.footnote)
        }
        .frame(maxWidth: .infinity)
    }
}
#endif

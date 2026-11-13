import SwiftUI
import RevenueCat

/// The plans screen: Plus, Family and Pro side by side, yearly or monthly, with live store prices and trial terms
/// from RevenueCat's current offering. Purchases and restores go through RevenueCat.
struct PlansSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Subscriptions.self) private var subs
    /// The plan a locked feature needs; it's preselected and everything below it is hidden.
    var need: Tier? = nil
    var onDone: (() -> Void)? = nil

    @State private var pick: Tier = .family
    @State private var yearly = true
    @State private var busy = false
    @State private var message: String? = nil

    private let accent = Color(hex: 0xAD321C)
    private var tiers: [Tier] { [.plus, .family, .pro].filter { $0 >= (need ?? .plus) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(subs.isSubscribed ? "Change your plan" : "Plan every week")
                        .font(.serif(44)).foregroundStyle(Paper.ink)
                    if let need {
                        Text("That's part of \(need.name)\(need < .pro ? " and above" : "").").foregroundStyle(Paper.ink)
                    } else {
                        Text("Dinners that work for everyone, priced by the pack, under your budget.").foregroundStyle(Paper.ink2)
                    }

                    Picker("Billing", selection: $yearly) {
                        Text(yearlyLabel).tag(true)
                        Text("Monthly").tag(false)
                    }
                    .pickerStyle(.segmented)

                    ForEach(tiers) { t in tierCard(t) }

                    Button(action: buy) {
                        HStack {
                            Spacer()
                            if busy { ProgressView().tint(.white) } else { Text(buyLabel).font(.headline) }
                            Spacer()
                        }
                        .padding(.vertical, 14)
                        .background(Capsule().fill(accent))
                        .foregroundStyle(.white)
                    }
                    .disabled(busy || package(pick, yearly) == nil || subs.tier == pick)

                    if let message { Text(message).font(.footnote).foregroundStyle(accent) }
                    Text(terms).font(.footnote).foregroundStyle(Paper.ink2)
                    HStack(spacing: 18) {
                        Button("Restore purchases") { Task { await restore() } }
                        Link("Terms", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                        Link("Privacy", destination: URL(string: "https://crispy3x.github.io/supperwise-site/privacy.html")!)
                    }
                    .font(.footnote)
                    .tint(accent)
                }
                .padding(20)
            }
            .background(Paper.ground)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Not now") { dismiss() } } }
            .task {
                pick = max(need ?? .family, subs.tier == .family ? .pro : .family)
                if subs.offering == nil { await subs.load() }
            }
        }
    }

    // MARK: Cards

    private func tierCard(_ t: Tier) -> some View {
        let on = pick == t
        let pkg = package(t, yearly)
        return Button { pick = t } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(t.name.replacingOccurrences(of: "Supperwise ", with: "")).font(.title3.weight(.semibold))
                    if t == .family && need == nil {
                        Text("MOST HOUSEHOLDS").font(.caption2.weight(.bold)).foregroundStyle(accent)
                    }
                    if subs.tier == t {
                        Text("CURRENT").font(.caption2.weight(.bold)).foregroundStyle(Paper.ink2)
                    }
                    Spacer()
                    Text(pkg.map { "\($0.storeProduct.localizedPriceString)\(yearly ? "/yr" : "/mo")" } ?? "–")
                        .font(.headline).monospacedDigit()
                }
                if yearly, let perMonth = pkg?.storeProduct.localizedPricePerMonth {
                    Text("About \(perMonth) a month").font(.footnote).foregroundStyle(Paper.ink2)
                }
                if on {
                    ForEach(t.features, id: \.self) { f in
                        Label(f, systemImage: "checkmark").font(.subheadline)
                    }
                }
            }
            .foregroundStyle(Paper.ink)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(Paper.raised))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(on ? accent : Paper.rule, lineWidth: on ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Store

    private func package(_ t: Tier, _ yearly: Bool) -> Package? {
        guard let ids = RC.products[t] else { return nil }
        let id = yearly ? ids.yearly : ids.monthly
        return subs.offering?.availablePackages.first { $0.storeProduct.productIdentifier == id }
    }

    /// "7 days free" when the yearly product has a free trial.
    private func trial(_ p: Package?) -> String? {
        guard let d = p?.storeProduct.introductoryDiscount, d.paymentMode == .freeTrial else { return nil }
        let n = d.subscriptionPeriod.value
        let unit: String = switch d.subscriptionPeriod.unit {
        case .day: n == 1 ? "day" : "days"
        case .week: n == 1 ? "week" : "weeks"
        case .month: n == 1 ? "month" : "months"
        case .year: n == 1 ? "year" : "years"
        }
        return "\(n) \(unit) free"
    }

    private var yearlyLabel: String {
        if let m = package(pick, false)?.storeProduct.price, let y = package(pick, true)?.storeProduct.price, m > 0 {
            let save = Int(((1 - (y as NSDecimalNumber).doubleValue / ((m as NSDecimalNumber).doubleValue * 12)) * 100).rounded())
            if save > 0 { return "Yearly · save \(save)%" }
        }
        return "Yearly"
    }

    private var buyLabel: String {
        let name = pick.name.replacingOccurrences(of: "Supperwise ", with: "")
        if subs.tier == pick { return "Your current plan" }
        if let t = trial(package(pick, yearly)) { return "Try \(name): \(t)" }
        return subs.isSubscribed ? "Switch to \(name)" : "Subscribe to \(name)"
    }

    private var terms: String {
        guard let p = package(pick, yearly) else { return "Plans couldn't load. Check your connection and try again." }
        let price = "\(p.storeProduct.localizedPriceString) a \(yearly ? "year" : "month")"
        let lead = trial(p).map { "Free for \($0.replacingOccurrences(of: " free", with: "")), then \(price)" } ?? price
        return "\(lead), charged to your Apple ID and renewing automatically until you cancel. Cancel in Settings at least 24 hours before the \(trial(p) == nil ? "period" : "trial") ends and you won't be charged again. Switch plans any time."
    }

    private func buy() {
        guard let p = package(pick, yearly) else { return }
        busy = true
        message = nil
        Task {
            defer { busy = false }
            do {
                let result = try await Purchases.shared.purchase(package: p)
                if result.userCancelled { return }
                finish(result.customerInfo)
            } catch {
                message = Subscriptions.message(for: error)
            }
        }
    }

    private func restore() async {
        busy = true
        await subs.restore()
        busy = false
        if subs.isSubscribed { onDone?(); dismiss() } else { message = subs.lastError }
    }

    private func finish(_ info: CustomerInfo) {
        subs.apply(info)
        guard subs.isSubscribed else { return }
        onDone?()
        dismiss()
    }
}

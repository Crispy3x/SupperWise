import SwiftUI
import RevenueCat
import RevenueCatUI

/// The first week, shown in full before any paywall. It's the person's to keep either way.
struct FirstWeekView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let plan = model.plan {
            let cost = model.cost(of: plan)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Season one · \(plan.dinners.count) episodes · ready")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Paper.ink2)
                        Text("\(plan.dinners.count) dinners for \(cost.total.dollars),\nat \(storeLine).")
                            .font(.serif(40))
                            .displayTracking(40)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 22)

                    HStack {
                        ForEach(Array(model.recipes(of: plan).enumerated()), id: \.offset) { _, pair in
                            VStack(spacing: 6) {
                                PlateView(recipe: pair.1, rim: 5, tint: DayPalette.of(pair.0).deep)
                                    .frame(width: 56, height: 56)
                                Text(pair.0.abbreviation).font(.footnote.weight(.semibold)).foregroundStyle(Ink.onDay)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 12)
                    .background(Color(hex: 0xAD321C))
                    .padding(.top, 18)

                    Text("This week's plan and list are yours to keep, whether you subscribe or not.")
                        .font(.subheadline)
                        .padding(.horizontal, 22)
                        .padding(.top, 14)

                    FirstWeekOffer(showKeepFree: plan.isFreeWeek) { model.markOfferSeen() }
                        .padding(.horizontal, 22)
                        .padding(.top, 14)
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .foregroundStyle(Paper.ink)
            .background(Paper.ground)
        }
    }

    private var storeLine: String {
        let p = model.settings.price
        return p.storeName.isEmpty ? "your \(p.storeKind.label.lowercased())" : p.storeName
    }
}

/// The first-week offer, in the app's own words; "See plans" opens RevenueCat's paywall.
struct FirstWeekOffer: View {
    @Environment(Subscriptions.self) private var subs
    let showKeepFree: Bool
    var onDone: (() -> Void)?
    @State private var showPaywall = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                bullet("A new week every Sunday", "priced at your store before you shop.")
                bullet("Everyone's rules on every plate", "diets, allergies and spice, per person.")
                bullet("Scan, score and plan", "product scanner, eating-out scores, first foods, holiday menus.")
            }
            Button { showPaywall = true } label: { Text("See plans").frame(maxWidth: .infinity) }
                .buttonStyle(PillButtonStyle(fill: Color(hex: 0xAD321C), ink: Ink.onDay))
            if showKeepFree {
                Button("Keep my free week") { onDone?() }
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(hex: 0xAD321C))
                    .frame(maxWidth: .infinity)
            }
            if let e = subs.lastError { Text(e).font(.footnote).foregroundStyle(Paper.ink2) }
        }
        .sheet(isPresented: $showPaywall) { PlansSheet { onDone?() } }
    }

    private func bullet(_ bold: String, _ rest: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle().fill(Color(hex: 0xAD321C)).frame(width: 8, height: 8)
            (Text(bold).fontWeight(.semibold) + Text(" " + rest).foregroundStyle(Paper.ink2)).font(.subheadline)
        }
    }
}

/// RevenueCat's paywall (designed in the RevenueCat dashboard; a default template shows until one is published).
/// It shows the current offering's packages (monthly and yearly), prices from the store, trial terms, restore and legal links.
struct PlansSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Subscriptions.self) private var subs
    var need: Tier? = nil
    var onDone: (() -> Void)? = nil

    var body: some View {
        PaywallView(displayCloseButton: true)
            .onPurchaseCompleted { info in finish(info) }
            .onRestoreCompleted { info in
                finish(info)
            }
    }

    private func finish(_ info: CustomerInfo) {
        subs.apply(info)
        guard subs.isSubscribed else { return }
        onDone?()
        dismiss()
    }
}

/// Opens a feature if the plan includes it; otherwise shows the plans with the needed one selected.
struct GatedButton<Label: View>: View {
    @Environment(Subscriptions.self) private var subs
    let feature: Feature
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var showPlans = false

    var body: some View {
        Button {
            if subs.has(feature) { action() } else { showPlans = true }
        } label: {
            HStack(spacing: 6) {
                label()
                if !subs.has(feature) {
                    Image(systemName: "lock.fill").font(.caption2).accessibilityLabel("Needs \(feature.tier.name)")
                }
            }
        }
        .sheet(isPresented: $showPlans) { PlansSheet(need: feature.tier) { action() } }
    }
}

import SwiftUI

/// First run, in the order the spec sets: where you shop, who's eating and what you spend,
/// then the first week, shown in full before any paywall.
struct OnboardingFlow: View {
    @Environment(AppModel.self) private var model
    @State private var step = -1
    @State private var editing: Person? = nil

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case -1: WelcomeStep { step = 0 }
                case 0: StoreStep { step = 1 }
                case 1: householdStep
                default: FirstWeekView()
                }
            }
            .animation(.smooth, value: step)
        }
        .onAppear {
            if model.plan != nil { step = 2 }
        }
    }

    private var householdStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Step 2 of 2").font(.footnote.weight(.bold)).foregroundStyle(Paper.ink2)
                    Text("Who's eating, and what do you spend?")
                        .font(.serif(40))
                        .displayTracking(40)
                }
                Text("Supperwise is free for your first week. After that it's a subscription, and you'll see the price before you pay anything.")
                    .font(.subheadline)
                    .foregroundStyle(Paper.ink2)
                HouseholdForm(editing: $editing)
                Button {
                    if model.settings.people.isEmpty {
                        model.updateSettings { $0.people = [Person(name: "Me")] }
                    }
                    model.makeFirstWeek()
                    if model.plan != nil {
                        model.finishOnboarding()
                        step = 2
                    }
                } label: {
                    Text("Build my first week").frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle(fill: Color(hex: 0xAD321C), ink: Ink.onDay))
                .disabled(model.settings.cookNights.isEmpty)
            }
            .padding(22)
        }
        .foregroundStyle(Paper.ink)
        .background(Paper.ground)
        .sheet(item: $editing) { p in PersonEditor(person: p) }
    }
}

struct StoreStep: View {
    @Environment(AppModel.self) private var model
    let next: () -> Void
    @State private var postal = ""
    @State private var store = ""
    @State private var kind: StoreKind = .supermarket

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Step 1 of 2").font(.footnote.weight(.bold)).foregroundStyle(Paper.ink2)
                    Text("Where do you shop?")
                        .font(.serif(46))
                        .displayTracking(46)
                }
                Text("Supperwise plans a week of dinners and prices the grocery list before you leave the house. Prices are estimates for your kind of store and region.")
                    .font(.subheadline)
                    .foregroundStyle(Paper.ink2)

                VStack(alignment: .leading, spacing: 8) {
                    Text("ZIP or postal code").font(.footnote.weight(.bold)).foregroundStyle(Paper.ink2)
                    TextField("45206", text: $postal)
                        .textContentType(.postalCode)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.characters)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Paper.raised))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Store name (optional)").font(.footnote.weight(.bold)).foregroundStyle(Paper.ink2)
                    TextField("The store you usually go to", text: $store)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Paper.raised))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Kind of store").font(.footnote.weight(.bold)).foregroundStyle(Paper.ink2)
                    Picker("Kind of store", selection: $kind) {
                        ForEach(StoreKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Button {
                    model.updateSettings {
                        $0.price.postalCode = postal
                        $0.price.storeName = store.trimmingCharacters(in: .whitespaces)
                        $0.price.storeKind = kind
                    }
                    next()
                } label: {
                    Text("Next").frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle(fill: Color(hex: 0xAD321C), ink: Ink.onDay))
                .disabled(postal.trimmingCharacters(in: .whitespaces).count < 3)
            }
            .padding(22)
        }
        .foregroundStyle(Paper.ink)
        .background(Paper.ground)
        .onAppear {
            postal = model.settings.price.postalCode
            store = model.settings.price.storeName
            kind = model.settings.price.storeKind
        }
    }
}


/// First screen: what Supperwise is for, in one line, and what it does, in six.
struct WelcomeStep: View {
    let next: () -> Void
    private let accent = Color(hex: 0xAD321C)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Supperwise").font(.footnote.weight(.bold)).foregroundStyle(Paper.ink2)
                Text("Feed your family well, for less.").font(.serif(48)).displayTracking(48).foregroundStyle(Paper.ink)
                Text("Your family's food app. It plans dinners everyone can eat, shops to your budget, and helps you eat healthier at home, at school and out.")
                    .foregroundStyle(Paper.ink2)
                VStack(alignment: .leading, spacing: 14) {
                    row("calendar", "A week of dinners, planned", "Around everyone's diets, allergies and spice levels.")
                    row("cart", "One grocery list, under budget", "Priced by the pack you actually buy.")
                    row("camera.metering.matrix", "Scan any meal or snack", "A 1–100 health score, calories and allergens.")
                    row("bag", "School lunches and baby's first foods", "Planned on the same list.")
                    row("fork.knife", "Eating out and holidays", "Restaurant scores, Thanksgiving and Christmas menus.")
                    row("dollarsign.circle", "See what you save", "Every dinner cooked at home, against takeout.")
                }
                .padding(.vertical, 6)
                Button(action: next) { Text("Get started: it takes a minute").frame(maxWidth: .infinity) }
                    .buttonStyle(PillButtonStyle(fill: accent, ink: Ink.onDay))
                Text("Your first week is free to keep. Your household and plans stay on this iPhone.")
                    .font(.footnote).foregroundStyle(Paper.ink2)
            }
            .padding(24)
        }
        .background(Paper.ground)
    }

    private func row(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(accent).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Paper.ink)
                Text(detail).font(.subheadline).foregroundStyle(Paper.ink2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

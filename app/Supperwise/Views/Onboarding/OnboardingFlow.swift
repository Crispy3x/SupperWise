import SwiftUI

/// First run, in the order the spec sets: where you shop, who's eating and what you spend,
/// then the first week, shown in full before any paywall.
struct OnboardingFlow: View {
    @Environment(AppModel.self) private var model
    @State private var step = 0
    @State private var editing: Person? = nil

    var body: some View {
        NavigationStack {
            Group {
                switch step {
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

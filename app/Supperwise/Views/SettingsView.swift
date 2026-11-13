import SwiftUI
import RevenueCat
import RevenueCatUI
import UserNotifications

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(Subscriptions.self) private var subs
    @Environment(Account.self) private var account
    @State private var showAccount = false
    @Environment(\.dismiss) private var dismiss
    @State private var showCustomerCenter = false
    @State private var showPaywall = false
    @State private var confirmErase = false
    @State private var showHow = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Your plan") {
                    if subs.isSubscribed, let pro = subs.activeEntitlement {
                        Label(subs.tier.name, systemImage: "checkmark.seal")
                        if let date = pro.expirationDate {
                            Text("\(pro.willRenew ? "Renews" : "Ends") \(date.formatted(date: .abbreviated, time: .omitted))\(pro.periodType == .trial ? " · free trial" : "")")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Button("Change plan") { showPaywall = true }
                        Button("Manage subscription") { showCustomerCenter = true }
                    } else {
                        Text("Free. Your first week is yours to keep.")
                        Button("See plans") { showPaywall = true }
                    }
                    Button("Restore purchases") { Task { await subs.restore() } }
                    if let e = subs.lastError { Text(e).font(.footnote).foregroundStyle(.secondary) }
                }

                if account.signedIn {
                    Section("Account") {
                        Text(account.email ?? "Signed in").foregroundStyle(.secondary)
                        Button("Shared recipes, sign out or delete account") { showAccount = true }
                    }
                }

                Section("Where you shop") {
                    TextField("Store name", text: Binding(get: { model.settings.price.storeName },
                                                          set: { v in model.updateSettings { $0.price.storeName = v } }))
                    TextField("ZIP or postal code", text: Binding(get: { model.settings.price.postalCode },
                                                                  set: { v in model.updateSettings { $0.price.postalCode = v } }))
                    Picker("Kind of store", selection: Binding(get: { model.settings.price.storeKind },
                                                              set: { v in model.updateSettings { $0.price.storeKind = v } })) {
                        ForEach(StoreKind.allCases) { Text($0.label).tag($0) }
                    }
                    Button("How we price this") { showHow = true }
                }

                Section {
                    Toggle("Dinner reminder at 4:30 pm", isOn: Binding(get: { model.settings.dinnerReminder }, set: { on in
                        Task { await setReminder(on) }
                    }))
                } footer: {
                    Text("A notification on cook nights with tonight's dish.")
                }

                Section("About") {
                    Link("Privacy policy", destination: URL(string: "https://supperwise.app/privacy")!)
                    Link("Terms of use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    Link("Contact support", destination: URL(string: "mailto:support@supperwise.app")!)
                    if !PhotoCredits.bundled.isEmpty {
                        NavigationLink("Photo credits") { PhotoCreditsView() }
                    }
                    Text("Recipes are a guide. Check ingredients, allergens and food-safety temperatures before cooking. Diet and allergy settings are a convenience, not a medical guarantee.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Erase all my data", role: .destructive) { confirmErase = true }
                } footer: {
                    Text("Everything you've entered lives only on this iPhone. Erasing removes it and starts the app over. It doesn't cancel a subscription.")
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .presentCustomerCenter(isPresented: $showCustomerCenter)
            .sheet(isPresented: $showPaywall) { PlansSheet() }
            .sheet(isPresented: $showHow) { HowWePriceView() }
            .sheet(isPresented: $showAccount) { MySubmissionsView() }
            .confirmationDialog("Erase everything on this iPhone?", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Erase", role: .destructive) {
                    UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                    model.eraseEverything()
                    dismiss()
                }
            }
        }
    }

    /// Asks for notification permission only when the person turns the reminder on.
    private func setReminder(_ on: Bool) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard on else {
            model.updateSettings { $0.dinnerReminder = false }
            return
        }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        model.updateSettings { $0.dinnerReminder = granted }
        guard granted, let plan = model.plan else { return }
        for (day, recipe) in model.recipes(of: plan) {
            let content = UNMutableNotificationContent()
            content.title = "Tonight: \(recipe.name)"
            content.body = "\(recipe.minutes) minutes. \(recipe.side)"
            var when = DateComponents()
            when.weekday = day == .sun ? 1 : day.rawValue + 1
            when.hour = 16
            when.minute = 30
            let request = UNNotificationRequest(identifier: "dinner-\(day.rawValue)", content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false))
            try? await center.add(request)
        }
    }
}

/// Every recipe photo's photographer and license, as the licenses require.
struct PhotoCreditsView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let credits = PhotoCredits.bundled
        let names = Dictionary(uniqueKeysWithValues: model.catalog.recipes.map { ($0.id, $0.name) })
        List(credits.keys.sorted { (names[$0] ?? $0) < (names[$1] ?? $1) }, id: \.self) { id in
            let c = credits[id]!
            VStack(alignment: .leading, spacing: 2) {
                Text(names[id] ?? id).font(.subheadline.weight(.semibold))
                Text(c.line).font(.footnote)
                HStack(spacing: 12) {
                    if let p = c.page, let u = URL(string: p) { Link("Original", destination: u) }
                    if let l = c.licenseURL, let u = URL(string: l) { Link("License", destination: u) }
                }
                .font(.footnote)
            }
        }
        .navigationTitle("Photo credits")
    }
}

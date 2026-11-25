#if canImport(SwiftUI)
import SwiftUI
import UniformTypeIdentifiers
import RidgelineCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var backupURL: URL?
    @State private var csvURLs: [URL] = []
    @State private var dataNote = ""
    @State private var showImporter = false
    @State private var serverAddress = ""
    @State private var serverToken = ""
    @State private var serverNote = ""
    @State private var locationNote = ""
    @State private var findingLocation = false
    #if canImport(CoreLocation)
    @State private var locator = LocationFetcher()
    #endif

    private func hourText(_ hour: Int) -> String {
        let d = Calendar.current.date(bySettingHour: min(max(hour, 0), 23), minute: 0, second: 0, of: Date()) ?? Date()
        return d.formatted(date: .omitted, time: .shortened)
    }

    private func binding<T>(_ get: @escaping () -> T, _ set: @escaping (T) -> Void) -> Binding<T> {
        Binding(get: get, set: { set($0); model.save() })
    }

    /// A whole number shown in a pill stepper, which counts in Doubles.
    private func intBinding(_ get: @escaping () -> Int, _ set: @escaping (Int) -> Void) -> Binding<Double> {
        Binding(get: { Double(get()) }, set: { set(Int($0.rounded())); model.save() })
    }

    var body: some View {
        ScreenStack {
            AppPage(title: "Settings", icon: "gearshape.fill") {
                accountAndAbout
                RemindersSettingsCard()
                tippingAndBusiness
                ReviewSettingsCard()
                ServicePricesCard()   // QuickInvoiceViews.swift
                yardAndInvoices
                drivingAndServer
                costsAndFees
                dataAndPlan
                if model.data.can(.manageSettings) {
                    CardGroup(title: "Assistant (advanced)", footer: "Optional. Most people leave this empty.") { AssistantKeyCard() }
                }
            }
            .onChange(of: model.data) {
                // Files prepared earlier no longer match the data once it changes.
                backupURL = nil
                csvURLs = []
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url): dataNote = model.readBackup(at: url) ?? ""
                case .failure(let error): dataNote = "Could not open the file: \(error.localizedDescription)"
                }
            }
            .alert("Replace the data on this device?",
                   isPresented: Binding(get: { model.pendingRestore != nil }, set: { _ in })) {
                Button("Replace", role: .destructive) { dataNote = model.applyPendingRestore() }
                Button("Cancel", role: .cancel) { model.pendingRestore = nil }
            } message: {
                if let r = model.pendingRestore {
                    Text("This backup has \(r.customerCount) customers, \(r.siteCount) sites, \(r.invoiceCount) invoices and \(r.visitCount) visits. It replaces the data on this device, including settings. A safety copy of your current data is saved first if possible.")
                }
            }
            .onAppear { serverAddress = model.data.routingServerURL }
        }
    }

    // MARK: - Account and about

    @ViewBuilder private var accountAndAbout: some View {
        if model.data.isOwnerSession {
            CardGroup {
                NavigationLink { SubscriptionView().circleBack() } label: {
                    CardLinkRow(icon: "creditcard", tint: .blue, title: "Subscription and plan")
                }
                .buttonStyle(.plain)
                RowDivider()
                NavigationLink { ProfileView().circleBack() } label: {
                    CardLinkRow(icon: "person.crop.circle", tint: .purple, title: "Profile and sign-in")
                }
                .buttonStyle(.plain)
            }
        }
        CardGroup(title: "About") {
            NavigationLink { LegalView(title: "Privacy Policy", text: LegalText.privacy).circleBack() } label: {
                CardLinkRow(icon: "hand.raised", tint: .teal, title: "Privacy Policy")
            }
            .buttonStyle(.plain)
            if let url = URL(string: StoreProducts.termsURL) {
                RowDivider()
                Link(destination: url) {
                    CardLinkRow(icon: "doc.text", tint: .indigo, title: "Terms of Use")
                }
                .buttonStyle(.plain)
            }
            RowDivider()
            NavigationLink { LegalView(title: "Support", text: LegalText.support).circleBack() } label: {
                CardLinkRow(icon: "questionmark.circle", tint: .orange, title: "Support")
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Tipping and business

    @ViewBuilder private var tippingAndBusiness: some View {
        CardGroup(title: "Tipping",
                  footer: "Shows Tip the crew and Send a coffee buttons on client pages. Clients then choose Venmo, PayPal or Cash App. The money goes straight to your crew; this app never handles it.") {
            Toggle("Let clients tip the crew",
                   isOn: binding({ model.data.profile.tippingIsOn }, { model.data.profile.tippingEnabled = $0 }))
            if model.data.profile.tippingIsOn {
                SettingsLinkEntry(label: "Crew Venmo link", placeholder: "https://venmo.com/...",
                                  help: "Leave empty to hide Venmo.", keyPath: \.venmoLink)
                SettingsLinkEntry(label: "Crew PayPal link", placeholder: "https://paypal.me/...",
                                  help: "Leave empty to hide PayPal.", keyPath: \.paypalLink)
                SettingsLinkEntry(label: "Crew Cash App link", placeholder: "https://cash.app/$...",
                                  help: "Leave empty to hide Cash App.", keyPath: \.cashAppLink)
            }
        }
        CardGroup(title: "Business") {
            PillMenu(label: "Appearance",
                     options: [("dark", "Dark"), ("light", "Light"), ("system", "Match my device")],
                     selection: binding({ model.data.profile.appearance ?? "dark" }, { model.data.profile.appearance = $0 }))
            PillMenu(label: "Color",
                     options: AppData.accentColors.map { ($0, $0.capitalized) },
                     selection: binding({ model.data.profile.accentColor }, { model.data.profile.accentColor = $0 }))
            PillField(label: "Business name", placeholder: "Shown to customers",
                      text: binding({ model.data.companyName }, { model.data.companyName = $0 }))
        }
    }

    // MARK: - Yard location, invoices and client messages

    @ViewBuilder private var yardAndInvoices: some View {
        CardGroup(title: "Yard location") {
            if let depot = model.data.depot {
                Text("Set: \(depot.latitude, specifier: "%.3f"), \(depot.longitude, specifier: "%.3f")")
            } else {
                Text("Not set. Needed for the weather forecast and route start.").foregroundStyle(.secondary)
            }
            #if canImport(CoreLocation)
            SecondaryActionButton(title: findingLocation ? "Finding..." : "Use my current location", icon: "location") {
                findingLocation = true
                Task {
                    if let here = await locator.currentLocation() {
                        model.setDepot(latitude: here.latitude, longitude: here.longitude)
                        locationNote = "Yard location saved."
                    } else {
                        locationNote = "Could not get your location. Check the location permission."
                    }
                    findingLocation = false
                }
            }
            .disabled(findingLocation)
            #endif
            if !locationNote.isEmpty { Text(locationNote).font(.footnote).foregroundStyle(.secondary) }
        }
        CardGroup(title: "Invoices and client messages",
                  footer: "Messages and client pages need your server (below) and clients who agreed to messages. Storm messages wait out quiet hours unless you mark them urgent.") {
            invoiceTerms
            RowDivider()
            clientMessages
        }
    }

    @ViewBuilder private var invoiceTerms: some View {
        PillMenu(label: "When a stop is done",
                 options: InvoiceAutomation.allCases.map { ($0, $0.title) },
                 selection: binding({ model.data.profile.invoiceAutomation }, { model.data.profile.invoiceAutomation = $0 }))
        Text(model.data.profile.invoiceAutomation.explanation).font(.footnote).foregroundStyle(.secondary)
        PillStepper(label: "Days clients have to pay",
                    value: intBinding({ model.data.profile.netDays }, { model.data.profile.netDays = $0 }),
                    range: 0...120, step: 1, format: { "\(Int($0))" })
        PillNotes(label: "How clients should pay", placeholder: "Shown on invoices",
                  text: binding({ model.data.profile.paymentInstructions }, { model.data.profile.paymentInstructions = String($0.prefix(300)) }))
        SettingsLinkEntry(label: "Payment link", placeholder: "https://...",
                          help: "Paste a link from Stripe, Square, PayPal, Venmo, Cash App, QuickBooks or Wave. We never touch the money.",
                          goodNote: "Clients get a Pay now button. Payments go to your own account.", keyPath: \.payLink)
    }

    @ViewBuilder private var clientMessages: some View {
        Toggle("Show the message-clients option on the Storm screen",
               isOn: binding({ model.data.profile.stormMessagesOn }, { model.data.profile.stormMessagesOn = $0 }))
        Toggle("Show invoice amounts on client pages",
               isOn: binding({ model.data.profile.portalShowsAmounts }, { model.data.profile.portalShowsAmounts = $0 }))
        SettingsEntry(label: "Client page address", placeholder: "https://...",
                      text: binding({ model.data.broadcastSettings.portalBaseURL }, { model.data.broadcastSettings.portalBaseURL = $0 }))
        if !model.data.routingServerURL.isEmpty && model.data.broadcastSettings.portalBaseURL.isEmpty {
            SecondaryActionButton(title: "Use my server's address", icon: "link") {
                model.data.broadcastSettings.portalBaseURL = model.data.routingServerURL
                model.save()
            }
        }
        PillStepper(label: "Quiet from",
                    value: intBinding({ model.data.broadcastSettings.quietHours.startHour }, { model.data.broadcastSettings.quietHours.startHour = $0 }),
                    range: 0...23, step: 1, format: { self.hourText(Int($0)) })
        PillStepper(label: "Quiet until",
                    value: intBinding({ model.data.broadcastSettings.quietHours.endHour }, { model.data.broadcastSettings.quietHours.endHour = $0 }),
                    range: 0...23, step: 1, format: { self.hourText(Int($0)) })
    }

    // MARK: - Drive times and routing server

    @ViewBuilder private var drivingAndServer: some View {
        CardGroup(title: "Drive times",
                  footer: "Apple Maps needs no key or setup. Apple answers one leg at a time and may slow requests down, so Ridgeline measures the most important legs and estimates the rest. Answers are kept in memory for 10 minutes only, because Apple's terms limit how long its map data may be stored.") {
            PillMenu(label: "Source",
                     options: [(RoutingProvider.appleMaps, "Apple Maps on this device"),
                               (RoutingProvider.server, "My routing server (Google)"),
                               (RoutingProvider.offline, "Offline estimate")],
                     selection: binding({ model.data.routingProvider }, { model.setRoutingProvider($0) }))
        }
        CardGroup(title: "Routing server (only used if chosen above)") {
            SettingsEntry(label: "Routing server address", placeholder: "https://...", text: $serverAddress)
            SettingsEntry(label: "Access token",
                          placeholder: model.hasRoutingToken ? "Token saved (leave blank to keep it)" : "Access token",
                          text: $serverToken, secret: true)
            SecondaryActionButton(title: "Save routing server", icon: "externaldrive.badge.checkmark") {
                serverNote = model.saveRoutingServer(address: serverAddress, token: serverToken)
                serverToken = ""
            }
            Text(model.data.routingProvider != .server
                 ? "Only used when \"My routing server\" is chosen above."
                 : (model.data.routingServerURL.isEmpty
                    ? "Not set, so routes use an offline estimate of drive times."
                    : (model.hasRoutingToken
                       ? "Using live traffic from your routing server. If it cannot be reached, the offline estimate is used."
                       : "Address saved but there is no token yet, so the offline estimate is used.")))
                .font(.footnote).foregroundStyle(.secondary)
            if !serverNote.isEmpty { Text(serverNote).font(.footnote).foregroundStyle(.secondary) }
        }
    }

    // MARK: - Costs and late fees

    @ViewBuilder private var costsAndFees: some View {
        CardGroup(title: "Your costs (for job costs)") {
            PillStepper(label: "Crew cost per hour",
                        value: intBinding({ model.data.laborCostPerHour.cents / 100 }, { model.data.laborCostPerHour = Money(dollars: $0) }),
                        range: 0...300, step: 1, format: { Money(dollars: Int($0)).formatted })
            PillStepper(label: "Salt cost per pound",
                        value: intBinding({ model.data.saltCostPerPound.cents }, { model.data.saltCostPerPound = Money(cents: $0) }),
                        range: 0...200, step: 1, format: { Money(cents: Int($0)).formatted })
        }
        CardGroup(title: "Late fees (never added automatically)") {
            PillStepper(label: "Grace period",
                        value: intBinding({ model.data.lateFeePolicy.graceDays }, { model.data.lateFeePolicy.graceDays = $0 }),
                        range: 0...90, step: 1, format: { "\(Int($0)) days" })
            PillStepper(label: "Flat fee (whole dollars)",
                        value: intBinding({ model.data.lateFeePolicy.flatFee.cents / 100 }, { model.data.lateFeePolicy.flatFee = Money(dollars: $0) }),
                        range: 0...500, step: 5, format: { Money(dollars: Int($0)).formatted })
            PillStepper(label: "Each extra 30 days, % of balance",
                        value: intBinding({ model.data.lateFeePolicy.monthlyPercent }, { model.data.lateFeePolicy.monthlyPercent = $0 }),
                        range: 0...10, step: 1, format: { "\(Int($0))%" })
        }
    }

    // MARK: - Your data and plan

    @ViewBuilder private var dataAndPlan: some View {
        CardGroup(title: "Your data",
                  footer: "The backup holds all your records. Photo files are not included: they stay on this device. Restoring replaces the data on this device, after saving a safety copy of what is there now.") {
            SecondaryActionButton(title: "Prepare a backup and spreadsheets", icon: "archivebox") {
                let export = model.prepareExport()
                backupURL = export.backup
                csvURLs = export.csvs
                dataNote = export.problem ?? "Ready. Choose what to share."
            }
            if let backupURL {
                ShareLink(item: backupURL) {
                    CardLinkRow(icon: "square.and.arrow.up", tint: .blue, title: "Share full backup (JSON)")
                }
                .buttonStyle(.plain)
            }
            ForEach(csvURLs, id: \.self) { url in
                ShareLink(item: url) {
                    CardLinkRow(icon: "tablecells", tint: .green, title: url.lastPathComponent)
                }
                .buttonStyle(.plain)
            }
            SecondaryActionButton(title: "Restore from a backup file...", icon: "arrow.down.doc") { showImporter = true }
            if model.data.isOwnerSession { RestoreEarlierCopyButton() }
            if !dataNote.isEmpty { Text(dataNote).font(.footnote).foregroundStyle(.secondary) }
            if let safety = model.lastSafetyCopy {
                ShareLink(item: safety) {
                    CardLinkRow(icon: "square.and.arrow.up", tint: .orange, title: "Share the safety copy of your previous data")
                }
                .buttonStyle(.plain)
            }
        }
        CardGroup(title: "Plan", footer: "Buying a plan is not connected yet in this build.") {
            switch model.subscriptionState {
            case .trial(let days): Text("Free trial, \(days) day\(days == 1 ? "" : "s") left. All features unlocked.")
            case .active(let tier): Text("Plan: \(tier == .pro ? "Pro" : "Max")")
            case .expired: Text("Trial ended. Nothing is locked in this build.")
            }
        }
        if let error = model.saveError {
            Card { Text(error).font(.footnote).foregroundStyle(.red) }
        }
    }
}

// MARK: - Entry fields in the app's pill style

private extension View {
    /// The rounded box around a field, the same as the pill fields on other screens.
    func settingsPillBox() -> some View {
        self.font(.title3)
            .padding(.horizontal, 22).padding(.vertical, 16)
            .background(Look.field, in: Capsule())
            .overlay(Capsule().stroke(Look.fieldStroke, lineWidth: 1))
    }
}

/// A labelled address or token field in a pill. Web addresses never get capital letters.
private struct SettingsEntry: View {
    let label: String
    var optional = false
    let placeholder: String
    @Binding var text: String
    var secret = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(label).font(.title3.weight(.medium))
                if optional { Text("(optional)").font(.title3).foregroundStyle(.secondary) }
            }
            if secret {
                SecureField(placeholder, text: $text).settingsPillBox()
            } else {
                TextField(placeholder, text: $text)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .settingsPillBox()
            }
        }
    }
}

/// A link kept on the business profile (pay link, tip links). It saves only a link that passes the check,
/// and shows what is wrong with it, or that it is good, under the field.
private struct SettingsLinkEntry: View {
    @Environment(AppModel.self) private var model
    let label: String
    let placeholder: String
    let help: String
    var goodNote = "Clients will see this button on their page."
    let keyPath: WritableKeyPath<BusinessProfile, String?>
    @State private var draft = ""
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsEntry(label: label, optional: true, placeholder: placeholder, text: $draft)
            if let problem = PayLink.problem(for: draft) {
                Label(problem, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
            } else if PayLink.clean(draft) != nil {
                Label(goodNote, systemImage: "checkmark.circle").font(.footnote).foregroundStyle(.secondary)
            } else {
                Text(help).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if !loaded { draft = model.data.profile[keyPath: keyPath] ?? ""; loaded = true }
        }
        .onChange(of: draft) { _, new in
            let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if model.data.profile[keyPath: keyPath] != nil { model.data.profile[keyPath: keyPath] = nil; model.save() }
            } else if let ok = PayLink.clean(trimmed), ok != model.data.profile[keyPath: keyPath] {
                model.data.profile[keyPath: keyPath] = ok; model.save()
            }
        }
    }
}
#endif

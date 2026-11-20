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

    var body: some View {
        ScreenStack {
            Form {
                Section("Business") {
                    Picker("Appearance", selection: binding({ model.data.profile.appearance ?? "dark" }, { model.data.profile.appearance = $0 })) {
                        Text("Dark").tag("dark")
                        Text("Light").tag("light")
                        Text("Match my device").tag("system")
                    }
                    Picker("Color", selection: binding({ model.data.profile.accentColor }, { model.data.profile.accentColor = $0 })) {
                        ForEach(AppData.accentColors, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    TextField("Business name (shown to customers)", text: binding({ model.data.companyName }, { model.data.companyName = $0 }))
                }
                Section("Yard location") {
                    if let depot = model.data.depot {
                        Text("Set: \(depot.latitude, specifier: "%.3f"), \(depot.longitude, specifier: "%.3f")")
                    } else {
                        Text("Not set. Needed for the weather forecast and route start.").foregroundStyle(.secondary)
                    }
                    #if canImport(CoreLocation)
                    Button(findingLocation ? "Finding..." : "Use my current location") {
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
                Section {
                    Picker("When a stop is done", selection: binding({ model.data.profile.invoiceAutomation }, { model.data.profile.invoiceAutomation = $0 })) {
                        ForEach(InvoiceAutomation.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Text(model.data.profile.invoiceAutomation.explanation).font(.footnote).foregroundStyle(.secondary)
                    Stepper("Clients have \(model.data.profile.netDays) days to pay",
                            value: binding({ model.data.profile.netDays }, { model.data.profile.netDays = $0 }), in: 0...120)
                    TextField("How clients should pay (shown on invoices)",
                              text: binding({ model.data.profile.paymentInstructions }, { model.data.profile.paymentInstructions = String($0.prefix(300)) }),
                              axis: .vertical)
                        .lineLimit(2...4)
                    SavedPayLinkField()
                    SavedProfileLinkField(placeholder: "Tip link for the crew (optional), https://...",
                                          note: "Adds a Tip the crew button on client pages. Use your own Venmo, Cash App, PayPal or Stripe link.", keyPath: \.tipLink)
                    SavedProfileLinkField(placeholder: "Buy us a coffee link (optional), https://...",
                                          note: "Adds a Buy us a coffee button on client pages.", keyPath: \.coffeeLink)
                    Toggle("Show the message-clients option on the Storm screen",
                           isOn: binding({ model.data.profile.stormMessagesOn }, { model.data.profile.stormMessagesOn = $0 }))
                    Toggle("Show invoice amounts on client pages",
                           isOn: binding({ model.data.profile.portalShowsAmounts }, { model.data.profile.portalShowsAmounts = $0 }))
                    TextField("Client page address (https://...)",
                              text: binding({ model.data.broadcastSettings.portalBaseURL }, { model.data.broadcastSettings.portalBaseURL = $0 }))
                    if !model.data.routingServerURL.isEmpty && model.data.broadcastSettings.portalBaseURL.isEmpty {
                        Button("Use my server's address") { model.data.broadcastSettings.portalBaseURL = model.data.routingServerURL; model.save() }
                            .font(.footnote)
                    }
                    Stepper("Quiet from \(hourText(model.data.broadcastSettings.quietHours.startHour))",
                            value: binding({ model.data.broadcastSettings.quietHours.startHour }, { model.data.broadcastSettings.quietHours.startHour = $0 }), in: 0...23)
                    Stepper("Quiet until \(hourText(model.data.broadcastSettings.quietHours.endHour))",
                            value: binding({ model.data.broadcastSettings.quietHours.endHour }, { model.data.broadcastSettings.quietHours.endHour = $0 }), in: 0...23)
                } header: {
                    Text("Invoices and client messages")
                } footer: {
                    Text("Messages and client pages need your server (below) and clients who agreed to messages. Storm messages wait out quiet hours unless you mark them urgent.")
                }
                Section("Drive times") {
                    Picker("Source", selection: binding({ model.data.routingProvider }, { model.setRoutingProvider($0) })) {
                        Text("Apple Maps on this device").tag(RoutingProvider.appleMaps)
                        Text("My routing server (Google)").tag(RoutingProvider.server)
                        Text("Offline estimate").tag(RoutingProvider.offline)
                    }
                    Text("Apple Maps needs no key or setup. Apple answers one leg at a time and may slow requests down, so Ridgeline measures the most important legs and estimates the rest. Answers are kept in memory for 10 minutes only, because Apple's terms limit how long its map data may be stored.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Routing server (only used if chosen above)") {
                    TextField("Routing server address (https://...)", text: $serverAddress)
                    SecureField(model.hasRoutingToken ? "Token saved (leave blank to keep it)" : "Access token", text: $serverToken)
                    Button("Save routing server") {
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
                Section("Your costs (for job costs)") {
                    Stepper("Crew cost per hour: \(model.data.laborCostPerHour.formatted)",
                            value: binding({ model.data.laborCostPerHour.cents / 100 }, { model.data.laborCostPerHour = Money(dollars: $0) }), in: 0...300)
                    Stepper("Salt cost per pound: \(model.data.saltCostPerPound.formatted)",
                            value: binding({ model.data.saltCostPerPound.cents }, { model.data.saltCostPerPound = Money(cents: $0) }), in: 0...200)
                }
                Section("Late fees (never added automatically)") {
                    Stepper("Grace period: \(model.data.lateFeePolicy.graceDays) days",
                            value: binding({ model.data.lateFeePolicy.graceDays }, { model.data.lateFeePolicy.graceDays = $0 }), in: 0...90)
                    Stepper("Flat fee (whole dollars): \(model.data.lateFeePolicy.flatFee.formatted)",
                            value: binding({ model.data.lateFeePolicy.flatFee.cents / 100 }, { model.data.lateFeePolicy.flatFee = Money(dollars: $0) }), in: 0...500, step: 5)
                    Stepper("Each extra 30 days: \(model.data.lateFeePolicy.monthlyPercent)% of the balance",
                            value: binding({ model.data.lateFeePolicy.monthlyPercent }, { model.data.lateFeePolicy.monthlyPercent = $0 }), in: 0...10)
                }
                Section("Your data") {
                    Button("Prepare a backup and spreadsheets") {
                        let export = model.prepareExport()
                        backupURL = export.backup
                        csvURLs = export.csvs
                        dataNote = export.problem ?? "Ready. Choose what to share."
                    }
                    if let backupURL {
                        ShareLink(item: backupURL) { Label("Share full backup (JSON)", systemImage: "square.and.arrow.up") }
                    }
                    ForEach(csvURLs, id: \.self) { url in
                        ShareLink(item: url) { Label(url.lastPathComponent, systemImage: "tablecells") }
                    }
                    Button("Restore from a backup file...") { showImporter = true }
                    Text("The backup holds all your records. Photo files are not included: they stay on this device. Restoring replaces the data on this device, after saving a safety copy of what is there now.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if !dataNote.isEmpty { Text(dataNote).font(.footnote).foregroundStyle(.secondary) }
                    if let safety = model.lastSafetyCopy {
                        ShareLink(item: safety) { Label("Share the safety copy of your previous data", systemImage: "square.and.arrow.up") }
                    }
                }
                Section("Plan") {
                    switch model.subscriptionState {
                    case .trial(let days): Text("Free trial, \(days) day\(days == 1 ? "" : "s") left. All features unlocked.")
                    case .active(let tier): Text("Plan: \(tier == .pro ? "Pro" : "Max")")
                    case .expired: Text("Trial ended. Nothing is locked in this build.")
                    }
                    Text("Buying a plan is not connected yet in this build.").font(.footnote).foregroundStyle(.secondary)
                }
                if let error = model.saveError { Section { Text(error).font(.footnote).foregroundStyle(.red) } }
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
            .navigationTitle("Settings")
        }
    }
}
#endif

#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var serverAddress = ""
    @State private var serverToken = ""
    @State private var serverNote = ""
    @State private var locationNote = ""
    @State private var findingLocation = false
    #if canImport(CoreLocation)
    @State private var locator = LocationFetcher()
    #endif

    private func binding<T>(_ get: @escaping () -> T, _ set: @escaping (T) -> Void) -> Binding<T> {
        Binding(get: get, set: { set($0); model.save() })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Business") {
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
                Section("Live traffic routing") {
                    TextField("Routing server address (https://...)", text: $serverAddress)
                    SecureField(model.hasRoutingToken ? "Token saved (leave blank to keep it)" : "Access token", text: $serverToken)
                    Button("Save routing server") {
                        serverNote = model.saveRoutingServer(address: serverAddress, token: serverToken)
                        serverToken = ""
                    }
                    Text(model.data.routingServerURL.isEmpty
                         ? "Not set. Routes use an offline estimate of drive times."
                         : (model.hasRoutingToken
                            ? "Using live traffic from your routing server. If it cannot be reached, the offline estimate is used."
                            : "Address saved but there is no token yet, so the offline estimate is used."))
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
                Section("Plan") {
                    switch model.subscriptionState {
                    case .trial(let days): Text("Free trial, \(days) day\(days == 1 ? "" : "s") left. All features unlocked.")
                    case .active(let tier): Text("Plan: \(tier == .pro ? "Pro" : "Max")")
                    case .expired: Text("Trial ended. Your data is safe and can be exported.")
                    }
                    Text("Buying a plan is not connected yet in this build.").font(.footnote).foregroundStyle(.secondary)
                }
                if let error = model.saveError { Section { Text(error).font(.footnote).foregroundStyle(.red) } }
            }
            .onAppear { serverAddress = model.data.routingServerURL }
            .navigationTitle("Settings")
        }
    }
}
#endif

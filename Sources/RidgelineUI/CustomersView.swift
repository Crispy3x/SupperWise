#if canImport(SwiftUI)
import SwiftUI
import UniformTypeIdentifiers
import RidgelineCore

struct CustomersView: View {
    @Environment(AppModel.self) private var model
    @State private var showingAdd = false
    @State private var showingImporter = false
    @State private var importReport: ImportReport?
    @State private var importProblem: String?

    var body: some View {
        ScreenStack {
            List {
                if model.data.sites.isEmpty {
                    Section {
                        Text("No customers yet. Add one, or load demo data to try the app.")
                            .foregroundStyle(.secondary)
                        if model.data.customers.isEmpty && model.data.contracts.isEmpty {
                            Button("Load demo data (adds sample customers)") { model.loadDemoData() }
                        }
                    }
                }
                ForEach(model.data.sites) { site in
                    NavigationLink { ClientDetailView(customerID: site.customerID) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.customerName(for: site)).font(.headline)
                            Text(site.address).font(.subheadline)
                            Text("Priority \(site.priority), trigger \(site.triggerInches, specifier: "%.1f") in")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Customers")
            .toolbar {
                Menu {
                    Button("Add one client") { showingAdd = true }
                    Button("Import from a spreadsheet (CSV)") { showingImporter = true }
                } label: { Label("Add", systemImage: "plus") }
            }
            .sheet(isPresented: $showingAdd) { AddCustomerSheet() }
            .sheet(isPresented: Binding(get: { importReport != nil }, set: { if !$0 { importReport = nil } })) {
                if let report = importReport { ImportClientsSheet(report: report) }
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
                switch result {
                case .success(let url):
                    let read = model.readImportFile(at: url)
                    importProblem = read.problem ?? read.report?.problem
                    if read.problem == nil, read.report?.problem == nil { importReport = read.report }
                case .failure(let error):
                    importProblem = "Could not open the file: \(error.localizedDescription)"
                }
            }
            .alert("Could not import", isPresented: Binding(get: { importProblem != nil }, set: { _ in })) {
                Button("OK") { importProblem = nil }
            } message: {
                Text(importProblem ?? "")
            }
        }
    }
}

/// Shows what an import would add before anything is saved. Imported clients are never marked as having agreed to messages.
struct ImportClientsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let report: ImportReport
    @State private var rate = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("\(report.clients.count) client\(report.clients.count == 1 ? "" : "s") will be added.").font(.headline)
                    if !report.skipped.isEmpty { Text("\(report.skipped.count) row\(report.skipped.count == 1 ? "" : "s") skipped.").foregroundStyle(.orange) }
                }
                Section("Price") {
                    Stepper(rate == 0 ? "No price yet" : "Price per push: $\(rate)", value: $rate, in: 0...1000, step: 5)
                    Text("With a price, each client also gets a per-push contract. With none you can add a quote later.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("First few") {
                    ForEach(Array(report.clients.prefix(5).enumerated()), id: \.offset) { _, c in
                        VStack(alignment: .leading) { Text(c.name); Text(c.address).font(.footnote).foregroundStyle(.secondary) }
                    }
                }
                if !report.skipped.isEmpty {
                    Section("Skipped") {
                        ForEach(Array(report.skipped.prefix(8).enumerated()), id: \.offset) { _, s in
                            Text("Row \(s.row): \(s.reason)").font(.footnote)
                        }
                    }
                }
                Section {
                    Text("Nobody is marked as having agreed to messages. Open each client to record that, only if they said yes.").font(.footnote).foregroundStyle(.secondary)
                    Text("A client without a price has no contract, so they are not billed or messaged until you add one (for example by accepting a quote).").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Import clients")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        model.edit { _ = $0.importClients(report.clients, perPush: rate > 0 ? Money(dollars: rate) : nil, now: Date()) }
                        dismiss()
                    }
                    .disabled(report.clients.isEmpty)
                }
            }
        }
    }
}

struct AddCustomerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var agreed = false
    @State private var address = ""
    @State private var priority = 3
    @State private var trigger = 2.0
    @State private var rate = 60
    @State private var seasonal = false
    @State private var season = 900
    @State private var coordinate: Coordinate?
    @State private var locationNote = ""
    @State private var searching = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Customer") {
                    TextField("Name", text: $name)
                    TextField("Phone", text: $phone)
                    TextField("Email (for storm updates and invoices)", text: $email)
                    Toggle("This client agreed to storm and invoice emails", isOn: $agreed)
                        .disabled(!ContactValidation.isValidEmail(email))
                    TextField("Service address", text: $address)
                    #if canImport(CoreLocation)
                    Button(searching ? "Looking up..." : "Find map location") {
                        searching = true
                        let looked = address
                        Task {
                            let found = await AddressGeocoder.coordinate(for: looked)
                            searching = false
                            guard looked == address else { return }   // the address changed while looking
                            coordinate = found
                            locationNote = found == nil ? "Address not found. The site will be left out of route ordering." : "Map location found."
                        }
                    }
                    .disabled(searching || address.isEmpty)
                    if !locationNote.isEmpty { Text(locationNote).font(.footnote).foregroundStyle(.secondary) }
                    #endif
                }
                Section("Service") {
                    Stepper("Priority: \(priority) (1 is first)", value: $priority, in: 1...5)
                    Stepper("Trigger: \(trigger, specifier: "%.1f") in", value: $trigger, in: 0.5...12, step: 0.5)
                    Picker("Billing", selection: $seasonal) {
                        Text("Per push").tag(false)
                        Text("Season").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if seasonal {
                        Stepper("Season price: $\(season)", value: $season, in: 50...50_000, step: 50)
                    } else {
                        Stepper("Price per push: $\(rate)", value: $rate, in: 10...1000, step: 5)
                    }
                }
            }
            .onAppear { trigger = model.data.profile.defaultTriggerInches; seasonal = model.data.profile.defaultSnowBilling == .seasonal }
            .onChange(of: address) {
                // A map location belongs to the address it was found for.
                coordinate = nil
                locationNote = ""
            }
            .navigationTitle("New customer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.addCustomerWithSite(name: name, phone: phone, email: email, emailConsent: agreed, address: address, priority: priority,
                                                  triggerInches: trigger, perPushRate: Money(dollars: rate), seasonPrice: seasonal ? Money(dollars: season) : nil, coordinate: coordinate)
                        dismiss()
                    }
                    .disabled(name.isEmpty || address.isEmpty)
                }
            }
        }
    }
}
#endif

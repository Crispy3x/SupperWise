#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

struct CustomersView: View {
    @Environment(AppModel.self) private var model
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            List {
                if model.data.sites.isEmpty {
                    Section {
                        Text("No customers yet. Add one, or load demo data to try the app.")
                            .foregroundStyle(.secondary)
                        Button("Load demo data") { model.loadDemoData() }
                    }
                }
                ForEach(model.data.sites) { site in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.customerName(for: site)).font(.headline)
                        Text(site.address).font(.subheadline)
                        Text("Priority \(site.priority), trigger \(site.triggerInches, specifier: "%.1f") in")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Customers")
            .toolbar {
                Button { showingAdd = true } label: { Label("Add", systemImage: "plus") }
            }
            .sheet(isPresented: $showingAdd) { AddCustomerSheet() }
        }
    }
}

struct AddCustomerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var priority = 3
    @State private var trigger = 2.0
    @State private var rate = 60
    @State private var coordinate: Coordinate?
    @State private var locationNote = ""
    @State private var searching = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Customer") {
                    TextField("Name", text: $name)
                    TextField("Phone", text: $phone)
                    TextField("Service address", text: $address)
                    #if canImport(CoreLocation)
                    Button(searching ? "Looking up..." : "Find map location") {
                        searching = true
                        Task {
                            coordinate = await AddressGeocoder.coordinate(for: address)
                            locationNote = coordinate == nil ? "Address not found. The site will be left out of route ordering." : "Map location found."
                            searching = false
                        }
                    }
                    .disabled(searching || address.isEmpty)
                    if !locationNote.isEmpty { Text(locationNote).font(.footnote).foregroundStyle(.secondary) }
                    #endif
                }
                Section("Service") {
                    Stepper("Priority: \(priority) (1 is first)", value: $priority, in: 1...5)
                    Stepper("Trigger: \(trigger, specifier: "%.1f") in", value: $trigger, in: 0.5...12, step: 0.5)
                    Stepper("Price per push: $\(rate)", value: $rate, in: 10...1000, step: 5)
                }
            }
            .navigationTitle("New customer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.addCustomerWithSite(name: name, phone: phone, address: address, priority: priority,
                                                  triggerInches: trigger, perPushRate: Money(dollars: rate), coordinate: coordinate)
                        dismiss()
                    }
                    .disabled(name.isEmpty || address.isEmpty)
                }
            }
        }
    }
}
#endif

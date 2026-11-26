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
            AppPage(title: "Import clients", icon: "person.2.fill") {
                Menu {
                    Button("Add one client") { showingAdd = true }
                    Button("Import from a spreadsheet (CSV)") { showingImporter = true }
                } label: {
                    Label("Add", systemImage: "plus").font(.title3.weight(.semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Theme.accent(model.data.profile.accentColor), in: Capsule())
                }
                .buttonStyle(.plain)
                if model.data.sites.isEmpty {
                    EmptyCard(icon: "person.2", title: "No clients with an address yet", message: "Add one, or import a spreadsheet saved as CSV with Name and Address columns.")
                    // Sample clients are the owner's call only, and only while the list is empty. They are removed on the Clients tab.
                    if model.data.customers.isEmpty && model.data.contracts.isEmpty && model.data.isOwnerSession {
                        SecondaryActionButton(title: "Load sample clients to try the app") { model.loadDemoData() }
                        Text("Sample clients are made up. Remove them all with one tap on the Clients tab.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                ForEach(model.data.sites) { site in
                    NavigationLink { ClientDetailView(customerID: site.customerID).circleBack().pageBackground() } label: {
                        Card(padding: 14) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(model.customerName(for: site)).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                                    Text(site.address).font(.subheadline).foregroundStyle(.primary)
                                    Text("Priority \(site.priority), trigger \(site.triggerInches, specifier: "%.1f") in")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                    }
                    .buttonStyle(.plain)
                }
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

    private func asDouble(_ value: Binding<Int>) -> Binding<Double> {
        Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Import clients").font(.title3.weight(.medium))
                Spacer()
                CircleButton(icon: "xmark", label: "Close") { dismiss() }
            }
            .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 6)
            AppPage(clearTabBar: false) {
                CardGroup {
                    Text("\(report.clients.count) client\(report.clients.count == 1 ? "" : "s") will be added.").font(.headline)
                    if !report.skipped.isEmpty { Text("\(report.skipped.count) row\(report.skipped.count == 1 ? "" : "s") skipped.").foregroundStyle(.orange) }
                }
                CardGroup(title: "Price") {
                    PillStepper(label: "Price per push", value: asDouble($rate), range: 0...1000, step: 5, format: { $0 == 0 ? "None yet" : "$\(Int($0))" })
                    Text("With a price, each client also gets a per-push contract. With none you can add a quote later.").font(.footnote).foregroundStyle(.secondary)
                }
                CardGroup(title: "First few") {
                    ForEach(Array(report.clients.prefix(5).enumerated()), id: \.offset) { index, c in
                        VStack(alignment: .leading, spacing: 14) {
                            if index > 0 { RowDivider() }
                            VStack(alignment: .leading, spacing: 2) { Text(c.name); Text(c.address).font(.footnote).foregroundStyle(.secondary) }
                        }
                    }
                }
                if !report.skipped.isEmpty {
                    CardGroup(title: "Skipped") {
                        ForEach(Array(report.skipped.prefix(8).enumerated()), id: \.offset) { _, s in
                            Text("Row \(s.row): \(s.reason)").font(.footnote)
                        }
                    }
                }
                CardGroup {
                    Text("Nobody is marked as having agreed to messages. Open each client to record that, only if they said yes.").font(.footnote).foregroundStyle(.secondary)
                    RowDivider()
                    Text("A client without a price has no contract, so they are not billed or messaged until you add one (for example by accepting a quote).").font(.footnote).foregroundStyle(.secondary)
                }
                PrimaryActionButton(title: "Import") {
                    model.edit { _ = $0.importClients(report.clients, perPush: rate > 0 ? Money(dollars: rate) : nil, now: Date()) }
                    dismiss()
                }
                .disabled(report.clients.isEmpty).opacity(report.clients.isEmpty ? 0.4 : 1)
            }
        }
        .background(Look.sheet.ignoresSafeArea())
    }
}
#endif

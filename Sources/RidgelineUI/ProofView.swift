#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Proof-of-service packet for a site, ready to share with an insurer or customer.
struct ProofView: View {
    @Environment(AppModel.self) private var model
    @State private var siteID: UUID?

    private var site: Site? {
        model.data.sites.first { $0.id == siteID } ?? model.data.sites.first
    }

    var body: some View {
        NavigationStack {
            if let site {
                let text = DisputePacket.render(site: site, log: model.data.visitLog)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Site", selection: Binding(get: { site.id }, set: { siteID = $0 })) {
                            ForEach(model.data.sites) { Text($0.address).tag($0.id) }
                        }
                        Label(model.data.visitLog.verify() ? "Log verified: no changes since recording" : "Log has been altered",
                              systemImage: model.data.visitLog.verify() ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(model.data.visitLog.verify() ? .green : .red)
                        Text(text).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                        ShareLink(item: text) { Label("Share packet", systemImage: "square.and.arrow.up") }
                    }
                    .padding()
                }
                .navigationTitle("Proof")
            } else {
                Text("Add a customer to see proof of service.").foregroundStyle(.secondary).navigationTitle("Proof")
            }
        }
    }
}
#endif

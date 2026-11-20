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
        ScreenStack {
            if let site {
                let text = DisputePacket.render(site: site, log: model.data.visitLog)
                let verified = model.data.visitLog.verify()
                AppPage {
                    CardGroup(title: "Site") {
                        PillMenu(label: "Site", options: model.data.sites.map { ($0.id, $0.address) }, selection: Binding(get: { site.id }, set: { siteID = $0 }))
                    }
                    CardGroup {
                        Label(verified ? "Log verified: no changes since recording" : "Log has been altered",
                              systemImage: verified ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(verified ? Color.green : Color.red)
                    }
                    CardGroup(title: "Packet") {
                        Text(text).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                    }
                    ShareLink(item: text) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share packet").font(.title3.weight(.semibold))
                        }
                        .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Theme.accent(model.data.profile.accentColor), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .navigationTitle("Proof")
            } else {
                AppPage {
                    EmptyCard(icon: "checkmark.seal", title: "No proof yet", message: "Add a customer to see proof of service.")
                }
                .navigationTitle("Proof")
            }
        }
    }
}
#endif

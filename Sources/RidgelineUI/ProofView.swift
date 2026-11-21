#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Proof-of-service packet for a site, ready to share with an insurer or customer.
struct ProofView: View {
    @Environment(AppModel.self) private var model
    @State private var siteID: UUID?
    /// Photo fingerprint checks by file name, filled in the background (hashing big photos is slow).
    @State private var photoChecks: [String: PhotoCheck] = [:]

    private var site: Site? {
        model.data.sites.first { $0.id == siteID } ?? model.data.sites.first
    }

    var body: some View {
        ScreenStack {
            if let site {
                let check: (PhotoRef) -> PhotoCheck = { photoChecks[$0.filename] ?? .notChecked }
                let proofs = ProofPacket.visits(site: site, log: model.data.visitLog, photoCheck: check)
                let text = ProofPacket.render(site: site, log: model.data.visitLog, photoCheck: check)
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
                    if proofs.isEmpty {
                        EmptyCard(icon: "doc.text.magnifyingglass", title: "No visits yet", message: "Visits logged on the Crew tab show up here as proof packets.")
                    } else {
                        ForEach(Array(proofs.reversed())) { proof in VisitProofCard(proof: proof) }
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
                .task(id: "\(site.id)-\(model.data.visitLog.entries.count)") { await checkPhotos(for: site) }
            } else {
                AppPage {
                    EmptyCard(icon: "checkmark.seal", title: "No proof yet", message: "Add a customer to see proof of service.")
                }
                .navigationTitle("Proof")
            }
        }
    }

    /// Re-hashes every stored photo for the site and compares it with the fingerprint saved when it was taken.
    @MainActor private func checkPhotos(for site: Site) async {
        guard let storage = model.photoStorage else { return }
        let refs = model.data.visitLog.records(forSite: site.id).flatMap(\.photos)
        guard !refs.isEmpty else { return }
        let results = await Task.detached(priority: .utility) { () -> [String: PhotoCheck] in
            var out: [String: PhotoCheck] = [:]
            for ref in refs { out[ref.filename] = storage.check(ref) }
            return out
        }.value
        photoChecks.merge(results) { _, new in new }
    }
}

/// One visit's proof packet: times, work, location check, photos and whether the record is untouched.
private struct VisitProofCard: View {
    let proof: VisitProof

    var body: some View {
        CardGroup(title: proof.heading) {
            ForEach(Array(proof.facts.enumerated()), id: \.offset) { index, fact in
                if index > 0 { RowDivider() }
                FactRow(label: fact.label, value: fact.value, valueColor: color(fact.tone))
            }
            RowDivider()
            Label(proof.custody.text, systemImage: proof.custody.isGood ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(proof.custody.isGood ? Color.green : Color.red)
            Text("Record code " + String(proof.fingerprint.prefix(16)))
                .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func color(_ tone: ProofFact.Tone) -> Color {
        switch tone {
        case .normal: return .primary
        case .good: return .green
        case .warning: return .orange
        case .bad: return .red
        }
    }
}
#endif

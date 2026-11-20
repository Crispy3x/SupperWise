#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Start of winter: email each client who agreed their private page link, which works the whole season.
struct SeasonLinksSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirming = false
    @State private var working = false
    @State private var result: String?

    private func reason(_ r: SkipReason) -> String {
        switch r {
        case .optedOut: return "asked to stop"
        case .noConsent: return "has not agreed to emails"
        case .noValidContact: return "has no valid email"
        case .alreadySent: return "already has this season's link"
        case .noContract: return "has no contract"
        case .noPortalLink: return "has no page yet"
        }
    }

    var body: some View {
        let plan = model.seasonLinkPlan()
        VStack(spacing: 14) {
            HStack {
                CircleButton(icon: "xmark", label: "Close") { dismiss() }
                Spacer(); Text("Winter page links").font(.title3.weight(.semibold)); Spacer()
                Color.clear.frame(width: 50, height: 50)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Send each client their private page for \(plan.season). It works all season: live truck map and arrival time, ask for service, see bills, and say thanks to the driver.")
                        .font(.title3).foregroundStyle(.secondary)
                    if !plan.problem.isEmpty {
                        Label(plan.problem, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
                    } else {
                        Card {
                            VStack(alignment: .leading, spacing: 8) {
                                CapsLabel(text: "Ready to send")
                                Text("\(plan.messages.count) client\(plan.messages.count == 1 ? "" : "s")").font(.system(size: 36, weight: .bold, design: .rounded))
                            }
                        }
                        if !plan.skipped.isEmpty {
                            CapsLabel(text: "Left out")
                            ForEach(Array(plan.skipped.enumerated()), id: \.offset) { _, s in
                                Text("\(s.customerName) \(reason(s.reason))").font(.callout).foregroundStyle(.secondary)
                            }
                        }
                        Button { confirming = true } label: {
                            Label(working ? "Sending..." : "Email \(plan.messages.count) link\(plan.messages.count == 1 ? "" : "s")", systemImage: "paperplane.fill")
                                .font(.title3.weight(.semibold)).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 18)
                                .background(Theme.accent(model.data.profile.accentColor).opacity(plan.messages.isEmpty ? 0.4 : 1), in: Capsule())
                        }
                        .buttonStyle(.plain).disabled(plan.messages.isEmpty || working)
                        .alert("Email \(plan.messages.count) client\(plan.messages.count == 1 ? "" : "s")?", isPresented: $confirming) {
                            Button("Send") { working = true; Task { result = await model.sendSeasonLinks(); working = false } }
                            Button("Cancel", role: .cancel) {}
                        } message: { Text("Only clients who agreed to emails. Nobody gets it twice in one season.") }
                    }
                    if let result { Text(result).font(.callout).foregroundStyle(.secondary) }
                }
                .padding(.bottom, 30)
            }
        }
        .padding(.horizontal, 18).padding(.top, 16)
        .background(Look.sheet.ignoresSafeArea())
    }
}
#endif

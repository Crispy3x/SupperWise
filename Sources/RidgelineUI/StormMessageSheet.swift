#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Review and send the storm-start message to clients. Nothing is sent until you tap Send.
struct StormMessageSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let inches: Double
    let routeStart: Date
    let offsets: [UUID: Double]

    @State private var storm: StormEvent?
    @State private var urgent = false
    @State private var sending = false
    @State private var result: String?

    private var plan: BroadcastPlan? {
        storm.map { model.broadcastPlan(storm: $0, inches: inches, urgent: urgent) }
    }

    private func reasonText(_ r: SkipReason) -> String {
        switch r {
        case .optedOut: return "asked to stop"
        case .noConsent: return "have not agreed to messages"
        case .noValidContact: return "have no valid email"
        case .alreadySent: return "already got this storm's message"
        case .noContract: return "have no contract"
        case .noPortalLink: return "have no client page (set the page address in Settings)"
        }
    }

    private var cannotSend: Bool { sending || (plan?.messages.isEmpty ?? true) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Message clients").font(.title3.weight(.medium))
                Spacer()
                CircleButton(icon: "xmark", label: "Close") { dismiss() }
            }
            .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 6)
            AppPage(clearTabBar: false) {
                if let plan {
                    CardGroup(title: "Who gets a message") {
                        Text("\(plan.messages.count) client\(plan.messages.count == 1 ? "" : "s") will get an email about \(SnowEstimateText.describe(forecastInches: inches)).")
                        let held = plan.messages.filter { $0.sendAfter > Date() }.count
                        if held > 0 {
                            Text("\(held) will wait until quiet hours end. Turn on urgent below to send them now.")
                                .font(.footnote).foregroundStyle(.orange)
                        }
                    }
                    let groups = Dictionary(grouping: plan.skipped, by: \.reason)
                    if !groups.isEmpty {
                        CardGroup(title: "Not getting one") {
                            ForEach(groups.keys.sorted { $0.rawValue < $1.rawValue }, id: \.self) { reason in
                                Text("\(groups[reason]?.count ?? 0) \(reasonText(reason))")
                            }
                        }
                    }
                    if let first = plan.messages.first {
                        CardGroup(title: "Preview") {
                            Text(first.subject).font(.subheadline.bold())
                            Text(first.body).font(.footnote)
                        }
                    }
                }
                CardGroup(footer: "Clients can reply to stop messages, and you can mark them as stopped in their details. Anyone who asked to stop is never messaged.") {
                    Toggle("Urgent: send now, even in quiet hours", isOn: $urgent)
                }
                PrimaryActionButton(title: sending ? "Sending..." : "Send now", icon: "paperplane") { send() }
                    .disabled(cannotSend)
                    .opacity(cannotSend ? 0.4 : 1)
                if let result { Text(result).font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Look.sheet.ignoresSafeArea())
        .onAppear {
            model.prepareClientPages()
            storm = model.ensureStorm(inches: inches)
        }
    }

    private func send() {
        guard let storm, let plan else { return }
        sending = true
        Task {
            result = await model.sendBroadcast(storm: storm, inches: inches, plan: plan, routeStart: routeStart, offsets: offsets)
            sending = false
        }
    }
}
#endif

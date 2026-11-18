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

    var body: some View {
        NavigationStack {
            Form {
                if let plan {
                    Section("Who gets a message") {
                        Text("\(plan.messages.count) client\(plan.messages.count == 1 ? "" : "s") will get an email about \(SnowEstimateText.describe(forecastInches: inches)).")
                        let held = plan.messages.filter { $0.sendAfter > Date() }.count
                        if held > 0 {
                            Text("\(held) will wait until quiet hours end. Turn on urgent below to send them now.")
                                .font(.footnote).foregroundStyle(.orange)
                        }
                    }
                    let groups = Dictionary(grouping: plan.skipped, by: \.reason)
                    if !groups.isEmpty {
                        Section("Not getting one") {
                            ForEach(groups.keys.sorted { $0.rawValue < $1.rawValue }, id: \.self) { reason in
                                Text("\(groups[reason]?.count ?? 0) \(reasonText(reason))")
                            }
                        }
                    }
                    if let first = plan.messages.first {
                        Section("Preview") {
                            Text(first.subject).font(.subheadline.bold())
                            Text(first.body).font(.footnote)
                        }
                    }
                }
                Section {
                    Toggle("Urgent: send now, even in quiet hours", isOn: $urgent)
                    Text("Clients can reply to stop messages, and you can mark them as stopped in their details. Anyone who asked to stop is never messaged.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Button(sending ? "Sending..." : "Send now") { send() }
                        .disabled(sending || (plan?.messages.isEmpty ?? true))
                    if let result { Text(result).font(.footnote) }
                }
            }
            .navigationTitle("Message clients")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear {
                model.prepareClientPages()
                storm = model.ensureStorm(inches: inches)
            }
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

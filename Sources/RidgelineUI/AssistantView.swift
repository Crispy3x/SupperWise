#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// The purple sparkle button opens this: a chat with the assistant, which can look things up, schedule jobs, plan the
/// route, add clients and prepare invoices. Anything that reaches a client waits for the person's tap.
struct AssistantView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack {
            Group {
                if !model.data.assistantConsented { ConsentCard() }
                else if !model.serverConfigured { SetupCard() }
                else { chat }
            }
            .background(Look.page)
            .navigationTitle("Assistant")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                if model.data.assistantConsented {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("New chat", systemImage: "square.and.pencil") { model.startNewAssistantChat() }.disabled(model.assistantBusy)
                            Button("Turn off the assistant", systemImage: "power", role: .destructive) { model.turnOffAssistant() }
                        } label: { Label("Options", systemImage: "ellipsis.circle") }
                    }
                }
            }
            .task { await model.refreshAssistantStatus() }
        }
    }

    private var suggestions: [String] {
        var s = ["What is on today?", "Plan today's route"]
        if model.data.can(.viewRevenue) { s.append("Which invoices are overdue?") }
        if model.data.can(.editJobs) { s.append("Book a job for tomorrow at 8") }
        return s
    }

    private var chat: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if model.assistantLines.isEmpty {
                            VStack(spacing: 14) {
                                IconTile(icon: "sparkles", tint: Look.sparkle, size: 64)
                                Text("What can I help with?").font(.title2.bold())
                                Text("I can look up jobs, clients and invoices, schedule jobs, add clients and plan your route. I always ask you to tap Send before anything goes to a client.")
                                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                                ForEach(suggestions, id: \.self) { s in
                                    Button { send(s) } label: {
                                        Text(s).font(.callout).padding(.horizontal, 14).padding(.vertical, 10)
                                            .background(Look.card, in: Capsule()).overlay(Capsule().stroke(Look.stroke, lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.top, 30).padding(.horizontal, 20)
                        }
                        ForEach(model.assistantLines) { line in LineView(line: line).id(line.id) }
                        if model.assistantBusy {
                            HStack(spacing: 8) { ProgressView(); Text("Thinking...").foregroundStyle(.secondary) }
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).id("busy")
                        }
                    }
                    .padding(.vertical, 12)
                }
                .onChange(of: model.assistantLines.count) { _, _ in
                    if let last = model.assistantLines.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            if let used = model.assistantUsedPercent, used >= 80 {
                Text(used >= 100 ? "This month's assistant allowance is used up." : "\(used)% of this month's assistant allowance is used.")
                    .font(.footnote).foregroundStyle(used >= 100 ? Color.red : Color.orange).padding(.vertical, 4)
            }
            HStack(spacing: 10) {
                TextField("Ask anything...", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($typing)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(Look.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Look.stroke, lineWidth: 1))
                    .onSubmit { send(draft) }
                Button { send(draft) } label: {
                    Image(systemName: "arrow.up").font(.headline).foregroundStyle(.white).frame(width: 44, height: 44)
                        .background(Look.sparkle, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.assistantBusy)
                .accessibilityLabel("Send")
            }
            .padding(12)
        }
    }

    private func send(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !model.assistantBusy else { return }
        draft = ""
        Task { await model.askAssistant(t) }
    }
}

private struct LineView: View {
    @Environment(AppModel.self) private var model
    let line: AssistantLine

    var body: some View {
        switch line.kind {
        case .user:
            Text(line.text).padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.accent(model.data.profile.accentColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .trailing).padding(.leading, 50).padding(.trailing, 16)
        case .assistant:
            VStack(alignment: .leading, spacing: 8) {
                Text(line.text).textSelection(.enabled)
                ForEach(line.actions, id: \.self) { Label($0, systemImage: "checkmark.circle.fill").font(.footnote).foregroundStyle(.green) }
                ForEach(line.pending) { action in PendingCard(action: action) }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Look.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Look.stroke, lineWidth: 1))
            .frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 40).padding(.leading, 16)
        case .note:
            Label(line.text, systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.horizontal, 16)
        case .problem:
            Label(line.text, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16)
        }
    }
}

/// Something the assistant prepared. It is only done when the person taps Send.
private struct PendingCard: View {
    @Environment(AppModel.self) private var model
    let action: PendingAction
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(action.title).font(.headline)
            Text(action.detail).font(.footnote).foregroundStyle(.secondary)
            HStack {
                Button { working = true; Task { await model.confirmPending(action) } } label: {
                    Label(working ? "Sending..." : "Send", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent).disabled(working)
                Button("Cancel") { model.cancelPending(action) }.buttonStyle(.bordered).disabled(working)
            }
        }
        .padding(12)
        .background(Look.page, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Asked once, in plain words, before any question leaves the phone.
private struct ConsentCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                IconTile(icon: "sparkles", tint: Look.sparkle, size: 64)
                Text("Before you use the assistant").font(.title2.bold())
                Text("The assistant is an AI service (Anthropic's Claude). To answer, it needs two things to leave your phone:")
                Label("What you type to it", systemImage: "text.bubble")
                Label("Details it looks up to help: job titles and times, client names and addresses, invoice numbers and amounts, team member names", systemImage: "list.bullet.rectangle")
                Text("These go through your own server to Anthropic, which writes the reply. Client phone numbers and email addresses are never sent, and the app never sends anything to a client until you tap Send.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("You can turn the assistant off at any time from the menu in this screen.").font(.callout).foregroundStyle(.secondary)
                Button { model.grantAssistantConsent() } label: {
                    Text("Agree and continue").font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Look.sparkle, in: Capsule())
                }
                .buttonStyle(.plain)
                Button("Not now") { dismiss() }.frame(maxWidth: .infinity)
            }
            .padding(24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct SetupCard: View {
    var body: some View {
        VStack(spacing: 12) {
            IconTile(icon: "server.rack", tint: .orange, size: 64)
            Text("The assistant needs your server").font(.title3.bold())
            Text("It runs through the server you set up for routing and client pages, so your AI key stays off the phone. Add the server address and access token in Settings, then come back.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(30)
    }
}
#endif

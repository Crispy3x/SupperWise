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
    #if canImport(Speech) && os(iOS)
    @State private var speech = SpeechInput()
    #endif

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                if !model.data.assistantConsented { ConsentCard() }
                else if !model.serverConfigured { SetupCard() }
                else { chat }
            }
        }
        .background(Look.sheet.ignoresSafeArea())
        .task { await model.refreshAssistantStatus() }
    }

    private var header: some View {
        HStack {
            Text("Assistant").font(.title3.weight(.medium)).foregroundStyle(.secondary)
            Spacer()
            if model.data.assistantConsented {
                Menu {
                    Button("Turn off the assistant", systemImage: "power", role: .destructive) { model.turnOffAssistant() }
                } label: { Image(systemName: "ellipsis").font(.title3).foregroundStyle(.secondary).frame(width: 40, height: 40) }
                Button { model.startNewAssistantChat() } label: { Image(systemName: "square.and.pencil").font(.title2).foregroundStyle(.secondary).frame(width: 44, height: 44) }
                    .buttonStyle(.plain).disabled(model.assistantBusy).accessibilityLabel("New chat")
            }
            CircleButton(icon: "xmark", label: "Close") { dismiss() }
        }
        .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 6)
    }

    private var suggestions: [String] {
        var s = ["Today's schedule"]
        if model.data.can(.viewRevenue) { s.append("Which invoices are overdue?") } else { s.append("Plan today's route") }
        if model.data.can(.editClients) { s.append("Add a client") }
        if model.data.can(.editJobs) { s.append("Create a job") }
        if model.data.can(.viewRevenue) { s.append("Invoice a client") }
        return s
    }

    private var chat: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if model.assistantLines.isEmpty { emptyState }
                        ForEach(model.assistantLines) { line in LineView(line: line).id(line.id) }
                        if model.assistantBusy {
                            HStack(spacing: 8) { ProgressView(); Text("Thinking...").foregroundStyle(.secondary) }
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16)
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
            #if canImport(Speech) && os(iOS)
            if let p = speech.problem { Text(p).font(.footnote).foregroundStyle(.orange).padding(.horizontal, 20) }
            #endif
            if model.assistantLines.isEmpty {
                Text(micAvailable ? "Tap the mic and speak, or type below." : "Type below.").font(.title3).foregroundStyle(.secondary).padding(.bottom, 10)
                FlowChips(items: suggestions) { send($0) }.padding(.horizontal, 16).padding(.bottom, 14)
            }
            inputBar
        }
    }

    private var micAvailable: Bool {
        #if canImport(Speech) && os(iOS)
        return true
        #else
        return false
        #endif
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            #if canImport(Speech) && os(iOS)
            Button { Task { await speech.toggle() } } label: {
                ZStack {
                    Circle().fill(Look.sparkle.opacity(speech.isListening ? 0.45 : 0.18)).frame(width: 230, height: 230)
                    Image(systemName: speech.isListening ? "waveform" : "sparkles").font(.system(size: 64)).foregroundStyle(Color(red: 0.74, green: 0.65, blue: 1))
                }
            }
            .buttonStyle(.plain).accessibilityLabel(speech.isListening ? "Stop listening" : "Tap to talk")
            Text(speech.isListening ? (speech.transcript.isEmpty ? "Listening..." : speech.transcript) : "Tap to talk").font(.title2).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 24)
            #else
            ZStack { Circle().fill(Look.sparkle.opacity(0.18)).frame(width: 200, height: 200); Image(systemName: "sparkles").font(.system(size: 64)).foregroundStyle(Color(red: 0.74, green: 0.65, blue: 1)) }
            Text("What can I help with?").font(.title2).foregroundStyle(.secondary)
            #endif
        }
        .frame(maxWidth: .infinity).padding(.top, 70).padding(.bottom, 20)
        #if canImport(Speech) && os(iOS)
        .onChange(of: speech.transcript) { _, new in if speech.isListening { draft = new } }
        #endif
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            #if canImport(Speech) && os(iOS)
            Button { Task { await speech.toggle() } } label: {
                Image(systemName: speech.isListening ? "stop.circle.fill" : "mic").font(.title2).foregroundStyle(speech.isListening ? Color.red : Color.secondary)
            }
            .buttonStyle(.plain).accessibilityLabel(speech.isListening ? "Stop listening" : "Speak")
            #endif
            TextField("Type a message...", text: $draft, axis: .vertical)
                .font(.title3).lineLimit(1...4).focused($typing)
                .onSubmit { send(draft) }
            Button { send(draft) } label: {
                Image(systemName: "arrow.up").font(.headline).foregroundStyle(.white).frame(width: 52, height: 52)
                    .background(Look.sparkle.opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.assistantBusy)
            .accessibilityLabel("Send")
        }
        .padding(.leading, 22).padding(.trailing, 8).padding(.vertical, 8)
        .background(Look.field, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).stroke(Look.fieldStroke, lineWidth: 1))
        .padding(.horizontal, 16).padding(.bottom, 12)
    }

    private func send(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !model.assistantBusy else { return }
        #if canImport(Speech) && os(iOS)
        speech.stop()
        #endif
        draft = ""
        Task { await model.askAssistant(t) }
    }
}

/// Suggestion buttons that wrap onto more than one row.
private struct FlowChips: View {
    let items: [String]
    let pick: (String) -> Void
    var body: some View {
        VStack(spacing: 10) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.self) { item in
                        Button { pick(item) } label: {
                            Text(item).font(.title3).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.75)
                                .padding(.horizontal, 18).padding(.vertical, 12)
                                .overlay(Capsule().stroke(Look.fieldStroke, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    private var rows: [[String]] { stride(from: 0, to: items.count, by: 2).map { Array(items[$0..<min($0 + 2, items.count)]) } }
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

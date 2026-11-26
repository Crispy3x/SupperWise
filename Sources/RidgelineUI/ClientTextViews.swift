#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore
#if canImport(MessageUI) && canImport(UIKit)
import MessageUI
#endif
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A text ready for Messages, with the after photo when one is attached.
struct PendingClientText: Identifiable {
    let id = UUID()
    let draft: ClientTextDraft
    let photo: Data?
}

/// Opens Messages with a text filled in. On a Mac, where there is no Messages composer, the text is shown to copy.
@MainActor
enum ClientTextLauncher {
    /// True when this device can show the Messages composer inside the app.
    static var canCompose: Bool {
        #if canImport(MessageUI) && canImport(UIKit)
        return MFMessageComposeViewController.canSendText()
        #else
        return false
        #endif
    }

    /// True when a photo can go with the text.
    static var canAttachPhoto: Bool {
        #if canImport(MessageUI) && canImport(UIKit)
        return MFMessageComposeViewController.canSendText() && MFMessageComposeViewController.canSendAttachments()
        #else
        return false
        #endif
    }

    static func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    /// Composer when available, otherwise an sms: link; on a Mac, or when Messages will not open, the copy card.
    static func launch(_ draft: ClientTextDraft, photo: Data?, model: AppModel, openURL: OpenURLAction,
                       pending: Binding<PendingClientText?>, copied: Binding<ClientTextDraft?>, problem: Binding<String?>) {
        problem.wrappedValue = nil
        #if os(macOS)
        copied.wrappedValue = draft
        #else
        if canCompose {
            pending.wrappedValue = PendingClientText(draft: draft, photo: photo)
        } else if let url = draft.smsURL {
            // We cannot see whether it was sent, so opening Messages counts as sent.
            openURL(url) { accepted in
                if accepted {
                    problem.wrappedValue = model.recordClientText(draft.kind, jobID: draft.jobID)
                } else {
                    copied.wrappedValue = draft
                }
            }
        } else {
            copied.wrappedValue = draft
        }
        #endif
    }
}

#if canImport(MessageUI) && canImport(UIKit)
/// The system Messages composer, filled in. Reports whether the text was actually sent.
struct MessageComposer: UIViewControllerRepresentable {
    let text: PendingClientText
    let onFinish: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let composer = MFMessageComposeViewController()
        composer.messageComposeDelegate = context.coordinator
        composer.recipients = [text.draft.recipient]
        composer.body = text.draft.body
        if let photo = text.photo, MFMessageComposeViewController.canSendAttachments() {
            _ = composer.addAttachmentData(photo, typeIdentifier: "public.jpeg", filename: "after-photo.jpg")
        }
        return composer
    }

    func updateUIViewController(_ controller: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinish: (Bool) -> Void
        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }

        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            onFinish(result == .sent)
        }
    }
}
#endif

/// Shows the Messages composer for a pending text and notes the text on the job once it is sent.
private struct ClientTextComposerHost: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var pending: PendingClientText?
    @Binding var problem: String?

    func body(content: Content) -> some View {
        #if canImport(MessageUI) && canImport(UIKit)
        content.sheet(item: $pending) { p in
            MessageComposer(text: p) { sent in
                pending = nil
                if sent { problem = model.recordClientText(p.draft.kind, jobID: p.draft.jobID) }
            }
            .ignoresSafeArea()
        }
        #else
        content
        #endif
    }
}

/// When Messages is not available here: the text to copy, then "Mark as sent".
private struct CopyClientTextCard: View {
    @Environment(AppModel.self) private var model
    let draft: ClientTextDraft
    @Binding var copied: ClientTextDraft?
    @Binding var problem: String?
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardGroup(title: "Send from your phone", footer: "Copy the text, send it from your phone, then tap Mark as sent.") {
                FactRow(label: "To", value: draft.recipient)
                RowDivider()
                Text(draft.body).font(.callout).textSelection(.enabled)
            }
            SecondaryActionButton(title: didCopy ? "Copied" : "Copy text", icon: "doc.on.doc") {
                ClientTextLauncher.copy(draft.body)
                didCopy = true
            }
            PrimaryActionButton(title: "Mark as sent", icon: "checkmark") {
                problem = model.recordClientText(draft.kind, jobID: draft.jobID)
                if problem == nil { copied = nil }
            }
        }
    }
}

/// "Text client" on a job: one tap opens Messages with "On my way" or "Job done" filled in.
struct ClientTextSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    /// The job, or for a repeating job the visit on screen.
    let job: Job

    @State private var etaMinutes = 15.0
    @State private var attachPhoto = true
    @State private var pending: PendingClientText?
    @State private var copied: ClientTextDraft?
    @State private var problem: String?
    @State private var loaded = false

    private var allowed: Bool {
        !job.isTask && job.status != .cancelled && (model.data.can(.editJobs) || model.data.can(.logVisits))
            && model.data.clientTextCustomer(for: job) != nil
    }
    /// Today's visit, or a storm job from last night that is still on today's list.
    private var isToday: Bool {
        Calendar.current.isDateInToday(job.start) || (!job.repeats && model.data.jobs(on: Date()).contains { $0.id == job.id })
    }
    private var hasAfterPhoto: Bool {
        ClientTextLauncher.canAttachPhoto && model.data.latestAfterPhoto(siteID: job.siteID, on: Date()) != nil
    }
    private var sentLines: [String] {
        job.sentTexts(forVisitOn: job.start).map { ClientTexts.sentLine($0, now: Date()) }
    }

    var body: some View {
        if allowed && (isToday || !sentLines.isEmpty) {
            VStack(alignment: .leading, spacing: 12) {
                if isToday { sendCard } else { logCard }
                if let copied { CopyClientTextCard(draft: copied, copied: $copied, problem: $problem) }
                if let problem { Text(problem).font(.footnote).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading) }
            }
            .modifier(ClientTextComposerHost(pending: $pending, problem: $problem))
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let seconds = model.plannedDriveSeconds(toJob: job.id), let m = ClientTexts.roundedETAMinutes(seconds) {
                    etaMinutes = Double(min(m, 180))
                }
            }
        }
    }

    @ViewBuilder private var sendCard: some View {
        let blocker = model.data.clientTextBlocker(jobID: job.id)
        CardGroup(title: "Text client", footer: blocker == nil ? "Opens Messages on this phone. Nothing goes out until you tap Send." : nil) {
            if let blocker {
                Text(blocker.message).font(.callout).foregroundStyle(.secondary)
            } else {
                let tint = Theme.accent(model.data.profile.accentColor)
                Button { send(.onMyWay) } label: {
                    CardLinkRow(icon: "car.fill", tint: tint, title: ClientTextKind.onMyWay.title,
                                detail: lastLine(.onMyWay) ?? "Arriving in about \(Int(etaMinutes)) min")
                }
                .buttonStyle(.plain)
                RowDivider()
                Button { send(.done) } label: {
                    CardLinkRow(icon: "checkmark.seal.fill", tint: .green, title: ClientTextKind.done.title,
                                detail: lastLine(.done) ?? (hasAfterPhoto && attachPhoto ? "With today's after photo" : "Lets them know you finished"))
                }
                .buttonStyle(.plain)
            }
        }
        if blocker == nil {
            PillStepper(label: "Arriving in", value: $etaMinutes, range: 5...180, step: 5, format: { "\(Int($0)) min" })
            if hasAfterPhoto {
                PillChoice(options: [(true, "Add after photo", "photo"), (false, "No photo", "text.bubble")], selection: $attachPhoto)
            }
        }
    }

    private var logCard: some View {
        CardGroup(title: "Texts sent") {
            ForEach(Array(sentLines.enumerated()), id: \.offset) { index, line in
                if index > 0 { RowDivider() }
                Text(line).font(.callout)
            }
        }
    }

    private func lastLine(_ kind: ClientTextKind) -> String? {
        job.lastSentText(kind, forVisitOn: job.start).map { ClientTexts.sentLine($0, now: Date()) }
    }

    private func send(_ kind: ClientTextKind) {
        let photo = (kind == .done && attachPhoto && hasAfterPhoto) ? model.todaysAfterPhotoData(for: job) : nil
        switch model.data.clientTextDraft(kind, jobID: job.id, etaSeconds: kind == .onMyWay ? etaMinutes * 60 : nil, withPhoto: photo != nil) {
        case .failure(let blocker):
            problem = blocker.message
        case .success(let draft):
            ClientTextLauncher.launch(draft, photo: photo, model: model, openURL: openURL,
                                      pending: $pending, copied: $copied, problem: $problem)
        }
    }
}

/// In the Smart route: "Text next client: on my way" for the first stop that is still scheduled.
struct NextStopTextButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let plan: RoutePlanResult
    let day: Date

    @State private var pending: PendingClientText?
    @State private var copied: ClientTextDraft?
    @State private var problem: String?

    private var nextJob: Job? {
        guard let id = model.data.nextStopToText(order: plan.stops.map(\.id), on: day) else { return nil }
        return model.data.jobs(on: day).first { $0.id == id }
    }

    var body: some View {
        if Calendar.current.isDateInToday(day), model.data.can(.editJobs) || model.data.can(.logVisits), let job = nextJob {
            let who = model.data.customerName(forJob: job)
            let blocker = model.data.clientTextBlocker(jobID: job.id)
            let drive = plan.planned.first { $0.stop.id == job.id }?.driveSeconds
            VStack(alignment: .leading, spacing: 12) {
                if blocker == nil {
                    SecondaryActionButton(title: "Text next client: on my way", icon: "message.fill") { send(job, drive: drive) }
                }
                Text(note(job: job, who: who, blocker: blocker, drive: drive))
                    .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
                if let copied { CopyClientTextCard(draft: copied, copied: $copied, problem: $problem) }
                if let problem { Text(problem).font(.footnote).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading) }
            }
            .modifier(ClientTextComposerHost(pending: $pending, problem: $problem))
        }
    }

    private func note(job: Job, who: String, blocker: ClientTextBlocker?, drive: Double?) -> String {
        let name = who.isEmpty ? job.title : who
        if let blocker { return "Next stop: \(name). \(blocker.message)" }
        if let sent = job.lastSentText(.onMyWay, forVisitOn: day) { return "Next stop: \(name). \(ClientTexts.sentLine(sent, now: Date()))." }
        guard let minutes = drive.flatMap(ClientTexts.roundedETAMinutes) else { return "Next stop: \(name)." }
        return "Next stop: \(name), arriving in about \(minutes) min."
    }

    private func send(_ job: Job, drive: Double?) {
        switch model.data.clientTextDraft(.onMyWay, jobID: job.id, etaSeconds: drive) {
        case .failure(let blocker):
            problem = blocker.message
        case .success(let draft):
            ClientTextLauncher.launch(draft, photo: nil, model: model, openURL: openURL,
                                      pending: $pending, copied: $copied, problem: $problem)
        }
    }
}
#endif

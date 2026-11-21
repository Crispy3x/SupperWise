#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Settings: where clients leave a review, and whether the app suggests asking.
struct ReviewSettingsCard: View {
    @Environment(AppModel.self) private var model
    @State private var draft = ""
    @State private var loaded = false

    var body: some View {
        CardGroup(title: "Reviews",
                  footer: "You send review requests from your own phone or email. Each client is asked at most once every 90 days, and never if they asked to stop messages.") {
            if model.data.can(.manageSettings) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Text("Review link").font(.title3.weight(.medium))
                        Text("(optional)").font(.title3).foregroundStyle(.secondary)
                    }
                    TextField("https://g.page/r/...", text: $draft)
                        .font(.title3)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .padding(.horizontal, 22).padding(.vertical, 16)
                        .background(Look.field, in: Capsule())
                        .overlay(Capsule().stroke(Look.fieldStroke, lineWidth: 1))
                    if let problem = ReviewLink.problem(for: draft) {
                        Label(problem, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
                    } else if ReviewLink.clean(draft) != nil {
                        Label("Saved. Review requests will include this link.", systemImage: "checkmark.circle").font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("Paste your Google review link (from your Google Business Profile), or your Yelp, Facebook or Nextdoor page.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                RowDivider()
                Toggle("Suggest a review request after a paid invoice or a thank-you message",
                       isOn: Binding(get: { model.data.profile.reviewSuggestionsOn },
                                     set: { model.data.profile.reviewSuggestionsEnabled = $0; model.save() }))
            } else {
                FactRow(label: "Review link", value: model.data.profile.reviewLink == nil ? "Not set" : "Set")
            }
        }
        .onAppear {
            if !loaded { draft = model.data.profile.reviewLink ?? ""; loaded = true }
        }
        .onChange(of: draft) { _, new in
            let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if model.data.profile.reviewLink != nil { model.data.profile.reviewLink = nil; model.save() }
            } else if let ok = ReviewLink.clean(trimmed), ok != model.data.profile.reviewLink {
                model.data.profile.reviewLink = ok; model.save()
            }
        }
    }
}

/// "Ask for a review" for one client. Shown on the client profile, on paid invoices and on thank-you messages.
/// It stands out when the app suggests asking (a recent paid invoice or thank-you, and the switch in Settings is on).
struct ReviewAskButton: View {
    @Environment(AppModel.self) private var model
    let customerID: UUID
    /// The screen already shows the client is happy: a paid invoice or a thank-you message.
    var happyNow = false
    /// Show nothing unless the app is suggesting a review right now.
    var onlyWhenSuggested = false
    @State private var showing = false

    private func blocker(_ now: Date) -> ReviewAskBlocker? {
        if case .failure(let b)? = model.data.reviewDraft(customerID: customerID, now: now) { return b }
        return nil
    }

    private func suggested(_ now: Date) -> Bool {
        guard model.data.profile.reviewSuggestionsOn,
              case .success? = model.data.reviewDraft(customerID: customerID, now: now) else { return false }
        return happyNow || model.data.shouldSuggestReview(customerID: customerID, now: now)
    }

    var body: some View {
        let now = Date()
        let exists = model.data.customers.contains { $0.id == customerID }
        let suggest = suggested(now)
        let blocked = blocker(now)
        // Stays while its sheet is open, so recording the ask does not pull the sheet away.
        if exists && model.data.can(.editClients) && (suggest || !onlyWhenSuggested || showing) {
            VStack(alignment: .leading, spacing: 8) {
                if suggest {
                    Label(happyNow ? "Happy clients are the best ones to ask for a review."
                                   : "They paid or thanked you recently. A good time to ask for a review.",
                          systemImage: "star.fill")
                        .font(.footnote).foregroundStyle(.secondary)
                    PrimaryActionButton(title: "Ask for a review", icon: "star.bubble") { showing = true }
                } else {
                    SecondaryActionButton(title: "Ask for a review", icon: "star.bubble") { showing = true }
                        .disabled(blocked != nil).opacity(blocked == nil ? 1 : 0.5)
                }
                if let blocked { Text(blocked.message).font(.footnote).foregroundStyle(.secondary) }
            }
            .sheet(isPresented: $showing) { ReviewRequestSheet(customerID: customerID) }
        }
    }
}

/// Shows the review request and sends it the owner's way: Messages, Mail or the share sheet. Records the ask when sent.
struct ReviewRequestSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let customerID: UUID
    @State private var draft: ReviewRequestDraft?
    @State private var blocker: ReviewAskBlocker?
    @State private var loaded = false
    @State private var recorded = false
    @State private var note: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Ask for a review").font(.title3.weight(.medium))
                Spacer()
                CircleButton(icon: "xmark", label: "Close") { dismiss() }
            }
            .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 6)
            AppPage(clearTabBar: false) {
                if let draft {
                    CardGroup(title: "Message", footer: "It goes from your own phone or email. No server needed.") {
                        Text(draft.text).font(.callout).textSelection(.enabled)
                    }
                    #if os(iOS)
                    if let sms = draft.smsURL {
                        PrimaryActionButton(title: "Text it", icon: "message.fill") { send(sms) }
                    }
                    #endif
                    if let mail = draft.mailURL {
                        SecondaryActionButton(title: "Email it", icon: "envelope.fill") { send(mail) }
                    }
                    CardGroup {
                        ShareLink(item: draft.text, subject: Text(draft.subject)) {
                            CardLinkRow(icon: "square.and.arrow.up", tint: .blue, title: "Share another way",
                                        detail: "WhatsApp, Messenger, or copy the text")
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded { record() })
                    }
                    if let note {
                        Text(note).font(.footnote).foregroundStyle(.secondary)
                            .padding(.horizontal, 6).frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if let blocker {
                    EmptyCard(icon: "star", title: "Not right now", message: blocker.message)
                } else if loaded {
                    EmptyCard(icon: "person.fill.questionmark", title: "Client not found", message: "This client no longer exists.")
                }
            }
        }
        .background(Look.sheet.ignoresSafeArea())
        .onAppear { load() }
    }

    private func load() {
        guard !loaded else { return }
        switch model.data.reviewDraft(customerID: customerID, now: Date()) {
        case .success(let d)?: draft = d
        case .failure(let b)?: blocker = b
        case nil: break
        }
        loaded = true
    }

    private func send(_ url: URL) {
        openURL(url)
        record()
    }

    /// Saves the date on the client so they are not asked again for 90 days. Only once per sheet.
    private func record() {
        guard !recorded else { return }
        var reason: String?
        let problem = model.edit { data in
            do { try data.recordReviewAsked(customerID: customerID, now: Date()) } catch let b as ReviewAskBlocker {
                reason = b.message
                throw b
            }
        }
        if let problem {
            note = reason ?? problem
        } else {
            recorded = true
            note = "Saved as asked today. We will not suggest asking this client again for 90 days."
        }
    }
}
#endif

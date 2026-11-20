#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Where the owner pastes a payment link from their own account. The app never handles the money.
struct PayLinkField: View {
    @Binding var link: String
    var placeholder = "Payment link (optional), https://..."
    var help = "Paste a link from Stripe, Square, PayPal, Venmo, Cash App, QuickBooks or Wave. We never touch the money."
    var goodNote = "Clients get a Pay now button. Payments go to your own account."
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(placeholder, text: $link)
                .autocorrectionDisabled()
#if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
#endif
            if let problem = PayLink.problem(for: link) {
                Label(problem, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
            } else if PayLink.clean(link) != nil {
                Label(goodNote, systemImage: "checkmark.circle")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Text(help)
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

/// Settings version: keeps what the owner is typing, and saves only a link that passes the check.
struct SavedPayLinkField: View {
    @Environment(AppModel.self) private var model
    @State private var draft = ""
    @State private var loaded = false
    var body: some View {
        PayLinkField(link: $draft)
            .onAppear {
                if !loaded { draft = model.data.profile.payLink ?? ""; loaded = true }
            }
            .onChange(of: draft) { _, new in
                let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    if model.data.profile.payLink != nil { model.data.profile.payLink = nil; model.save() }
                } else if let ok = PayLink.clean(trimmed), ok != model.data.profile.payLink {
                    model.data.profile.payLink = ok; model.save()
                }
            }
    }
}

/// Settings version for the tip and coffee links on client pages. Saves only a link that passes the check.
struct SavedProfileLinkField: View {
    @Environment(AppModel.self) private var model
    let placeholder: String
    let note: String
    let keyPath: WritableKeyPath<BusinessProfile, String?>
    @State private var draft = ""
    @State private var loaded = false

    var body: some View {
        PayLinkField(link: $draft, placeholder: placeholder, help: note, goodNote: "Clients will see this button on their page.")
            .onAppear {
                if !loaded { draft = model.data.profile[keyPath: keyPath] ?? ""; loaded = true }
            }
            .onChange(of: draft) { _, new in
                let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    if model.data.profile[keyPath: keyPath] != nil { model.data.profile[keyPath: keyPath] = nil; model.save() }
                } else if let ok = PayLink.clean(trimmed), ok != model.data.profile[keyPath: keyPath] {
                    model.data.profile[keyPath: keyPath] = ok; model.save()
                }
            }
    }
}
#endif

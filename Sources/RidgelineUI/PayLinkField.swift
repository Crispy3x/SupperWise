#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Where the owner pastes a payment link from their own account. The app never handles the money.
struct PayLinkField: View {
    @Binding var link: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Payment link (optional), https://...", text: $link)
                .autocorrectionDisabled()
#if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
#endif
            if let problem = PayLink.problem(for: link) {
                Label(problem, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
            } else if PayLink.clean(link) != nil {
                Label("Clients get a Pay now button. Payments go to your own account.", systemImage: "checkmark.circle")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("Paste a link from Stripe, Square, PayPal, Venmo, Cash App, QuickBooks or Wave. We never touch the money.")
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
#endif

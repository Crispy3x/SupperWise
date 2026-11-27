#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Settings, "Put it on your website": the text to paste into the owner's own website (Wix, Squarespace, WordPress, GoDaddy,
/// Shopify) for the Track your service box and the tips box, and the optional website page client links point to.
/// Shown only to someone who may change settings.
struct EmbedSettingsCard: View {
    @Environment(AppModel.self) private var model
    @State private var draft = ""
    @State private var loaded = false
    @State private var copied: String?

    private var base: String { model.data.broadcastSettings.portalBaseURL }

    var body: some View {
        if model.data.can(.manageSettings) {
            CardGroup(title: "Put it on your website",
                      footer: "Paste it into an HTML or Embed block on your website. It works on Wix, Squarespace, WordPress, GoDaddy and Shopify.") {
                if let tracker = EmbedSnippets.script(portalBaseURL: base, mode: .tracker),
                   let tips = EmbedSnippets.script(portalBaseURL: base, mode: .tips),
                   let frame = EmbedSnippets.iframe(portalBaseURL: base, mode: .tracker) {
                    Text("Clients can follow the plow from your own website. Paste one of these into a page there; the tips box lets anyone tip the crew.")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("Clients sign in with their last name and house number. For a business client, set \"Name for their tracker\" on their profile.")
                        .font(.callout).foregroundStyle(.secondary)
                    snippet(title: "Tracker", text: tracker)
                    snippet(title: "Tips only", text: tips)
                    RowDivider()
                    snippet(title: "If your site does not allow scripts", text: frame)
                    RowDivider()
                    websitePageField
                } else {
                    Label("Turn on client pages first: add your client page address (https) in Settings under Invoices and client messages.",
                          systemImage: "info.circle")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .onAppear {
                if !loaded { draft = model.data.profile.websiteTrackingPage ?? ""; loaded = true }
            }
            .onChange(of: draft) { _, new in
                let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    if model.data.profile.websiteTrackingPage != nil { model.data.profile.websiteTrackingPage = nil; model.save() }
                } else if let ok = EmbedSnippets.cleanWebsitePage(trimmed), ok != model.data.profile.websiteTrackingPage {
                    model.data.profile.websiteTrackingPage = ok; model.save()
                }
            }
        }
    }

    @ViewBuilder private func snippet(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.weight(.medium))
            Text(text)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Look.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Look.stroke, lineWidth: 1))
            SecondaryActionButton(title: copied == title ? "Copied" : "Copy", icon: copied == title ? "checkmark" : "doc.on.doc") {
                Self.copy(text)
                copied = title
            }
        }
    }

    @ViewBuilder private var websitePageField: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Your website's tracking page").font(.title3.weight(.medium))
                Text("(optional)").font(.title3).foregroundStyle(.secondary)
            }
            TextField("https://yourwebsite.com/track", text: $draft)
                .font(.title3)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
                .padding(.horizontal, 22).padding(.vertical, 16)
                .background(Look.field, in: Capsule())
                .overlay(Capsule().stroke(Look.fieldStroke, lineWidth: 1))
            if let problem = EmbedSnippets.websitePageProblem(draft) {
                Label(problem, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
                if model.data.profile.websiteTrackingPage != nil {
                    Text("The page saved before is still in use until this one is fixed or the field is cleared.").font(.footnote).foregroundStyle(.secondary)
                }
            } else if model.data.profile.websiteTrackingPage != nil, EmbedSnippets.cleanWebsitePage(draft) != nil {
                Label("Saved. Season emails and Share page link now send each client to this page with their own code.",
                      systemImage: "checkmark.circle").font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("The page where you pasted the tracker. Leave it empty to keep sending clients to the server page.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    static func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
#endif

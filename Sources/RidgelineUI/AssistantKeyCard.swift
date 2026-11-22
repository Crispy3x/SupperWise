#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Lets the owner paste their own Anthropic key so the assistant works right away, without a server.
/// The key is kept in the Keychain on this device and sent only to Anthropic.
struct AssistantKeyCard: View {
    @Environment(AppModel.self) private var model
    @State private var key = ""
    @State private var note = ""
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.ownAssistantKeySet {
                Label("Your Anthropic key is saved. The assistant is on.", systemImage: "checkmark.seal.fill")
                    .font(.callout.weight(.semibold)).foregroundStyle(.green)
                HStack(spacing: 10) {
                    SecondaryActionButton(title: working ? "Testing..." : "Test it", icon: "bolt.fill") {
                        Task { working = true; note = await model.testAssistantKey(); working = false }
                    }
                    SecondaryActionButton(title: "Remove key", icon: "trash") { note = model.saveAssistantKey("") }
                }
            } else {
                Text("Paste an API key from console.anthropic.com (Settings, API keys). It stays in this device's Keychain and is only sent to Anthropic. You pay Anthropic for what you use, usually a few cents a day.")
                    .font(.footnote).foregroundStyle(.secondary)
                SecureField("sk-ant-...", text: $key)
                    .font(.title3)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .padding(.horizontal, 22).padding(.vertical, 16)
                    .background(Look.field, in: Capsule())
                    .overlay(Capsule().stroke(Look.fieldStroke, lineWidth: 1))
                PrimaryActionButton(title: "Save key", icon: "key.fill") {
                    note = model.saveAssistantKey(key)
                    if model.ownAssistantKeySet { key = "" }
                }
            }
            if !note.isEmpty { Text(note).font(.footnote).foregroundStyle(.secondary) }
        }
    }
}
#endif

#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// A plain page of text, such as the privacy policy.
struct LegalView: View {
    let title: String
    let text: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.largeTitle.bold())
                Text(text).font(.body).foregroundStyle(.secondary).textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 110)
        }
        .background(Look.page.ignoresSafeArea())
    }
}
#endif

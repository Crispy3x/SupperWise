#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Top-level screen for iPhone, iPad and Mac. In your Xcode app target use:
///     WindowGroup { RidgelineRootView() }
public struct RidgelineRootView: View {
    public init() {}

    public var body: some View {
        TabView {
            PricingCalculatorView()
                .tabItem { Label("Plans", systemImage: "dollarsign.circle") }
            InvoicePreviewView()
                .tabItem { Label("Billing", systemImage: "doc.text") }
        }
    }
}
#endif

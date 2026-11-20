#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// A short walkthrough after signing in: 3 to 5 cards. Owners and employees see different ones.
struct TutorialView: View {
    @Environment(AppModel.self) private var model
    let role: SessionRole
    /// First time after sign-up the tutorial has to be completed. A replay from Home can be skipped.
    var required = false
    let onFinish: () -> Void
    @State private var index = 0

    private var steps: [TutorialStep] { Tutorials.steps(for: role) }

    var body: some View {
        let step = steps[min(index, steps.count - 1)]
        let tint = Theme.accent(model.data.profile.accentColor)
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 20) {
                HStack {
                    Text("Step \(index + 1) of \(steps.count)").font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    if !required { Button("Skip") { onFinish() }.font(.callout) }
                }
                IconTile(icon: step.icon, tint: tint, size: 84)
                Text(step.title).font(.title2.bold()).multilineTextAlignment(.center)
                Text(step.body).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    ForEach(0..<steps.count, id: \.self) { i in
                        Capsule().fill(i == index ? tint : Color.gray.opacity(0.35)).frame(width: i == index ? 22 : 8, height: 8)
                    }
                }
                HStack {
                    if index > 0 { Button("Back") { index -= 1 }.buttonStyle(.bordered) }
                    Spacer()
                    Button(index == steps.count - 1 ? "Get started" : "Next") {
                        if index == steps.count - 1 { onFinish() } else { index += 1 }
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                }
            }
            .padding(24)
            .frame(maxWidth: 440)
            .background(Look.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Look.stroke, lineWidth: 1))
            .padding(24)
            .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
            .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
        .transition(.opacity)
        .accessibilityAddTraits(.isModal)
    }
}
#endif

import SwiftUI

/// Plus: one big step at a time, with timers found in the step text. The screen stays on while cooking.
struct CookModeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe
    let day: Weekday
    @State private var index = 0
    @State private var timerEnd: Date? = nil
    @State private var timerStep = -1

    var body: some View {
        let palette = DayPalette.of(day)
        let step = recipe.steps.isEmpty ? "This recipe has no steps saved." : recipe.steps[index]
        let minutes = Self.minutes(in: step)
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("\(recipe.name) · step \(index + 1) of \(max(recipe.steps.count, 1))").font(.footnote.weight(.semibold))
                Spacer()
                Button("Close") { dismiss() }.fontWeight(.semibold)
            }
            .foregroundStyle(Ink.onDay2)
            HStack(spacing: 4) {
                ForEach(0..<max(recipe.steps.count, 1), id: \.self) { i in
                    Capsule().fill(i <= index ? Ink.onDay : Ink.onDay.opacity(0.3)).frame(height: 4)
                }
            }
            Text(step)
                .font(.serif(34, relativeTo: .title))
                .fixedSize(horizontal: false, vertical: true)
                .id(index)
                .transition(.opacity)
            if let minutes {
                Button {
                    timerEnd = .now.addingTimeInterval(Double(minutes) * 60)
                    timerStep = index
                } label: {
                    HStack {
                        Text(timerStep == index && timerEnd != nil ? "Timer running" : "Start a \(minutes)-minute timer")
                        Spacer()
                        if let end = timerEnd, timerStep == index {
                            Text(timerInterval: Date.now...max(end, .now), countsDown: true).font(.title.weight(.semibold)).monospacedDigit()
                        } else {
                            Text("\(minutes):00").font(.title.weight(.semibold)).monospacedDigit()
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 20).fill(.black.opacity(0.22)))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            HStack(spacing: 10) {
                Button("Back") { withAnimation { index -= 1 } }
                    .buttonStyle(PillButtonStyle(fill: .clear, ink: Ink.onDay, outlined: true))
                    .disabled(index == 0)
                if index < recipe.steps.count - 1 {
                    Button { withAnimation { index += 1 } } label: { Text("Next step").frame(maxWidth: .infinity) }
                        .buttonStyle(PillButtonStyle(fill: Ink.onDay, ink: palette.ground))
                } else {
                    Button { model.markCooked(day); dismiss() } label: { Text("I cooked it").frame(maxWidth: .infinity) }
                        .buttonStyle(PillButtonStyle(fill: Ink.onDay, ink: palette.ground))
                }
            }
        }
        .foregroundStyle(Ink.onDay)
        .padding(22)
        .background(palette.ground.ignoresSafeArea())
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .sensoryFeedback(.selection, trigger: index)
    }

    /// "Simmer 18 to 20 minutes" → 20. "for 1 minute" → 1.
    nonisolated static func minutes(in step: String) -> Int? {
        guard let r = step.range(of: #"(\d+)(\s*(to|-|–)\s*(\d+))?\s*(minutes?|min)\b"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let nums = step[r].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        return nums.last
    }
}

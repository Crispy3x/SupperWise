import SwiftUI

/// The 1–100 score in a ring, coloured by band.
struct ScoreBadge: View {
    let score: Int
    var size: CGFloat = 48

    var color: Color {
        switch HealthScore.band(score) {
        case .good: Color(hex: 0x2F6B3A)
        case .ok: Color(hex: 0xB26B00)
        case .poor: Color(hex: 0xB3261E)
        }
    }

    var body: some View {
        Text("\(score)")
            .font(.system(size: size * 0.38, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(color, lineWidth: 3))
            .accessibilityLabel("Health score \(score) out of 100, \(HealthScore.band(score).rawValue)")
    }
}

struct FindingRow: View {
    let finding: Finding
    var body: some View {
        let (symbol, color): (String, Color) = switch finding.severity {
        case .conflict: ("xmark", Color(hex: 0xB3261E))
        case .warning: ("exclamationmark", Color(hex: 0xB26B00))
        case .info: ("info", Paper.ink2)
        case .fine: ("checkmark", Color(hex: 0x2F6B3A))
        }
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(Paper.ground)
                .frame(width: 22, height: 22)
                .background(Circle().fill(color))
            Text(finding.text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct NutritionGrid: View {
    let n: Nutrition
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            row("Added sugar", "\(Int(n.addedSugar.rounded())) g", HealthScore.percentDV(n.addedSugar, HealthScore.dvSugar))
            row("Sodium", "\(Int(n.sodium.rounded())) mg", HealthScore.percentDV(n.sodium, HealthScore.dvSodium))
            row("Saturated fat", "\(Int(n.satFat.rounded())) g", HealthScore.percentDV(n.satFat, HealthScore.dvSatFat))
            row("Protein", "\(Int(n.protein.rounded())) g", nil)
            row("Fibre", "\(Int(n.fiber.rounded())) g", nil)
        }
        .font(.subheadline)
        .monospacedDigit()
    }
    @ViewBuilder private func row(_ label: String, _ value: String, _ pct: Int?) -> some View {
        GridRow {
            Text(label).foregroundStyle(Paper.ink2)
            Text(value).bold()
            Text(pct.map { "\($0)%" } ?? "").foregroundStyle(pct.map { $0 >= 20 } == true ? Color(hex: 0xB3261E) : Paper.ink2)
        }
    }
}

struct HowTheScoreWorks: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How the score works").font(.serif(24))
            Text("It judges food by what you get per calorie. Added sugar, sodium and saturated fat lose points when a serving carries more of the FDA daily value than its share of a 2,000-calorie day. Protein and fibre add points. Fried, refined and ultra-processed foods lose points, as do artificial colours and meals over 600 calories. 70 and up is a good pick; under 40 is poor. It's a guide, not medical advice.")
                .font(.footnote).foregroundStyle(Paper.ink2)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Paper.raised))
    }
}

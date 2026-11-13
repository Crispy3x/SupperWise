import SwiftUI

/// The title-card set: flat cut-paper ingredients around the plate (chilli, onion wedge,
/// chickpeas, cilantro leaf), in the day's deep tone. Drawn in a 402 × 270 space and scaled.
struct CutPaperSet: View {
    var deep: Color
    var ground: Color
    var second: Color = Ink.cut2

    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 402, sy = size.height / 270
            ctx.scaleBy(x: sx, y: sy)

            // Chilli
            var chilli = Path()
            chilli.move(to: CGPoint(x: 8, y: 190))
            chilli.addCurve(to: CGPoint(x: 78, y: 60), control1: CGPoint(x: 0, y: 136), control2: CGPoint(x: 26, y: 82))
            chilli.addCurve(to: CGPoint(x: 62, y: 196), control1: CGPoint(x: 60, y: 98), control2: CGPoint(x: 50, y: 146))
            chilli.addCurve(to: CGPoint(x: 8, y: 190), control1: CGPoint(x: 46, y: 208), control2: CGPoint(x: 18, y: 208))
            ctx.fill(chilli, with: .color(deep))
            var stem = Path()
            stem.move(to: CGPoint(x: 76, y: 56))
            stem.addQuadCurve(to: CGPoint(x: 102, y: 40), control: CGPoint(x: 84, y: 40))
            ctx.stroke(stem, with: .color(second), style: StrokeStyle(lineWidth: 7, lineCap: .round))

            // Onion wedge with rings
            var wedge = Path()
            wedge.move(to: CGPoint(x: 322, y: 94))
            wedge.addLine(to: CGPoint(x: 322, y: 24))
            wedge.addArc(center: CGPoint(x: 322, y: 94), radius: 70, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            wedge.closeSubpath()
            ctx.fill(wedge, with: .color(deep))
            for r in [48.0, 26.0] {
                var ring = Path()
                ring.addArc(center: CGPoint(x: 322, y: 94), radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
                ctx.stroke(ring, with: .color(ground), lineWidth: 4)
            }

            // Chickpeas
            for (x, y, r) in [(54.0, 246.0, 13.0), (80, 254, 11), (66, 226, 10), (370, 236, 12)] {
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(second))
            }

            // Cilantro leaf: three lobes and a stem
            var leaf = ctx
            leaf.translateBy(x: 354, y: 176)
            leaf.rotate(by: .degrees(-20))
            for (x, y, r) in [(0.0, 0.0, 16.0), (22, -8, 14), (18, 16, 13)] {
                leaf.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(deep))
            }
            var leafStem = Path()
            leafStem.move(to: CGPoint(x: 10, y: 6))
            leafStem.addLine(to: CGPoint(x: -16, y: 44))
            leaf.stroke(leafStem, with: .color(deep), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}

/// Small onion-half glyph used beside big numbers and as an aisle mark on paper screens.
struct OnionGlyph: View {
    var color: Color
    var ground: Color
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            let c = CGPoint(x: s, y: s)
            var p = Path()
            p.move(to: c)
            p.addLine(to: CGPoint(x: 0, y: s))
            p.addArc(center: c, radius: s, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            p.closeSubpath()
            ctx.fill(p, with: .color(color))
            for f in [0.66, 0.33] {
                var ring = Path()
                ring.addArc(center: c, radius: s * f, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
                ctx.stroke(ring, with: .color(ground), lineWidth: max(1.5, s * 0.06))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// A plate: the dish photo cropped to a circle with a cream rim. If a recipe has no photo yet,
/// a designed fallback (a coloured plate with the dish's initial) stands in — never a grey box.
struct PlateView: View {
    let recipe: Recipe
    var rim: CGFloat = 8
    var tint: Color = Color(hex: 0xAD321C)

    var body: some View {
        ZStack {
            if let photo = recipe.photo, let image = UIImage(named: photo) {
                // Cut-out studio dishes sit small in their frame; catalog photos (rp_*) are already framed.
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(photo.hasPrefix("rp_") ? 1.1 : 1.5)
            } else {
                ZStack {
                    Circle().fill(tint.opacity(0.85))
                    Text(String(recipe.name.prefix(1)))
                        .font(.serif(80))
                        .foregroundStyle(Ink.onDay)
                }
            }
        }
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Ink.onDay, lineWidth: rim))
        .accessibilityLabel(recipe.name)
    }
}

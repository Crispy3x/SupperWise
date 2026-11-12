import SwiftUI
import CoreText

// Tokens from design/DIRECTION.md.

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

/// The colour field: each weekday has its own ground. You know the day before you read.
struct DayPalette {
    let ground: Color
    let groundDark: Color
    let deep: Color
    let deepDark: Color

    static func of(_ day: Weekday) -> DayPalette {
        switch day {
        case .mon: DayPalette(ground: Color(hex: 0x84520C), groundDark: Color(hex: 0x3D2605), deep: Color(hex: 0x553406), deepDark: Color(hex: 0x6B4410))
        case .tue: DayPalette(ground: Color(hex: 0x5E2A4F), groundDark: Color(hex: 0x2C1325), deep: Color(hex: 0x3D1A33), deepDark: Color(hex: 0x55264A))
        case .wed: DayPalette(ground: Color(hex: 0xAD321C), groundDark: Color(hex: 0x4A160C), deep: Color(hex: 0x741A0E), deepDark: Color(hex: 0x7A2614))
        case .thu: DayPalette(ground: Color(hex: 0x4D581C), groundDark: Color(hex: 0x23280C), deep: Color(hex: 0x323A10), deepDark: Color(hex: 0x4A5420))
        case .fri: DayPalette(ground: Color(hex: 0x1E4D5C), groundDark: Color(hex: 0x0D242B), deep: Color(hex: 0x12323C), deepDark: Color(hex: 0x24505E))
        case .sat: DayPalette(ground: Color(hex: 0x6B3A1C), groundDark: Color(hex: 0x311A0C), deep: Color(hex: 0x472510), deepDark: Color(hex: 0x5E3820))
        case .sun: DayPalette(ground: Color(hex: 0x2E4A36), groundDark: Color(hex: 0x142219), deep: Color(hex: 0x1D3022), deepDark: Color(hex: 0x30503A))
        }
    }

    func ground(_ scheme: ColorScheme) -> Color { scheme == .dark ? groundDark : ground }
    func deep(_ scheme: ColorScheme) -> Color { scheme == .dark ? deepDark : deep }
}

enum Ink {
    /// Cream ink on every weekday ground (≥ 4.5:1 on each).
    static let onDay = Color(hex: 0xFFF5EC)
    static let onDay2 = Color(hex: 0xFFE3D6)
    static let cut2 = Color(hex: 0xE07A5C)
}

/// The "paper" used by list screens, light and dark.
enum Paper {
    static let ground = Color("PaperGround")
    static let raised = Color("PaperRaised")
    static let ink = Color("PaperInk")
    static let ink2 = Color("PaperInk2")
    static let rule = Color("PaperRule")
    static let chip = Color("PaperChip")
}

/// Today's weekday colour is the one accent on paper screens (role: today and the primary action).
struct TodayAccentKey: EnvironmentKey { static let defaultValue = Color(hex: 0xAD321C) }
extension EnvironmentValues {
    var todayAccent: Color {
        get { self[TodayAccentKey.self] }
        set { self[TodayAccentKey.self] = newValue }
    }
}

// MARK: - Type

enum Fonts {
    static let serifName = "InstrumentSerif-Regular"

    /// Registers the bundled display face once at launch.
    static func register() {
        guard let url = Bundle.main.url(forResource: "InstrumentSerif-Regular", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

extension Font {
    /// Instrument Serif, scaled with Dynamic Type relative to a system style.
    static func serif(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .custom(Fonts.serifName, size: size, relativeTo: style)
    }
}

extension View {
    /// Display tracking: tighter as size grows.
    func displayTracking(_ size: CGFloat) -> some View { tracking(-size * 0.025) }
}

// MARK: - Buttons

struct PillButtonStyle: ButtonStyle {
    var fill: Color
    var ink: Color
    var outlined = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 22)
            .frame(minHeight: 50)
            .foregroundStyle(ink)
            .background {
                Capsule().fill(outlined ? Color.clear : fill)
                if outlined { Capsule().strokeBorder(ink.opacity(0.55), lineWidth: 1.5) }
            }
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// Uses Liquid Glass on iOS 26 when built with Xcode 26, a material otherwise.
struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content.background(.ultraThinMaterial, in: Capsule())
        }
        #else
        content.background(.ultraThinMaterial, in: Capsule())
        #endif
    }
}

extension View {
    func glassCapsule() -> some View { modifier(GlassCapsule()) }
}

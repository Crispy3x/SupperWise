#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The app's dark, rounded look: soft cards on a near-black page, blue accents, capsule buttons.
/// Each color has a light and a dark version, so the app also looks right when someone chooses the light appearance.
extension Color {
    init(light: Color, dark: Color) {
        #if canImport(UIKit)
        self.init(UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
        #elseif canImport(AppKit)
        self.init(NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light) })
        #else
        self = dark
        #endif
    }
}

enum Look {
    static let page = Color(light: Color(red: 0.95, green: 0.95, blue: 0.97), dark: Color(red: 0.105, green: 0.105, blue: 0.115))
    static let card = Color(light: .white, dark: Color(red: 0.17, green: 0.17, blue: 0.185))
    static let pill = Color(light: Color(red: 0.89, green: 0.89, blue: 0.92), dark: Color(red: 0.2, green: 0.2, blue: 0.215))
    static let stroke = Color(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.08))
    static let sparkle = Color(red: 0.49, green: 0.23, blue: 0.93)
    static let cardCorner: CGFloat = 20
    /// Space kept free at the bottom so content is never hidden behind the floating tab bar.
    static let tabBarClearance: CGFloat = 104
}

/// A rounded card on the page.
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Look.card, in: RoundedRectangle(cornerRadius: Look.cardCorner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Look.cardCorner, style: .continuous).stroke(Look.stroke, lineWidth: 1))
    }
}

/// A capsule button with an icon, like Menu and Notifications at the top of the screen.
struct PillButton: View {
    let title: String
    let icon: String
    var badge: Int = 0
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 18, weight: .medium))
                Text(title).font(.title3.weight(.medium))
                if badge > 0 {
                    Text("\(badge)").font(.caption.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 2).background(Color.red, in: Capsule())
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(Look.pill, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(badge > 0 ? "\(title), \(badge) new" : title)
    }
}

/// A tinted tip bar: an icon, a line of text and either a chevron or a close button.
struct BannerRow: View {
    let icon: String
    let title: String
    var onClose: (() -> Void)?
    let action: () -> Void
    @Environment(AppModel.self) private var model
    var body: some View {
        let tint = Theme.accent(model.data.profile.accentColor)
        HStack(spacing: 12) {
            Button(action: action) {
                HStack(spacing: 12) {
                    Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(tint)
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    if onClose == nil { Image(systemName: "chevron.right").foregroundStyle(.secondary) }
                }
            }
            .buttonStyle(.plain)
            if let onClose {
                Button(action: onClose) { Image(systemName: "xmark").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).accessibilityLabel("Close")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(tint.opacity(0.35), lineWidth: 1))
    }
}

/// A round icon tile used in the menu and in lists.
struct IconTile: View {
    let icon: String
    var tint: Color = .accentColor
    var size: CGFloat = 52
    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.4, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
    }
}

/// The big title row on Jobs and Clients: an icon tile, the title and a short count on the right.
struct ScreenHeader: View {
    let icon: String
    let title: String
    let trailing: String
    var body: some View {
        HStack(spacing: 14) {
            IconTile(icon: icon, size: 54)
            Text(title).font(.largeTitle.bold())
            Spacer()
            Text(trailing).font(.callout).foregroundStyle(.secondary)
        }
    }
}

struct SearchField: View {
    let prompt: String
    @Binding var text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Look.card, in: Capsule())
        .overlay(Capsule().stroke(Look.stroke, lineWidth: 1))
    }
}

/// The empty state: a large icon, a heading and one line of help.
struct EmptyCard: View {
    let icon: String
    let title: String
    let message: String
    var body: some View {
        Card {
            VStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 44)).foregroundStyle(.secondary)
                Text(title).font(.title3.bold())
                Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 24)
        }
    }
}

/// The wide blue button at the bottom of Jobs and Clients.
struct PrimaryBar: View {
    let title: String
    let action: () -> Void
    @Environment(AppModel.self) private var model
    var body: some View {
        Button(action: action) {
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 18)
                .background(Theme.accent(model.data.profile.accentColor), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

extension JobStatus {
    var color: Color {
        switch self {
        case .scheduled: return .blue
        case .inProgress: return .orange
        case .done: return .green
        case .cancelled: return .gray
        }
    }
}

extension DateFormatter {
    static func make(_ format: String) -> DateFormatter {
        let f = DateFormatter(); f.dateFormat = format; return f
    }
}
#endif

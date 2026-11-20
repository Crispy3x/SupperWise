#if canImport(SwiftUI)
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import RidgelineCore

/// One place for the app's look: the accent color the owner picked, a few sizes and two small building blocks.
/// Everything else uses the system's own fonts and colors, so the app looks at home on iPhone, iPad and Mac.
enum Theme {
    static func accent(_ name: String) -> Color {
        switch name {
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "purple": return .purple
        case "teal": return .teal
        case "gray": return .gray
        default: return .blue
        }
    }
    static let corner: CGFloat = 14
    static let tile: CGFloat = 34
}

// MARK: - A screen that works on its own (tab) or inside another screen's navigation

private struct EmbeddedInStackKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// True when a screen is opened from a hub list, which already provides the navigation bar.
    var embeddedInStack: Bool {
        get { self[EmbeddedInStackKey.self] }
        set { self[EmbeddedInStackKey.self] = newValue }
    }
}

/// Wraps a screen in its own navigation, unless it is being shown inside another screen's navigation.
struct ScreenStack<Content: View>: View {
    @Environment(\.embeddedInStack) private var embedded
    private let content: Content

    init(@ViewBuilder _ content: () -> Content) { self.content = content() }

    var body: some View {
        // Every list and form inside gets the app's page color and card-colored rows, so no screen falls back to plain black.
        Group {
            if embedded { content } else { NavigationStack { content } }
        }
        .scrollContentBackground(.hidden)
        .background(Look.page.ignoresSafeArea())
        .onAppear { RowAppearance.apply() }
    }
}

// MARK: - Building blocks

/// A row in a hub list: a colored icon tile, a title, one line of explanation and an optional count.
struct HubRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var badge: Int = 0
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Theme.tile, height: Theme.tile)
                .background(tint, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            if badge > 0 {
                Text("\(badge)").font(.footnote.bold()).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Color.red, in: Capsule())
            }
        }
        .padding(.vertical, 2)
    }
}

/// A short colored label, for example "Paid" or "Overdue".
struct StatusPill: View {
    let text: String
    var color: Color = .accentColor

    var body: some View {
        Text(text).font(.caption.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }
}
#endif


/// Rows in lists and forms use the card color, like the cards on the rest of the app.
enum RowAppearance {
    @MainActor static func apply() {
        #if canImport(UIKit) && !os(watchOS)
        UICollectionViewListCell.appearance().backgroundColor = UIColor(Look.card)
        #endif
    }
}

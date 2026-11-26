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

// MARK: - The newer look: circle buttons, pill fields, step-by-step sheets

extension Look {
    static let field = Color(light: .white, dark: Color(red: 0.2, green: 0.2, blue: 0.215))
    static let fieldStroke = Color(light: Color.blue.opacity(0.25), dark: Color(red: 0.24, green: 0.32, blue: 0.5))
    static let sheet = Color(light: Color(red: 0.97, green: 0.97, blue: 0.985), dark: Color(red: 0.165, green: 0.165, blue: 0.175))
}

/// A round button with one icon: back, close, next.
struct CircleButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(.primary)
                .frame(width: 50, height: 50).background(Look.pill, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The top bar of a screen that is opened on its own: a round back button and a centred title.
struct ScreenTopBar: View {
    let title: String
    let onBack: () -> Void
    var body: some View {
        HStack {
            CircleButton(icon: "chevron.left", label: "Back", action: onBack)
            Spacer()
            Text(title).font(.title3.weight(.semibold)).lineLimit(1)
            Spacer()
            Color.clear.frame(width: 50, height: 50)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Look.card.opacity(0.6))
        .overlay(alignment: .bottom) { Rectangle().fill(Look.stroke).frame(height: 1) }
    }
}

/// For a screen pushed inside a navigation stack: hides the system back button and shows the round one instead.
struct CircleBackModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    var action: (() -> Void)?
    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CircleButton(icon: "chevron.left", label: "Back") { if let action { action() } else { dismiss() } }
                }
            }
    }
}

extension View {
    func circleBack(_ action: (() -> Void)? = nil) -> some View { modifier(CircleBackModifier(action: action)) }

    /// A dark page behind a list or form, so the standard controls sit on the same background as everything else.
    func pageBackground() -> some View {
        scrollContentBackground(.hidden).background(Look.page)
    }

    @ViewBuilder func hideNavBar() -> some View {
        #if os(iOS)
        toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }
}

/// A labelled text field with a rounded, pill-shaped box.
struct PillField: View {
    enum Kind { case text, phone, email, number }
    let label: String
    var optional = false
    var required = false
    let placeholder: String
    @Binding var text: String
    var kind: Kind = .text

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(label).font(.title3.weight(.medium))
                if optional { Text("(optional)").font(.title3).foregroundStyle(.secondary) }
                if required { Text("*").font(.title3) }
            }
            TextField(placeholder, text: $text)
                .font(.title3)
                .autocorrectionDisabled()
                #if os(iOS)
                .keyboardType(kind == .phone ? .phonePad : (kind == .email ? .emailAddress : (kind == .number ? .decimalPad : .default)))
                .textInputAutocapitalization(kind == .text ? .words : .never)
                #endif
                .padding(.horizontal, 22).padding(.vertical, 16)
                .background(Look.field, in: Capsule())
                .overlay(Capsule().stroke(Look.fieldStroke, lineWidth: 1))
        }
    }
}

/// A labelled multi-line box for notes.
struct PillNotes: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) { Text(label).font(.title3.weight(.medium)); Text("(optional)").font(.title3).foregroundStyle(.secondary) }
            TextField(placeholder, text: $text, axis: .vertical).font(.title3).lineLimit(3...6)
                .padding(.horizontal, 22).padding(.vertical, 16)
                .background(Look.field, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Look.fieldStroke, lineWidth: 1))
        }
    }
}

/// A labelled drop-down in a pill.
struct PillMenu<T: Hashable>: View {
    let label: String
    var required = false
    let options: [(T, String)]
    @Binding var selection: T

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) { Text(label).font(.title3.weight(.medium)); if required { Text("*").font(.title3) } }
            Menu {
                ForEach(Array(options.enumerated()), id: \.offset) { _, o in Button(o.1) { selection = o.0 } }
            } label: {
                HStack {
                    Text(options.first { $0.0 == selection }?.1 ?? "Choose").font(.title3).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.down").foregroundStyle(.secondary)
                }
                .padding(.horizontal, 22).padding(.vertical, 16)
                .background(Look.field, in: Capsule())
                .overlay(Capsule().stroke(Look.fieldStroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }
}

/// A number with minus and plus buttons, in a pill.
struct PillStepper: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var format: (Double) -> String = { String(format: "%g", $0) }

    var body: some View {
        HStack {
            Text(label).font(.title3)
            Spacer()
            Button { value = max(range.lowerBound, value - step) } label: { Image(systemName: "minus.circle.fill").font(.title2) }
                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Less")
            Text(format(value)).font(.title3.weight(.semibold)).monospacedDigit().frame(minWidth: 56)
            Button { value = min(range.upperBound, value + step) } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                .buttonStyle(.plain).foregroundStyle(Color.accentColor).accessibilityLabel("More")
        }
        .padding(.horizontal, 22).padding(.vertical, 12)
        .background(Look.field, in: Capsule())
        .overlay(Capsule().stroke(Look.fieldStroke, lineWidth: 1))
    }
}

/// Two or more choices side by side, one selected, in pills.
struct PillChoice<T: Hashable>: View {
    let options: [(value: T, title: String, icon: String?)]
    @Binding var selection: T
    @Environment(AppModel.self) private var model

    var body: some View {
        let tint = Theme.accent(model.data.profile.accentColor)
        HStack(spacing: 12) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, o in
                let on = o.value == selection
                Button { selection = o.value } label: {
                    HStack(spacing: 8) {
                        if let icon = o.icon { Image(systemName: icon) }
                        Text(o.title).font(.title3.weight(.medium)).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .foregroundStyle(on ? tint : Color.primary)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(on ? tint.opacity(0.16) : Look.field, in: Capsule())
                    .overlay(Capsule().stroke(on ? tint : Look.fieldStroke, lineWidth: on ? 2 : 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct SectionLabel: View {
    let text: String
    @Environment(AppModel.self) private var model
    var body: some View {
        Text(text).font(.title2.weight(.semibold)).foregroundStyle(Theme.accent(model.data.profile.accentColor).opacity(0.9))
    }
}

/// A small grey capital label, like STATUS or HOURS.
struct CapsLabel: View {
    let text: String
    var body: some View { Text(text.uppercased()).font(.subheadline.weight(.semibold)).tracking(1.2).foregroundStyle(.secondary) }
}

/// A sheet that walks through a few steps: close or back on the left, next or finish on the right, and a progress bar.
struct WizardScaffold<Content: View>: View {
    let title: String
    let steps: [String]
    @Binding var step: Int
    var canAdvance = true
    let onClose: () -> Void
    let onFinish: () -> Void
    @ViewBuilder var content: Content
    @Environment(AppModel.self) private var model

    private var last: Bool { step >= steps.count - 1 }

    var body: some View {
        let tint = Theme.accent(model.data.profile.accentColor)
        VStack(spacing: 14) {
            HStack {
                CircleButton(icon: step == 0 ? "xmark" : "chevron.left", label: step == 0 ? "Close" : "Back") { if step == 0 { onClose() } else { step -= 1 } }
                Spacer()
                Text(title).font(.title3.weight(.semibold))
                Spacer()
                CircleButton(icon: last ? "checkmark" : "arrow.right", label: last ? "Save" : "Next") { if last { onFinish() } else { step += 1 } }
                    .disabled(!canAdvance).opacity(canAdvance ? 1 : 0.35)
            }
            if steps.count > 1 {
                HStack {
                    Text("Step \(step + 1) of \(steps.count)").font(.title3).foregroundStyle(.secondary)
                    Spacer()
                    Text(steps[min(step, steps.count - 1)]).font(.title3.weight(.medium))
                }
                HStack(spacing: 8) {
                    ForEach(0..<steps.count, id: \.self) { i in Capsule().fill(i <= step ? tint : Look.pill).frame(height: 5) }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) { content }
                    .padding(.top, 8).padding(.bottom, 30)
            }
        }
        .padding(.horizontal, 18).padding(.top, 16)
        .background(Look.sheet.ignoresSafeArea())
    }
}

// MARK: - Page kit: every screen is built from these, so the whole app looks and acts the same

/// A full page in the app's style: an optional big title, then cards, on the page color, clear of the floating tab bar.
struct AppPage<Content: View>: View {
    var title: String?
    var icon: String?
    var trailing: String = ""
    var clearTabBar = true
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let title, let icon { ScreenHeader(icon: icon, title: title, trailing: trailing) }
                content
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, clearTabBar ? Look.tabBarClearance : 24)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(ScreenshotMode.anchor)   // nil in normal use; debug screenshots can start part-way down a page
        .scrollDismissesKeyboard(.interactively)
        .background(Look.page.ignoresSafeArea())
    }
}

/// A titled card that holds rows, fields or buttons. Put `RowDivider()` between rows.
struct CardGroup<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { SectionLabel(text: title).padding(.leading, 4) }
            Card { VStack(alignment: .leading, spacing: 14) { content } }
            if let footer { Text(footer).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 6) }
        }
    }
}

struct RowDivider: View {
    var body: some View { Divider().overlay(Look.stroke) }
}

/// A tappable row inside a card or on its own: colored icon tile, title, optional detail line and a chevron.
/// Use inside a NavigationLink or Button label.
struct CardLinkRow: View {
    let icon: String
    var tint: Color = .accentColor
    let title: String
    var detail: String?
    var badge: Int = 0
    var body: some View {
        HStack(spacing: 14) {
            IconTile(icon: icon, tint: tint, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                if let detail, !detail.isEmpty { Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer()
            if badge > 0 {
                Text("\(badge)").font(.footnote.bold()).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 2).background(Color.red, in: Capsule())
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}

/// A label with a value on the right, for facts inside a card.
struct FactRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold).foregroundStyle(valueColor).multilineTextAlignment(.trailing)
        }
    }
}

/// The main action at the bottom of a card or page: a filled capsule.
struct PrimaryActionButton: View {
    let title: String
    var icon: String?
    var destructive = false
    let action: () -> Void
    @Environment(AppModel.self) private var model
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon) }
                Text(title).font(.title3.weight(.semibold))
            }
            .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(destructive ? Color.red : Theme.accent(model.data.profile.accentColor), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A quieter button: a pill with a tinted outline.
struct SecondaryActionButton: View {
    let title: String
    var icon: String?
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon) }
                Text(title).font(.title3.weight(.medium))
            }
            .foregroundStyle(.primary).frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(Look.pill, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

#endif

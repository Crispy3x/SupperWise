#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// A round badge with initials.
struct AvatarView: View {
    @Environment(AppModel.self) private var model
    let name: String
    var size: CGFloat = 44

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2).compactMap { $0.first }
        return parts.isEmpty ? "R" : String(parts).uppercased()
    }

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Theme.accent(model.data.profile.accentColor), in: Circle())
    }
}
#endif

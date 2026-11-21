#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Opens the list of earlier copies. `compact` is the small style used inside the warning banner.
struct RestoreEarlierCopyButton: View {
    var compact = false
    @State private var showing = false

    var body: some View {
        Group {
            if compact {
                Button("Restore an earlier copy") { showing = true }
                    .font(.footnote).buttonStyle(.bordered)
            } else {
                SecondaryActionButton(title: "Restore an earlier copy...", icon: "clock.arrow.circlepath") { showing = true }
            }
        }
        .sheet(isPresented: $showing) { SavedCopiesSheet() }
    }
}

/// The copies of your data the app keeps on this device, with a confirmation before one is put back.
struct SavedCopiesSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var copies: [SavedCopy] = []
    @State private var chosen: SavedCopy?
    @State private var result: String?

    private func when(_ copy: SavedCopy) -> String {
        copy.savedAt.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Earlier copies").font(.title3.weight(.medium))
                Spacer()
                CircleButton(icon: "xmark", label: "Close") { dismiss() }
            }
            .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 6)
            AppPage(clearTabBar: false) {
                if copies.isEmpty {
                    EmptyCard(icon: "clock.arrow.circlepath", title: "No copies yet",
                              message: "The app keeps a copy each time it opens, and one a day for the last 3 days.")
                } else {
                    CardGroup(title: "Saved on this device",
                              footer: "Restoring replaces what is on this device now. A safety copy of it is saved first. Everyone signs in again after.") {
                        ForEach(Array(copies.enumerated()), id: \.element.id) { index, copy in
                            if index > 0 { RowDivider() }
                            Button { chosen = copy } label: {
                                CardLinkRow(icon: "clock.arrow.circlepath", tint: .blue, title: when(copy),
                                            detail: "\(copy.title) · \(copy.clientText)")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if let result {
                    Text(result).font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Look.sheet.ignoresSafeArea())
        .onAppear { copies = model.savedCopies() }
        .alert("Restore this copy?", isPresented: Binding(get: { chosen != nil }, set: { if !$0 { chosen = nil } })) {
            Button("Restore", role: .destructive) {
                guard let copy = chosen else { return }
                chosen = nil
                let message = model.restoreSavedCopy(copy)
                if model.data.session == nil {
                    model.notice = message          // shown after signing in again
                    dismiss()
                } else {
                    result = message
                    copies = model.savedCopies()
                }
            }
            Button("Cancel", role: .cancel) { chosen = nil }
        } message: {
            if let copy = chosen {
                Text("This copy from \(when(copy)) has \(copy.clientText). It replaces the data on this device, including settings.")
            }
        }
    }
}
#endif

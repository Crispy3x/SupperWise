#if canImport(SwiftUI)
import SwiftUI
import ImageIO
import RidgelineCore
#if canImport(MapKit)
import MapKit
#endif

// Building blocks of the client profile (ClientDetailView.swift): photos, the small map, history rows and the property editor.

extension AppModel {
    /// Like `edit`, with plain words for the mistakes someone can make on the client profile.
    func editProfile(_ change: (inout AppData) throws -> Void) -> String? {
        var copy = data
        do {
            try change(&copy)
        } catch let error as ClientProfileError {
            return error.message
        } catch {
            return Self.describe(error)
        }
        data = copy
        save()
        return nil
    }
}

// MARK: - Photos

/// Makes small versions of stored photos off the main thread and keeps them in memory, so the strip scrolls smoothly.
/// Nothing is checked against the saved fingerprint here. The Proof screen does that.
enum ClientPhotoLoader {
    private struct Loaded: @unchecked Sendable { let image: CGImage? }

    private static let cache = NSCache<NSString, CGImage>()

    static func image(for ref: PhotoRef, in storage: PhotoStorage, maxPixel: Int) async -> CGImage? {
        let name = (ref.filename as NSString).lastPathComponent
        let key = "\(name)#\(maxPixel)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let url = storage.directory.appendingPathComponent(name)
        let loaded = await Task.detached(priority: .userInitiated) { () -> Loaded in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return Loaded(image: nil) }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel
            ]
            return Loaded(image: CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary))
        }.value
        if let image = loaded.image { cache.setObject(image, forKey: key) }
        return loaded.image
    }
}

extension PhotoKind {
    /// "Before", "After" and so on, for the label on a photo.
    var title: String {
        switch self {
        case .before: return "Before"
        case .after: return "After"
        case .damage: return "Damage"
        case .gate: return "Gate"
        case .other: return "Photo"
        }
    }
}

/// One square photo in the strip. It loads when it scrolls into view.
struct ClientPhotoThumb: View {
    @Environment(AppModel.self) private var model
    let photo: ClientPhoto
    var side: CGFloat = 108
    @State private var image: CGImage?
    @State private var missing = false

    var body: some View {
        ZStack {
            Look.pill
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
                    .frame(width: side, height: side)
            } else {
                Image(systemName: missing ? "exclamationmark.triangle" : "photo").font(.title2).foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            Text(photo.ref.kind.title).font(.caption2.weight(.semibold)).foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Color.black.opacity(0.55), in: Capsule())
                .padding(6)
        }
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Look.stroke, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .task(id: photo.id) {
            guard let storage = model.photoStorage else { missing = true; return }
            let loaded = await ClientPhotoLoader.image(for: photo.ref, in: storage, maxPixel: 360)
            image = loaded
            missing = loaded == nil
        }
    }
}

/// The latest proof photos side by side. Tap one to see it larger.
struct ClientPhotoStrip: View {
    let photos: [ClientPhoto]
    let onOpen: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    Button { onOpen(index) } label: { ClientPhotoThumb(photo: photo) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(photo.ref.kind.title) photo, \(photo.ref.capturedAt.formatted(date: .abbreviated, time: .omitted))")
                }
            }
        }
        .frame(height: 108)
    }
}

/// One photo, large, with when and where it was taken. Arrows step through the others.
struct ClientPhotoViewer: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let photos: [ClientPhoto]
    @State var index: Int
    @State private var image: CGImage?
    @State private var missing = false

    private var photo: ClientPhoto? { photos.indices.contains(index) ? photos[index] : nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(photos.count > 1 ? "Photo \(index + 1) of \(photos.count)" : "Photo").font(.title3.weight(.medium))
                Spacer()
                CircleButton(icon: "xmark", label: "Close") { dismiss() }
            }
            .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 6)
            AppPage(clearTabBar: false) {
                if let photo {
                    picture
                    CardGroup {
                        FactRow(label: "Taken", value: photo.ref.capturedAt.formatted(date: .abbreviated, time: .shortened))
                        RowDivider()
                        FactRow(label: "Kind", value: photo.ref.kind.title)
                        if !photo.address.isEmpty {
                            RowDivider()
                            FactRow(label: "Property", value: photo.address)
                        }
                    }
                    if photos.count > 1 {
                        HStack(spacing: 12) {
                            SecondaryActionButton(title: "Newer", icon: "chevron.left") { index = max(index - 1, 0) }
                                .disabled(index == 0).opacity(index == 0 ? 0.4 : 1)
                            SecondaryActionButton(title: "Older", icon: "chevron.right") { index = min(index + 1, photos.count - 1) }
                                .disabled(index >= photos.count - 1).opacity(index >= photos.count - 1 ? 0.4 : 1)
                        }
                    }
                } else {
                    EmptyCard(icon: "photo", title: "Photo not found", message: "This photo is no longer here.")
                }
            }
        }
        .background(Look.sheet.ignoresSafeArea())
        .task(id: index) {
            image = nil
            missing = false
            guard let photo, let storage = model.photoStorage else { missing = true; return }
            let loaded = await ClientPhotoLoader.image(for: photo.ref, in: storage, maxPixel: 1800)
            guard !Task.isCancelled else { return }
            image = loaded
            missing = loaded == nil
        }
    }

    @ViewBuilder private var picture: some View {
        if let image {
            Image(decorative: image, scale: 1).resizable().scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Look.cardCorner, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Look.cardCorner, style: .continuous).stroke(Look.stroke, lineWidth: 1))
        } else if missing {
            EmptyCard(icon: "exclamationmark.triangle", title: "Photo not on this device",
                      message: "Photos stay on the phone that took them. Open the app on that phone to see this one.")
        } else {
            Card { ProgressView().frame(maxWidth: .infinity).padding(.vertical, 60) }
        }
    }
}

// MARK: - Map

#if canImport(MapKit)
/// A small still map with a pin on the property. It does not scroll or zoom, so the page scrolls over it.
struct SiteMapSnapshot: View {
    let coordinate: Coordinate

    var body: some View {
        let center = CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
        Map(initialPosition: .region(MKCoordinateRegion(center: center, latitudinalMeters: 450, longitudinalMeters: 450)),
            interactionModes: []) {
            Marker("", coordinate: center)
        }
        .frame(height: 140)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Look.stroke, lineWidth: 1))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .id(coordinate)          // a changed address gets a fresh map on the new spot
    }
}
#endif

// MARK: - History

extension ClientEventKind {
    var icon: String {
        switch self {
        case .jobDone: return "checkmark.circle.fill"
        case .jobScheduled: return "calendar"
        case .invoiceCreated: return "doc.text.fill"
        case .invoicePaid: return "dollarsign.circle.fill"
        case .visitLogged: return "camera.fill"
        case .requestReceived: return "bubble.left.fill"
        case .reviewAsked: return "star.fill"
        }
    }

    var tint: Color {
        switch self {
        case .jobDone: return .green
        case .jobScheduled: return .blue
        case .invoiceCreated: return .purple
        case .invoicePaid: return .green
        case .visitLogged: return .teal
        case .requestReceived: return .orange
        case .reviewAsked: return .yellow
        }
    }
}

/// One line of a client's history: what happened, a detail line and the day.
struct ClientHistoryRow: View {
    let event: ClientEvent
    var showsChevron = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(icon: event.kind.icon, tint: event.kind.tint, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.headline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                if !event.detail.isEmpty {
                    Text(event.detail).font(.footnote).foregroundStyle(.secondary).lineLimit(3).multilineTextAlignment(.leading)
                }
                Text(event.date.formatted(date: .abbreviated, time: .omitted)).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if showsChevron { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Add or change a property

/// Add another property for a client, or change one: its address and what the crew should know there.
/// The address is looked up on the map when saving, so the property can go on routes.
struct PropertyEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let customerID: UUID
    /// The property being changed. Nil adds a new one.
    var site: Site?
    /// Called with a short message once it is saved.
    var onSaved: (String) -> Void = { _ in }

    @State private var address = ""
    @State private var instructions = ""
    @State private var loaded = false
    @State private var working = false
    @State private var problem: String?
    @State private var lookup: Task<Void, Never>?

    private var canSave: Bool { !working && !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(site == nil ? "Add a property" : "Change this property").font(.title3.weight(.medium))
                Spacer()
                CircleButton(icon: "xmark", label: "Close") {
                    lookup?.cancel()
                    dismiss()
                }
            }
            .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 6)
            AppPage(clearTabBar: false) {
                CardGroup(title: "Address", footer: "We look the address up on the map when you save, so this property can go on routes.") {
                    PillField(label: "Service address", required: true, placeholder: "14 Elm Ave, Minneapolis", text: $address)
                }
                CardGroup(title: "For the crew", footer: "The crew sees this on every job at this property.") {
                    PillNotes(label: "Gate code and instructions", placeholder: "Gate code 4411. Pile snow on the left side.", text: $instructions)
                }
                if let problem {
                    Label(problem, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                PrimaryActionButton(title: working ? "Looking up the address..." : "Save", icon: working ? nil : "checkmark") { save() }
                    .disabled(!canSave).opacity(canSave ? 1 : 0.4)
            }
        }
        .background(Look.sheet.ignoresSafeArea())
        .interactiveDismissDisabled(working)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            address = site?.address ?? ""
            instructions = site?.instructions ?? ""
        }
        .onChange(of: address) { problem = nil }
    }

    private func save() {
        let typed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let crewNote = instructions
        let sameAddress = site.map { $0.address.trimmingCharacters(in: .whitespacesAndNewlines) == typed } ?? false
        let needsLookup = !sameAddress || site?.latitude == nil || site?.longitude == nil
        problem = nil
        working = true
        lookup = Task { @MainActor in
            var found: Coordinate?
            #if canImport(CoreLocation)
            if needsLookup { found = await AddressGeocoder.coordinate(for: typed) }
            #endif
            working = false
            guard !Task.isCancelled else { return }
            finish(address: typed, instructions: crewNote, found: found, lookedUp: needsLookup)
        }
    }

    private func finish(address typed: String, instructions crewNote: String, found: Coordinate?, lookedUp: Bool) {
        let existing = site
        let owner = customerID
        let failure = model.editProfile { data in
            if let existing {
                try data.updateSiteAddress(siteID: existing.id, address: typed, coordinate: found)
                try data.setSiteInstructions(siteID: existing.id, instructions: crewNote)
            } else {
                let made = try data.addSite(customerID: owner, address: typed, coordinate: found, now: Date())
                try data.setSiteInstructions(siteID: made.id, instructions: crewNote)
            }
        }
        if let failure {
            problem = failure
            return
        }
        var message = existing == nil ? "Property added." : "Saved."
        if lookedUp && found == nil {
            message += " We could not find the address on the map, so it is left out of routes for now. Check the spelling, or try again when you have signal."
        }
        onSaved(message)
        dismiss()
    }
}
#endif

#if canImport(SwiftUI)
import SwiftUI
import PhotosUI
import RidgelineCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Converts any picked image (HEIC, PNG, ...) to JPEG so every saved photo matches its file name.
func jpegData(from data: Data) -> Data? {
    #if canImport(UIKit)
    return UIImage(data: data)?.jpegData(compressionQuality: 0.8)
    #elseif canImport(AppKit)
    guard let tiff = NSImage(data: data)?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    #else
    return nil
    #endif
}

#if os(iOS)
/// The camera, for taking a photo on the spot. Needs the camera permission text in Info.plist.
struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.8) {
                parent.onCapture(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
#endif

/// A row that adds photos of one kind to a visit. Each photo is saved to disk and its fingerprint is kept.
struct PhotoCaptureRow: View {
    @Environment(AppModel.self) private var model
    let title: String
    let kind: PhotoKind
    @Binding var photos: [PhotoRef]
    /// Lines burned into the bottom of each photo when it is saved (see PhotoStamper.swift). The fingerprint is
    /// taken of the stamped file.
    var stamp: ((Date) -> [String])? = nil

    @State private var pickerItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.title3.weight(.medium))
                Spacer()
                Text("\(photos.count) saved").font(.footnote).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                #if os(iOS)
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { showingCamera = true } label: {
                        Label("Take photo", systemImage: "camera.fill").font(.callout.weight(.medium)).frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Look.pill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                #endif
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Choose photo", systemImage: "photo.on.rectangle").font(.callout.weight(.medium)).frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Look.pill, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            if let problem { Text(problem).font(.footnote).foregroundStyle(.red) }
        }
        .onChange(of: pickerItem) {
            guard let item = pickerItem else { return }
            Task {
                if let raw = try? await item.loadTransferable(type: Data.self), let jpeg = jpegData(from: raw) {
                    add(jpeg)
                } else {
                    problem = "That photo could not be read."
                }
                pickerItem = nil
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showingCamera) { CameraPicker { add($0) } }
        #endif
    }

    private func add(_ jpeg: Data) {
        guard let storage = model.photoStorage else {
            problem = "There is nowhere to save photos on this device."
            return
        }
        let capturedAt = Date()
        // If stamping fails, keep the plain photo rather than lose it.
        let bytes = stamp.flatMap { stampedPhoto(jpeg, lines: $0(capturedAt)) } ?? jpeg
        do {
            photos.append(try storage.save(bytes, kind: kind, capturedAt: capturedAt))
            problem = nil
        } catch {
            problem = "The photo could not be saved: \(error.localizedDescription)"
        }
    }
}
#endif

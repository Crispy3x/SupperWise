import SwiftUI
import PhotosUI
import Vision

/// Family: compare what the plan estimated with what the person paid; optionally teach the estimates their store.
/// The receipt is read on the device (Vision text recognition); nothing is uploaded.
struct ReceiptView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var item: PhotosPickerItem? = nil
    @State private var paid: Double? = nil
    @State private var reading = false
    @State private var note: String? = nil
    @State private var done = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let plan = model.plan {
                        let planned = model.cost(of: plan).total
                        Text("Photograph your receipt, or type what you paid. It's read on your iPhone and never uploaded.")
                            .font(.subheadline).foregroundStyle(Paper.ink2)
                        PhotosPicker(selection: $item, matching: .images) {
                            Label("Choose the receipt photo", systemImage: "doc.text.viewfinder")
                        }
                        .buttonStyle(PillButtonStyle(fill: Paper.chip, ink: Paper.ink))
                        if reading { ProgressView("Reading the receipt…") }
                        if let note { Text(note).font(.footnote).foregroundStyle(Paper.ink2) }

                        HStack {
                            Text("You paid")
                            Spacer()
                            TextField("0.00", value: $paid, format: .currency(code: "USD"))
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 120)
                        }
                        .font(.headline)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Paper.raised))

                        stat("Planned", planned.dollars)
                        if let paid, paid > 0 {
                            let diff = paid - planned
                            stat("Difference", (diff >= 0 ? "+" : "−") + abs(diff).dollars,
                                 color: diff > 0 ? Color(hex: 0xB3261E) : Color(hex: 0x2F6B3A))
                            let pct = abs(diff) / planned * 100
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Teach it your store").font(.serif(24))
                                Text("Your store ran \(String(format: "%.1f", pct))% \(diff > 0 ? "above" : "below") our estimates this week. Use it to adjust future plans? Changes are capped at 25% either way.")
                                    .font(.footnote).foregroundStyle(Paper.ink2)
                                HStack {
                                    Button("Adjust my estimates") { model.recordReceipt(planned: planned, paid: paid, learn: true); done = true }
                                        .buttonStyle(PillButtonStyle(fill: Color(hex: 0xAD321C), ink: Ink.onDay))
                                    Button("Just save it") { model.recordReceipt(planned: planned, paid: paid, learn: false); done = true }
                                }
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Paper.raised))
                        }
                        if done { Label("Saved. Next week's plan uses it.", systemImage: "checkmark.circle").foregroundStyle(Color(hex: 0x2F6B3A)) }
                        if model.storeAdjust != 1 {
                            Text("Estimates for your store currently run \(String(format: "%+.1f", (model.storeAdjust - 1) * 100))% against the national reference.")
                                .font(.footnote).foregroundStyle(Paper.ink2)
                        }
                    }
                }
                .padding(22)
            }
            .foregroundStyle(Paper.ink)
            .background(Paper.ground)
            .navigationTitle("Receipt check")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: item) { _, new in Task { await read(new) } }
        }
    }

    private func stat(_ label: String, _ value: String, color: Color = Paper.ink) -> some View {
        HStack { Text(label); Spacer(); Text(value).font(.serif(30)).monospacedDigit().foregroundStyle(color) }
            .padding(.vertical, 6)
            .overlay(alignment: .bottom) { Divider().overlay(Paper.rule) }
    }

    private func read(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let ui = UIImage(data: data), let image = ui.cgImage else { return }
        reading = true
        defer { reading = false }
        let total = await Self.findTotal(in: image, orientation: CGImagePropertyOrientation(ui.imageOrientation))
        if let total { paid = total; note = "Found a total of \(total.dollars). Check it matches your receipt." }
        else { note = "Couldn't find the total. Type it in instead." }
    }

    /// Reads the receipt's lines and returns the amount on the line that says TOTAL (not SUBTOTAL), or the largest amount.
    nonisolated static func findTotal(in image: CGImage, orientation: CGImagePropertyOrientation) async -> Double? {
        await Task.detached(priority: .userInitiated) { () -> Double? in
            let req = VNRecognizeTextRequest()
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = false
            do { try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([req]) } catch { return nil }
            let lines = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return parseTotal(lines)
        }.value
    }

    nonisolated static func parseTotal(_ lines: [String]) -> Double? {
        func amount(_ s: String) -> Double? {
            let m = s.replacingOccurrences(of: ",", with: "").range(of: #"\d+\.\d{2}"#, options: .regularExpression)
            return m.flatMap { Double(s.replacingOccurrences(of: ",", with: "")[$0]) }
        }
        if let line = lines.first(where: { let u = $0.uppercased(); return u.contains("TOTAL") && !u.contains("SUB") && amount($0) != nil }) {
            return amount(line)
        }
        return lines.compactMap(amount).max()
    }
}

extension CGImagePropertyOrientation {
    /// Photos from the camera carry their rotation in the UIImage; Vision needs it to read them upright.
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

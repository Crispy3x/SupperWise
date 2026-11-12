import SwiftUI
import VisionKit

/// Family: scan a barcode, see calories, the 1–100 score, and anything that conflicts with the household.
struct ScannerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var product: FoodProduct? = nil
    @State private var error: String? = nil
    @State private var loading = false
    @State private var typed = ""
    @State private var lastCode = ""

    var scannerAvailable: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if scannerAvailable {
                        BarcodeScanner { code in
                            guard code != lastCode else { return }
                            lastCode = code
                            Task { await lookUp(code) }
                        }
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(alignment: .bottomLeading) {
                            Text("Point at a barcode").font(.footnote.weight(.semibold)).foregroundStyle(.white)
                                .padding(8).background(.black.opacity(0.45), in: Capsule()).padding(10)
                        }
                    } else {
                        Text("The camera scanner isn't available on this device. Type the barcode numbers instead.")
                            .font(.subheadline).foregroundStyle(Paper.ink2)
                    }
                    HStack {
                        TextField("Barcode numbers", text: $typed)
                            .keyboardType(.numberPad)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Paper.raised))
                        Button("Look up") { Task { await lookUp(typed) } }
                            .disabled(typed.filter(\.isNumber).count < 8)
                    }

                    if loading { ProgressView("Looking it up…").frame(maxWidth: .infinity) }
                    if let error { Text(error).font(.subheadline).foregroundStyle(Color(hex: 0xB3261E)) }
                    if let p = product { ProductCard(product: p) }

                    HowTheScoreWorks()
                    Text("Product data from Open Food Facts (openfoodfacts.org), shared under the Open Database License. It can be out of date: always read the label. % is of the FDA daily value; 20% or more in a serving is high.")
                        .font(.footnote).foregroundStyle(Paper.ink2)
                }
                .padding(22)
            }
            .foregroundStyle(Paper.ink)
            .background(Paper.ground)
            .navigationTitle("Scan a product")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func lookUp(_ code: String) async {
        loading = true
        error = nil
        defer { loading = false }
        do { product = try await OpenFoodFacts().product(barcode: code) }
        catch { self.error = (error as? LocalizedError)?.errorDescription ?? "Couldn't look that up." }
    }
}

struct ProductCard: View {
    @Environment(AppModel.self) private var model
    let product: FoodProduct

    var body: some View {
        let findings = FoodCheck.findings(nutrition: product.nutrition, allergens: product.allergens, hasMeat: false,
                                          notVegetarianIngredients: product.notVegetarian, people: model.settings.people)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name).font(.serif(26)).fixedSize(horizontal: false, vertical: true)
                    Text([product.brand, product.servingLabel].compactMap { $0 }.joined(separator: " · "))
                        .font(.footnote).foregroundStyle(Paper.ink2)
                }
                Spacer()
                VStack(spacing: 2) {
                    ScoreBadge(score: product.score, size: 56)
                    Text("health score").font(.caption2).foregroundStyle(Paper.ink2)
                }
            }
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading) {
                    Text(product.nutrition.kcal.formatted(.number.precision(.fractionLength(0)))).font(.serif(44)).monospacedDigit()
                    Text("calories per serving").font(.caption).foregroundStyle(Paper.ink2)
                }
                NutritionGrid(n: product.nutrition)
            }
            ForEach(findings) { FindingRow(finding: $0) }
            if let ing = product.ingredientsText, !ing.isEmpty {
                (Text("Ingredients: ").bold() + Text(ing)).font(.footnote).foregroundStyle(Paper.ink2)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(Paper.raised))
    }
}

/// VisionKit's live barcode scanner (iOS 16+, devices with a Neural Engine).
struct BarcodeScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
                                           qualityLevel: .balanced, recognizesMultipleItems: false,
                                           isHighFrameRateTrackingEnabled: false, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        return vc
    }

    /// Start once the scanner is on screen; starting earlier can fail silently.
    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        if !vc.isScanning { try? vc.startScanning() }
    }

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) { vc.stopScanning() }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }
        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in items {
                if case .barcode(let b) = item, let code = b.payloadStringValue { onCode(code); return }
            }
        }
    }
}

import SwiftUI
import PhotosUI

/// Family: photograph a meal, a snack or a packaged item. The AI estimates what it is, the ingredients (including
/// likely hidden ones like oil and butter) and the nutrition; the app scores it 1–100 with the same formula as
/// barcode scans and restaurant dishes, and checks it against everyone's allergies and diets.
struct FoodScanView: View {
    @Environment(AppModel.self) private var model
    @Environment(Account.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var image: UIImage? = nil
    @State private var showCamera = false
    @State private var scan: FoodScan? = nil
    @State private var remaining: Int? = nil
    @State private var busy = false
    @State private var error: String? = nil
    @State private var signingIn = false
    /// Apple requires clear permission before personal data goes to a third-party AI. Asked once.
    @AppStorage("foodScanConsent") private var consent = false
    @State private var askConsent = false
    @State private var pending: UIImage? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill().frame(height: 240).frame(maxWidth: .infinity).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .overlay { if busy { ZStack { Color.black.opacity(0.35); ProgressView("Reading your food…").tint(.white).foregroundStyle(.white) } .clipShape(RoundedRectangle(cornerRadius: 18)) } }
                    } else {
                        Text("Snap a plate, a snack or anything in the pantry. You get a 1–100 score, calories and what's likely in it, checked for your household.")
                            .foregroundStyle(Paper.ink2)
                    }
                    HStack {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button { start { showCamera = true } } label: { Label("Take photo", systemImage: "camera") }.buttonStyle(.borderedProminent)
                        }
                        PhotosPicker(selection: $photoItem, matching: .images) { Label("Choose photo", systemImage: "photo") }.buttonStyle(.bordered)
                    }
                    .tint(Color(hex: 0xAD321C))
                    if let error { Text(error).foregroundStyle(Color(hex: 0xB3261E)) }
                    if let scan { result(scan) }
                    if let remaining { Text("\(remaining) scans left this month.").font(.footnote).foregroundStyle(Paper.ink2) }
                }
                .padding(20)
            }
            .background(Paper.ground)
            .navigationTitle("Scan food")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showCamera) { CameraPicker { img in Task { await run(img) } }.ignoresSafeArea() }
            .sheet(isPresented: $signingIn) { SignInView(why: "Sign in to scan food. Scans are counted per account.") }
            .onChange(of: photoItem) { _, item in
                Task {
                    guard let d = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: d) else { return }
                    if account.signedIn { await run(img) } else { image = img; signingIn = true }
                }
            }
            .onChange(of: account.signedIn) { _, on in if on, let image, scan == nil { Task { await run(image) } } }
            .alert("Send this photo to be analysed?", isPresented: $askConsent) {
                Button("Allow") { consent = true; if let p = pending { Task { await run(p) } } }
                Button("Not now", role: .cancel) { pending = nil; busy = false }
            } message: {
                Text("To estimate the food, the photo is sent to Supperwise's server and analysed by Anthropic's Claude AI. Supperwise doesn't store the photo, and Anthropic doesn't use it to train its models. Only the photo is sent: not your name, plan or household.")
            }
        }
    }

    private func start(_ go: () -> Void) { if account.signedIn { go() } else { signingIn = true } }

    private func run(_ img: UIImage) async {
        image = img
        guard consent else { pending = img; askConsent = true; return }
        scan = nil; error = nil; busy = true
        defer { busy = false }
        guard let jpeg = img.downscaledJPEG(maxSide: 1024, quality: 0.7) else { error = "Couldn't read that photo."; return }
        do {
            let (s, left) = try await account.backend.scanFood(jpeg: jpeg)
            remaining = left
            if s.isFood { scan = s } else { error = "That doesn't look like food. Try another photo." }
        } catch { self.error = error.localizedDescription }
    }

    @ViewBuilder private func result(_ s: FoodScan) -> some View {
        let n = s.asNutrition
        let findings = FoodCheck.findings(nutrition: n, allergens: s.householdAllergens, hasMeat: !s.notVegetarian.isEmpty,
                                          notVegetarianIngredients: s.notVegetarian, people: model.settings.people)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ScoreBadge(score: s.score, size: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text(s.name).font(.serif(30, relativeTo: .title2)).foregroundStyle(Paper.ink)
                    Text("\(Int(n.kcal.rounded())) calories · \(s.portion)").foregroundStyle(Paper.ink2)
                    Text("\(HealthScore.band(s.score).rawValue) · \(s.confidence.capitalized) confidence").font(.footnote).foregroundStyle(Paper.ink2)
                }
            }
            ForEach(findings) { FindingRow(finding: $0) }
            if (s.allergens ?? []).contains("sesame") {
                FindingRow(finding: Finding(severity: .info, text: "Likely contains sesame."))
            }
            NutritionGrid(n: n)
            VStack(alignment: .leading, spacing: 6) {
                Text("What's likely in it").font(.headline)
                ForEach(s.ingredients, id: \.self) { i in
                    HStack {
                        Image(systemName: i.visible ? "eye" : "eye.slash").foregroundStyle(Paper.ink2).frame(width: 20)
                            .accessibilityLabel(i.visible ? "Seen in the photo" : "Likely, not visible")
                        Text(i.name)
                    }
                    .font(.subheadline)
                }
            }
            Text("An estimate from one photo, not a lab measurement\(s.notes.isEmpty ? "" : ": \(s.notes)"). For allergies, always check the label or ask the restaurant.")
                .font(.footnote).foregroundStyle(Paper.ink2)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(Paper.raised))
    }
}

/// The system camera, for one photo.
struct CameraPicker: UIViewControllerRepresentable {
    let onPick: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onPick(img) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

import SwiftUI
import PhotosUI
import Vision

// MARK: - Weekly recap (Family)

struct RecapView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                if let plan = model.plan {
                    let cost = model.cost(of: plan)
                    let cooked = plan.dinners.filter(\.cooked).count
                    let receipt = model.receipts.first { $0.weekStart == plan.weekStart }
                    let spent = receipt?.paid ?? cost.total
                    let none = model.cost(of: plan, ignoringKitchen: true).total
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(cooked) of \(plan.dinners.count)").font(.serif(80)).foregroundStyle(Color(hex: 0xAD321C))
                        Text("dinners cooked at home this week.").font(.subheadline).foregroundStyle(Paper.ink2).padding(.bottom, 12)
                        stat("Planned grocery bill", cost.total.dollars)
                        if let receipt { stat("What you paid", receipt.paid.dollars) }
                        stat("Against your budget", "\(abs(model.settings.budget - spent).dollars) \(model.settings.budget >= spent ? "under" : "over")")
                        stat("Packs shared across dinners", "\(cost.lines.filter { $0.days.count > 1 && !$0.inKitchen }.count)")
                        stat("Lunches from leftovers", "\((plan.leftovers ?? []).count)")
                        stat("Off the bill from your pantry", max(0, none - cost.total).dollars)
                        Text("Every number here comes from your own plan\(receipt == nil ? "" : " and receipt").")
                            .font(.footnote).foregroundStyle(Paper.ink2).padding(.top, 12)
                    }
                    .padding(22)
                }
            }
            .foregroundStyle(Paper.ink)
            .background(Paper.ground)
            .navigationTitle("Your week")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) { Text(label); Spacer(); Text(value).font(.serif(28)).monospacedDigit() }
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) { Divider().overlay(Paper.rule) }
    }
}

// MARK: - Save a recipe from a link (Plus: 10 a month; Family and Pro: unlimited)

struct ImportRecipeView: View {
    @Environment(AppModel.self) private var model
    @Environment(Subscriptions.self) private var subs
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var working = false
    @State private var error: String? = nil

    var limitReached: Bool { subs.tier == .plus && model.importsThisMonth >= 10 }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Paste a link to a recipe website. Supperwise reads the ingredients and steps and prices what it recognises by the pack. TikTok and Instagram are coming.")
                        .font(.subheadline).foregroundStyle(Paper.ink2)
                    TextField("https://…", text: $link).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button(working ? "Saving…" : "Save recipe") { Task { await save() } }
                        .disabled(link.isEmpty || working || limitReached)
                    if let error { Text(error).foregroundStyle(Color(hex: 0xB3261E)).font(.footnote) }
                    if subs.tier == .plus {
                        Text(limitReached ? "That's 10 saves this month on Plus. Family and Pro are unlimited." : "\(10 - model.importsThisMonth) of 10 saves left this month on Plus.")
                            .font(.footnote).foregroundStyle(Paper.ink2)
                    }
                }
                .listRowBackground(Paper.ground)
                if !model.savedRecipes.isEmpty {
                    Section("Saved") {
                        ForEach(model.savedRecipes) { r in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(r.name).font(.headline)
                                    Text("\(r.minutes) min · \(r.ingredients.count) ingredients · \(r.source ?? "")").font(.caption).foregroundStyle(Paper.ink2)
                                }
                                Spacer()
                                if let day = model.tonight()?.day {
                                    Button("Tonight") { model.setDinner(day, recipeID: r.id); dismiss() }.buttonStyle(.bordered)
                                }
                            }
                            .listRowBackground(Paper.ground)
                            .swipeActions { Button("Delete", role: .destructive) { model.deleteSavedRecipe(r.id) } }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Paper.ground)
            .navigationTitle("Save a recipe")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func save() async {
        working = true
        error = nil
        defer { working = false }
        do {
            let r = try await RecipeImporter(catalog: model.catalog).importRecipe(from: link)
            model.saveRecipe(r)
            link = ""
        } catch { self.error = (error as? LocalizedError)?.errorDescription ?? "Couldn't save that recipe." }
    }
}

// MARK: - Fridge scan (Pro)

/// Photograph the fridge or pantry; Apple's on-device image classifier suggests foods, the person confirms,
/// and the matches rank dinners by what's already there. Nothing is uploaded.
struct FridgeView: View {
    @Environment(AppModel.self) private var model
    @Environment(Account.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var item: PhotosPickerItem? = nil
    @State private var scanning = false
    @State private var adding = false
    @State private var showCamera = false
    @State private var signingIn = false
    @State private var message: String? = nil
    @State private var pending: UIImage? = nil
    @State private var askConsent = false
    /// Shared with the food scan: permission to send photos to the AI, asked once.
    @AppStorage("foodScanConsent") private var consent = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { showCamera = true } label: { Label("Take a photo of your fridge or pantry", systemImage: "camera") }
                    }
                    PhotosPicker(selection: $item, matching: .images) { Label("Choose a photo", systemImage: "photo") }
                    if scanning { ProgressView("Looking at your shelves…") }
                    if let message { Text(message).font(.footnote).foregroundStyle(Color(hex: 0xAD321C)) }
                    Text(account.signedIn
                         ? "The photo is read by AI to find ingredients, then matched to dinners. Check the list: tap an item to remove it, or add what it missed."
                         : "Recognised on your iPhone (basic). Sign in for a much better scan that reads labels and finds far more items.")
                        .font(.footnote).foregroundStyle(Paper.ink2)
                    if !account.signedIn { Button("Sign in for the better scan") { signingIn = true } }
                }
                .listRowBackground(Paper.ground)
                Section("What you have (\(model.fridge.count))") {
                    WrapLayout(spacing: 8) {
                        ForEach(model.fridge, id: \.self) { id in
                            Button { model.setFridge(model.fridge.filter { $0 != id }) } label: {
                                Text((model.catalog.ingredients[id]?.name ?? id) + " ×").font(.subheadline)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Capsule().fill(Paper.ink)).foregroundStyle(Paper.ground)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button("Add an item") { adding = true }
                }
                .listRowBackground(Paper.ground)
                Section("Best matches for tonight") {
                    ForEach(matches(), id: \.recipe.id) { m in
                        HStack(spacing: 12) {
                            PlateView(recipe: m.recipe, rim: 0).frame(width: 48, height: 48)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.recipe.name).font(.headline)
                                Text(m.missing.isEmpty ? "You have everything" : "Buy \(m.missing.joined(separator: ", ")) · about \(m.cost.dollars)")
                                    .font(.caption).foregroundStyle(Paper.ink2)
                                ProgressView(value: Double(m.have), total: Double(max(m.total, 1))).tint(Color(hex: 0xAD321C))
                            }
                            if let day = model.tonight()?.day {
                                Button("Tonight") { model.setDinner(day, recipeID: m.recipe.id); dismiss() }.buttonStyle(.bordered)
                            }
                        }
                        .listRowBackground(Paper.ground)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Paper.ground)
            .navigationTitle("What can I cook?")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: item) { _, new in
                Task { if let new, let d = try? await new.loadTransferable(type: Data.self), let ui = UIImage(data: d) { await scan(ui) } }
            }
            .sheet(isPresented: $adding) { AddFridgeItem() }
            .sheet(isPresented: $showCamera) { CameraPicker { img in Task { await scan(img) } }.ignoresSafeArea() }
            .sheet(isPresented: $signingIn) { SignInView(why: "Sign in for the AI fridge scan. Scans are counted per account.") }
            .alert("Send this photo to be analysed?", isPresented: $askConsent) {
                Button("Allow") { consent = true; if let p = pending { Task { await scan(p) } } }
                Button("Not now", role: .cancel) { pending = nil }
            } message: {
                Text("To find ingredients, the photo is sent to Supperwise's server and analysed by Anthropic's Claude AI. Supperwise doesn't store the photo, and Anthropic doesn't use it to train its models.")
            }
        }
    }

    struct Match { let recipe: Recipe; let have: Int; let total: Int; let missing: [String]; let cost: Double }

    func matches() -> [Match] {
        let have = Set(model.fridge).union(model.inKitchen)
        let pricer = model.planner.pricer
        return model.catalog.eligibleRecipes(for: model.settings, taste: model.taste).map { r in
            let need = r.ingredients.filter { model.catalog.ingredients[$0.ingredient]?.staple == false }
            let missing = need.filter { !have.contains($0.ingredient) }
            let cost = missing.reduce(0.0) { sum, ri in
                guard let i = model.catalog.ingredients[ri.ingredient] else { return sum }
                let packs = (ri.amount * pricer.scale(r) / i.packSize - 1e-9).rounded(.up)
                return sum + packs * i.refPrice * model.settings.price.multiplier * model.storeAdjust
            }
            return Match(recipe: r, have: need.count - missing.count, total: need.count,
                         missing: missing.compactMap { model.catalog.ingredients[$0.ingredient]?.name.lowercased() }, cost: cost)
        }
        .sorted { ($0.missing.count, $0.cost) < ($1.missing.count, $1.cost) }
        .prefix(6).map { $0 }
    }

    private func scan(_ ui: UIImage) async {
        message = nil
        if account.signedIn {
            guard consent else { pending = ui; askConsent = true; return }
            guard let jpeg = ui.downscaledJPEG(maxSide: 1400, quality: 0.75) else { return }
            scanning = true
            defer { scanning = false }
            do {
                let (found, left) = try await account.backend.scanFridge(jpeg: jpeg, catalog: Array(model.catalog.ingredients.values))
                model.setFridge(Array(Set(model.fridge).union(found)).sorted())
                message = found.isEmpty ? "Couldn't spot any ingredients. Try a closer, brighter photo." : "Found \(found.count) items · \(left) scans left this month."
            } catch { message = error.localizedDescription }
        } else {
            guard let image = ui.cgImage else { return }
            scanning = true
            defer { scanning = false }
            let found = await FoodRecognizer.ingredients(in: image, orientation: CGImagePropertyOrientation(ui.imageOrientation))
            model.setFridge(Array(Set(model.fridge).union(found)).sorted())
            message = found.isEmpty ? "The basic scan found nothing. Sign in for the AI scan, or add items by hand." : nil
        }
    }
}

struct AddFridgeItem: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var q = ""
    var body: some View {
        NavigationStack {
            List(model.catalog.ingredients.values.filter { !$0.staple && (q.isEmpty || $0.name.localizedCaseInsensitiveContains(q)) }.sorted { $0.name < $1.name }) { i in
                Button(i.name) { model.setFridge(Array(Set(model.fridge + [i.id])).sorted()); dismiss() }
            }
            .searchable(text: $q)
            .navigationTitle("Add an item")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

/// Maps Vision's on-device image classification labels to catalog ingredients.
enum FoodRecognizer {
    static let labelMap: [String: String] = [
        "egg": "eggs", "lemon": "lemon", "lime": "lime", "broccoli": "broccoli", "carrot": "carrots", "bell_pepper": "bell_pepper",
        "pepper": "bell_pepper", "onion": "onion_yellow", "garlic": "garlic", "potato": "potatoes", "spinach": "spinach",
        "tomato": "tomatoes_cherry", "cheese": "cheddar", "mushroom": "mushrooms", "avocado": "avocado", "cabbage": "cabbage",
        "celery": "celery", "milk": "milk", "yogurt": "yogurt", "butter": "butter", "chicken": "chicken_thighs", "salmon": "salmon",
        "shrimp": "shrimp", "bread": "bread_crusty", "pasta": "spaghetti", "rice": "jasmine", "lettuce": "arugula", "herb": "parsley",
        "scallion": "scallions", "ginger": "ginger", "tortilla": "tortillas", "peas": "frozen_peas", "bean": "black_beans",
    ]

    static func ingredients(in image: CGImage, orientation: CGImagePropertyOrientation) async -> [String] {
        await Task.detached(priority: .userInitiated) { () -> [String] in
            let req = VNClassifyImageRequest()
            do { try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([req]) } catch { return [] }
            let labels = (req.results ?? []).filter { $0.confidence > 0.25 }.map { $0.identifier.lowercased() }
            var found = Set<String>()
            for l in labels { for (k, v) in labelMap where l.contains(k) { found.insert(v) } }
            return Array(found)
        }.value
    }
}

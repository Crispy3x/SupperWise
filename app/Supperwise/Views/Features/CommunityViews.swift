import SwiftUI
import PhotosUI

/// The signed-in account for community recipes and food scans. Signing in is only needed to share or scan.
@Observable
@MainActor
final class Account {
    let backend = Backend()
    private(set) var signedIn = false
    private(set) var email: String? = nil
    private(set) var isAdmin = false

    init() { refresh() }

    func refresh() {
        signedIn = backend.isSignedIn
        email = backend.current?.email
        Task { isAdmin = signedIn ? await backend.isAdmin() : false }
    }
    func sendCode(_ email: String) async throws { try await backend.sendCode(to: email) }
    func verify(_ email: String, _ code: String) async throws { try await backend.verify(email: email, code: code); refresh() }
    func signOut() { backend.signOut(); refresh() }
    func deleteAccount() async throws { try await backend.deleteAccount(); refresh() }
    /// From the emailed sign-in link.
    func handle(_ url: URL) -> String? {
        do { if try backend.handleSignInLink(url) { refresh() }; return nil } catch { return error.localizedDescription }
    }
}

// MARK: - Sign in

/// Sign in with a 6-digit code sent by email. No password.
struct SignInView: View {
    @Environment(Account.self) private var account
    @Environment(\.dismiss) private var dismiss
    var why = "Sign in to share recipes and scan food."
    @State private var email = ""
    @State private var code = ""
    @State private var sent = false
    @State private var busy = false
    @State private var error: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(why).foregroundStyle(Paper.ink2)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress).textContentType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .disabled(sent)
                    if sent {
                        Label("Check your email and tap the sign-in link on this iPhone.", systemImage: "envelope.open")
                        TextField("Or type the 6-digit code, if your email has one", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode)
                    }
                    Button(sent ? "Sign in with code" : "Email me a sign-in link") { Task { await go() } }
                        .disabled(busy || !email.contains("@") || (sent && code.count < 6))
                    if sent { Button("Use a different email") { sent = false; code = "" } }
                } footer: {
                    Text(error ?? "We only use your email to sign you in. Your meal plans stay on this iPhone.")
                        .foregroundStyle(error == nil ? Paper.ink2 : Color(hex: 0xB3261E))
                }
            }
            .navigationTitle("Sign in")
            .onChange(of: account.signedIn) { _, on in if on { dismiss() } }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func go() async {
        busy = true; error = nil
        defer { busy = false }
        do {
            if sent { try await account.verify(email.trimmingCharacters(in: .whitespaces), code); dismiss() }
            else { try await account.sendCode(email.trimmingCharacters(in: .whitespaces)); sent = true }
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Browse

/// Recipes other families shared, approved by Supperwise before anyone sees them.
struct CommunityView: View {
    @Environment(AppModel.self) private var model
    @Environment(Account.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var recipes: [CommunityRecipe] = []
    @State private var search = ""
    @State private var loading = false
    @State private var error: String? = nil
    @State private var open: CommunityRecipe? = nil
    @State private var sharing = false
    @State private var signingIn = false
    @State private var mine = false
    @State private var reviewing = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { if account.signedIn { sharing = true } else { signingIn = true } } label: {
                        Label("Share a recipe", systemImage: "square.and.arrow.up")
                    }
                    if account.signedIn { Button { mine = true } label: { Label("My shared recipes", systemImage: "tray") } }
                    if account.isAdmin { Button { reviewing = true } label: { Label("Review new recipes", systemImage: "checkmark.shield") } }
                } footer: {
                    Text("Every recipe is checked by Supperwise before it appears here. Saved recipes are yours to add to any night; they're never planned automatically, so check allergens yourself.")
                }
                if let error { Text(error).foregroundStyle(Color(hex: 0xB3261E)) }
                if recipes.isEmpty && !loading && error == nil {
                    Text(search.isEmpty ? "No shared recipes yet. Be the first." : "Nothing matches “\(search)”.").foregroundStyle(Paper.ink2)
                }
                ForEach(recipes) { c in
                    Button { open = c } label: { CommunityRow(c: c, saved: model.savedRecipes.contains { $0.id == c.recipe.id }) }
                        .buttonStyle(.plain)
                }
            }
            .overlay { if loading && recipes.isEmpty { ProgressView() } }
            .searchable(text: $search, prompt: "Search shared recipes")
            .onSubmit(of: .search) { Task { await load() } }
            .refreshable { await load() }
            .task { await load() }
            .navigationTitle("Community")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $open) { CommunityRecipeView(c: $0) }
            .sheet(isPresented: $sharing) { SubmitRecipeView() }
            .sheet(isPresented: $signingIn) { SignInView(why: "Sign in to share a recipe. Your name appears with it.") }
            .sheet(isPresented: $mine) { MySubmissionsView() }
            .sheet(isPresented: $reviewing) { ReviewQueueView() }
        }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do { recipes = try await account.backend.approvedRecipes(search: search); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct CommunityRow: View {
    let c: CommunityRecipe
    var saved = false
    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: c.photoURL) { img in img.resizable().scaledToFill() } placeholder: { Paper.chip }
                .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(c.recipe.name).font(.headline).foregroundStyle(Paper.ink)
                Text("\(c.recipe.cuisine) · \(c.recipe.minutes) min\(c.authorName.map { " · by \($0)" } ?? "")")
                    .font(.footnote).foregroundStyle(Paper.ink2)
            }
            Spacer()
            if saved { Image(systemName: "bookmark.fill").foregroundStyle(Paper.ink2).accessibilityLabel("Saved") }
        }
    }
}

struct CommunityRecipeView: View {
    @Environment(AppModel.self) private var model
    @Environment(Account.self) private var account
    @Environment(\.dismiss) private var dismiss
    let c: CommunityRecipe
    var reviewActions: ((Bool) -> Void)? = nil
    @State private var reporting = false
    @State private var reason = ""
    @State private var reported = false
    @State private var signingIn = false

    var body: some View {
        NavigationStack {
            List {
                if let url = c.photoURL {
                    AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Paper.chip }
                        .frame(height: 220).clipped().listRowInsets(EdgeInsets())
                }
                Section {
                    Text("\(c.recipe.cuisine) · \(c.recipe.minutes) min · serves \(c.recipe.servings)").foregroundStyle(Paper.ink2)
                    if !c.recipe.allergens.isEmpty {
                        Text("Contains: \(c.recipe.allergens.map { $0.label.replacingOccurrences(of: "No ", with: "") }.joined(separator: ", "))")
                    }
                    if c.recipe.vegetarian { Label("Vegetarian", systemImage: "leaf") }
                    if let a = c.authorName { Text("Shared by \(a)").font(.footnote).foregroundStyle(Paper.ink2) }
                }
                Section("Ingredients") { ForEach(Array(c.recipe.ingredients.enumerated()), id: \.offset) { Text($0.element.text) } }
                Section("Steps") {
                    ForEach(Array(c.recipe.steps.enumerated()), id: \.offset) { i, s in Text("\(i + 1). \(s)") }
                }
                Section {
                    if let reviewActions {
                        Button("Approve and publish") { reviewActions(true); dismiss() }
                        Button("Reject", role: .destructive) { reviewActions(false); dismiss() }
                    } else {
                        let saved = model.savedRecipes.contains { $0.id == c.recipe.id }
                        Button(saved ? "Saved to your recipes" : "Save to my recipes") { model.saveRecipe(c.recipe) }.disabled(saved)
                        Button(reported ? "Reported. Thank you." : "Report this recipe", role: .destructive) {
                            if account.signedIn { reporting = true } else { signingIn = true }
                        }
                        .disabled(reported)
                    }
                } footer: {
                    Text("Shared by a Supperwise family and checked before publishing. Check allergens and cooking temperatures yourself.")
                }
            }
            .navigationTitle(c.recipe.name)
            .navigationBarTitleDisplayMode(.inline)
            .alert("What's wrong with it?", isPresented: $reporting) {
                TextField("Unsafe, offensive, copied, wrong allergens…", text: $reason)
                Button("Report", role: .destructive) {
                    Task { try? await account.backend.report(c.id, reason: reason.isEmpty ? "No reason given" : reason); reported = true }
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Supperwise reviews every report within 24 hours.") }
            .sheet(isPresented: $signingIn) { SignInView(why: "Sign in to report a recipe.") }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

// MARK: - Share

/// Write up a recipe to share. It's private to its author until it's approved.
struct SubmitRecipeView: View {
    @Environment(AppModel.self) private var model
    @Environment(Account.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var cuisine = "American"
    @State private var minutes = 30
    @State private var servings = 4
    @State private var ingredientsText = ""
    @State private var stepsText = ""
    @State private var allergens: Set<Allergen> = []
    @State private var vegetarian = false
    @State private var authorName = ""
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var photo: Data? = nil
    @State private var busy = false
    @State private var error: String? = nil
    @State private var done = false

    private let cuisines = ["American", "Italian", "Mexican", "Chinese", "Indian", "Thai", "Japanese", "Korean", "Middle Eastern",
                            "Mediterranean", "French", "Caribbean", "Latin American", "African", "Other"]
    private var lines: [String] { ingredientsText.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    private var steps: [String] { stepsText.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    private var ready: Bool { name.count >= 3 && lines.count >= 3 && steps.count >= 2 && !authorName.isEmpty }

    var body: some View {
        NavigationStack {
            if done {
                ContentUnavailableView {
                    Label("Thanks for sharing", systemImage: "checkmark.circle")
                } description: {
                    Text("We check every recipe before it's published, usually within a couple of days. You'll see it under My shared recipes.")
                } actions: { Button("Done") { dismiss() } }
            } else {
                Form {
                    Section("Recipe") {
                        TextField("Name", text: $name)
                        Picker("Cuisine", selection: $cuisine) { ForEach(cuisines, id: \.self) { Text($0) } }
                        Stepper("\(minutes) minutes in total", value: $minutes, in: 5...480, step: 5)
                        Stepper("Serves \(servings)", value: $servings, in: 1...12)
                    }
                    Section {
                        TextField("2 cans chickpeas, drained\n1 onion, diced\n…", text: $ingredientsText, axis: .vertical).lineLimit(5...14)
                    } header: { Text("Ingredients, one per line") } footer: { Text("Include amounts, like \"1 cup\" or \"400 g\".") }
                    Section("Steps, one per line") {
                        TextField("Heat the oil in a large pan…", text: $stepsText, axis: .vertical).lineLimit(4...14)
                    }
                    Section {
                        ForEach(Allergen.allCases) { a in
                            Toggle(a.label.replacingOccurrences(of: "No ", with: "Contains "), isOn: Binding(
                                get: { allergens.contains(a) }, set: { if $0 { allergens.insert(a) } else { allergens.remove(a) } }))
                        }
                        Toggle("Vegetarian", isOn: $vegetarian)
                    } header: { Text("Allergens and diet") } footer: { Text("Families rely on this. Tick everything the recipe contains.") }
                    Section("Photo (optional)") {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label(photo == nil ? "Add a photo of the finished dish" : "Change photo", systemImage: "photo")
                        }
                        if let photo, let ui = UIImage(data: photo) {
                            Image(uiImage: ui).resizable().scaledToFill().frame(height: 160).clipped()
                        }
                    }
                    Section {
                        TextField("Your first name, shown with the recipe", text: $authorName).textContentType(.givenName)
                        Button(busy ? "Sending…" : "Send for review") { Task { await send() } }.disabled(!ready || busy)
                    } footer: {
                        Text(error ?? "By sharing, you confirm it's your own recipe (or written in your own words) and photo, and that Supperwise may show it to other families.")
                            .foregroundStyle(error == nil ? Paper.ink2 : Color(hex: 0xB3261E))
                    }
                }
                .navigationTitle("Share a recipe")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .onChange(of: photoItem) { _, item in
                    Task { if let d = try? await item?.loadTransferable(type: Data.self) { photo = UIImage(data: d)?.downscaledJPEG(maxSide: 1600) } }
                }
            }
        }
    }

    private func send() async {
        busy = true; error = nil
        defer { busy = false }
        let importer = RecipeImporter(catalog: model.catalog)
        let r = Recipe(id: "community_" + UUID().uuidString.lowercased().prefix(12), name: name.trimmingCharacters(in: .whitespaces),
                       side: "Shared by \(authorName).", cuisine: cuisine, minutes: minutes, difficulty: minutes > 50 ? "Medium" : "Easy",
                       protein: vegetarian ? "none" : "mixed", allergens: allergens.sorted { $0.rawValue < $1.rawValue }, equipment: [],
                       spice: 0, ingredients: lines.map { importer.match($0) }, steps: steps, photo: nil,
                       vegetarian: vegetarian, pescatarian: vegetarian, mildNote: nil, vegetarianSwap: nil, servings: servings,
                       source: "Community")
        do { try await account.backend.submit(r, authorName: authorName, photoJPEG: photo); done = true }
        catch { self.error = error.localizedDescription }
    }
}

struct MySubmissionsView: View {
    @Environment(Account.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var list: [CommunityRecipe] = []
    @State private var error: String? = nil
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(Color(hex: 0xB3261E)) }
                if list.isEmpty && error == nil { Text("Nothing shared yet.").foregroundStyle(Paper.ink2) }
                ForEach(list) { c in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(c.recipe.name).font(.headline)
                        switch c.status {
                        case .pending: Text("Waiting for review").font(.footnote).foregroundStyle(Paper.ink2)
                        case .approved: Text("Published").font(.footnote).foregroundStyle(Color(hex: 0x2F6B3A))
                        case .rejected: Text("Not published\(c.rejectReason.map { ": \($0)" } ?? "")").font(.footnote).foregroundStyle(Color(hex: 0xB3261E))
                        }
                    }
                    .swipeActions {
                        if c.status != .approved {
                            Button("Withdraw", role: .destructive) { Task { try? await account.backend.withdraw(c.id); await load() } }
                        }
                    }
                }
                Section {
                    Button("Sign out") { account.signOut(); dismiss() }
                    Button("Delete my account", role: .destructive) { confirmDelete = true }
                } footer: {
                    Text("Deleting your account removes your shared recipes and photos. Your meal plans stay on this iPhone.")
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .navigationTitle("My shared recipes")
            .confirmationDialog("Delete your Supperwise account?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete account and shared recipes", role: .destructive) {
                    Task {
                        do { try await account.deleteAccount(); dismiss() } catch { self.error = error.localizedDescription }
                    }
                }
            } message: { Text("This can't be undone. It doesn't cancel a subscription; manage that in Settings.") }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
    private func load() async {
        do { list = try await account.backend.mySubmissions(); error = nil } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Admin review

/// For Supperwise admins only (the server refuses anyone else): approve or reject new recipes.
struct ReviewQueueView: View {
    @Environment(Account.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var queue: [CommunityRecipe] = []
    @State private var open: CommunityRecipe? = nil
    @State private var rejecting: CommunityRecipe? = nil
    @State private var reason = ""
    @State private var error: String? = nil

    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(Color(hex: 0xB3261E)) }
                if queue.isEmpty && error == nil { Text("Nothing waiting for review.").foregroundStyle(Paper.ink2) }
                ForEach(queue) { c in
                    Button { open = c } label: { CommunityRow(c: c) }.buttonStyle(.plain)
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .navigationTitle("Review (\(queue.count))")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $open) { c in
                CommunityRecipeView(c: c) { approve in
                    if approve { Task { await decide(c, true) } } else { rejecting = c }
                }
            }
            .alert("Why isn't it being published?", isPresented: Binding(get: { rejecting != nil }, set: { if !$0 { rejecting = nil } })) {
                TextField("Reason the author will see", text: $reason)
                Button("Reject", role: .destructive) { if let c = rejecting { Task { await decide(c, false) } } }
                Button("Cancel", role: .cancel) { rejecting = nil }
            }
        }
    }
    private func load() async {
        do { queue = try await account.backend.pendingRecipes(); error = nil } catch { self.error = error.localizedDescription }
    }
    private func decide(_ c: CommunityRecipe, _ approve: Bool) async {
        do { try await account.backend.review(c.id, approve: approve, reason: approve ? nil : reason); reason = ""; await load() }
        catch { self.error = error.localizedDescription }
    }
}

extension UIImage {
    /// A JPEG no larger than `maxSide` pixels on its long side, for uploads and scans.
    func downscaledJPEG(maxSide: CGFloat, quality: CGFloat = 0.75) -> Data? {
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
            .jpegData(compressionQuality: quality)
    }
}

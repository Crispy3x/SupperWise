import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking   // URLSession on Linux (used by the logic tests)
#endif
#if canImport(Security)
import Security
#endif

/// The Supperwise backend (Supabase): sign-in by emailed code, community recipes, and AI food scans.
/// Only the project URL and the public anon key ship in the app; row-level security on the server decides who can
/// read and write what (see backend/supabase/migrations). Never put the service-role key in the app.
enum BackendConfig {
    /// Filled in once the Supabase project exists (Project Settings → API). Until then, community features say
    /// they're coming soon instead of failing.
    static let url = URL(string: "https://tgywrfseyrvflhusqzpt.supabase.co")!
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRneXdyZnNleXJ2ZmxodXNxenB0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQ1NDg0NjYsImV4cCI6MjExMDEyNDQ2Nn0.IyljME217AG0_flxZUBAusyB2JZVxl-R6gvhuO9gOt8"
    static var isConfigured: Bool { !url.absoluteString.contains("YOUR-PROJECT") && !anonKey.hasPrefix("YOUR-") }
}

enum BackendError: LocalizedError, Equatable {
    case notConfigured, signedOut, network, server(String), overLimit(String)
    var errorDescription: String? {
        switch self {
        case .notConfigured: "Community features are coming soon."
        case .signedOut: "Sign in first."
        case .network: "You're offline. Check your connection and try again."
        case .server(let m), .overLimit(let m): m
        }
    }
}

struct Session: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: String
    var email: String?
}

/// A recipe someone shared. `recipe` uses the app's own recipe shape so a saved one prices and cooks like any other.
struct CommunityRecipe: Codable, Identifiable, Hashable {
    enum Status: String, Codable { case pending, approved, rejected }
    let id: String
    var authorName: String?
    var status: Status
    var recipe: Recipe
    var photoPath: String?
    var rejectReason: String?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, status, recipe
        case authorName = "author_name", photoPath = "photo_path", rejectReason = "reject_reason", createdAt = "created_at"
    }

    var photoURL: URL? {
        photoPath.map { BackendConfig.url.appendingPathComponent("storage/v1/object/public/recipe-photos/\($0)") }
    }
}

/// What the AI food scan returns (see backend/supabase/functions/scan-food).
struct FoodScan: Codable, Hashable {
    struct Item: Codable, Hashable { let name: String; let visible: Bool }
    struct Facts: Codable, Hashable {
        let kcal: Double, proteinG: Double, fiberG: Double, addedSugarG: Double, saturatedFatG: Double, sodiumMg: Double
    }
    let kind: String
    let name: String
    let portion: String
    let ingredients: [Item]
    let nutrition: Facts
    var allergens: [String]? = nil
    let ultraProcessed: Bool
    var fried: Bool? = nil
    let confidence: String
    let notes: String

    var isFood: Bool { kind != "not_food" }

    /// The same nutrition shape the barcode scanner and restaurant scores use, so the 1–100 score is comparable.
    var asNutrition: Nutrition {
        Nutrition(kcal: max(0, nutrition.kcal), addedSugar: max(0, nutrition.addedSugarG), sodium: max(0, nutrition.sodiumMg),
                  satFat: max(0, nutrition.saturatedFatG), protein: max(0, nutrition.proteinG), fiber: max(0, nutrition.fiberG),
                  fried: fried ?? false, ultraProcessed: ultraProcessed)
    }
    var score: Int { HealthScore.score(asNutrition) }

    /// Allergens as household settings.
    var householdAllergens: Set<Allergen> {
        Set((allergens ?? []).compactMap { $0 == "nuts" ? .nuts : Allergen(rawValue: $0) })
    }

    /// Meat or fish named in the ingredients, for vegetarians.
    var notVegetarian: [String] {
        let words = ["chicken", "beef", "pork", "bacon", "ham", "turkey", "lamb", "sausage", "pepperoni", "salami", "anchov",
                     "fish", "salmon", "tuna", "shrimp", "prawn", "crab", "gelatin", "lard", "steak", "chorizo"]
        return ingredients.map(\.name).filter { n in words.contains { n.lowercased().contains($0) } }
    }
}

/// A small client for Supabase's REST endpoints (auth, PostgREST, storage, edge functions). No SDK dependency.
final class Backend {
    let base: URL
    let anonKey: String
    var session: URLSession
    private(set) var current: Session?
    private let store: SessionStore

    init(base: URL = BackendConfig.url, anonKey: String = BackendConfig.anonKey, session: URLSession = .shared,
         store: SessionStore = KeychainSessionStore()) {
        self.base = base
        self.anonKey = anonKey
        self.session = session
        self.store = store
        self.current = store.load()
    }

    var isSignedIn: Bool { current != nil }

    // MARK: Auth: a 6-digit code by email (no password to forget)

    /// Where the emailed sign-in link sends people back: the app (registered in Supperwise-Info.plist).
    static let redirect = "supperwise://login"

    /// Emails a sign-in link (and a 6-digit code where the email template includes one).
    func sendCode(to email: String) async throws {
        _ = try await send("auth/v1/otp", query: [URLQueryItem(name: "redirect_to", value: Self.redirect)], method: "POST",
                           body: ["email": email, "create_user": true], auth: false)
    }

    /// Signs in from the emailed link: supperwise://login#access_token=…&refresh_token=…&expires_in=…
    /// Returns false if the link isn't a sign-in link; throws if it's one that failed or expired.
    @discardableResult
    func handleSignInLink(_ url: URL, now: Date = .now) throws -> Bool {
        guard url.scheme == "supperwise", url.host == "login" else { return false }
        var params: [String: String] = [:]
        for part in [url.fragment, URLComponents(url: url, resolvingAgainstBaseURL: false)?.query].compactMap({ $0 }) {
            for pair in part.split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding ?? String($0) }
                if kv.count == 2 { params[kv[0]] = kv[1] }
            }
        }
        if let e = params["error_description"] ?? params["error"] {
            throw BackendError.server(e.replacingOccurrences(of: "+", with: " ") + ". Ask for a new sign-in email.")
        }
        guard let access = params["access_token"], let refresh = params["refresh_token"],
              let claims = Self.claims(of: access), let id = claims["sub"] as? String else {
            throw BackendError.server("That sign-in link didn't work. Ask for a new one.")
        }
        current = Session(accessToken: access, refreshToken: refresh,
                          expiresAt: now.addingTimeInterval(Double(params["expires_in"] ?? "") ?? 3600),
                          userID: id, email: claims["email"] as? String)
        store.save(current)
        return true
    }

    /// The payload of a JWT (not verified here; the server verifies every request).
    static func claims(of jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var b64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    func verify(email: String, code: String) async throws {
        let data = try await send("auth/v1/verify", method: "POST", body: ["type": "email", "email": email, "token": code], auth: false)
        try adopt(data)
    }

    /// Deletes the account and everything shared with it, then signs out (App Store guideline 5.1.1(v)).
    func deleteAccount() async throws {
        try await refreshIfNeeded()
        _ = try await send("functions/v1/delete-account", method: "POST", body: [:])
        signOut()
    }

    func signOut() {
        current = nil
        store.save(nil)
    }

    private func refreshIfNeeded() async throws {
        guard let s = current else { throw BackendError.signedOut }
        guard s.expiresAt.timeIntervalSinceNow < 60 else { return }
        let data = try await send("auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "refresh_token")], method: "POST",
                                  body: ["refresh_token": s.refreshToken], auth: false)
        try adopt(data)
    }

    private func adopt(_ data: Data) throws {
        current = try Self.parseSession(data)
        store.save(current)
    }

    static func parseSession(_ data: Data, now: Date = .now) throws -> Session {
        guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = o["access_token"] as? String, let refresh = o["refresh_token"] as? String,
              let user = o["user"] as? [String: Any], let id = user["id"] as? String else {
            throw BackendError.server("Sign-in didn't work. Ask for a new code.")
        }
        let expires = (o["expires_in"] as? Double) ?? Double(o["expires_in"] as? Int ?? 3600)
        return Session(accessToken: access, refreshToken: refresh, expiresAt: now.addingTimeInterval(expires),
                       userID: id, email: user["email"] as? String)
    }

    // MARK: Community recipes

    /// Approved recipes, newest first.
    func approvedRecipes(search: String = "") async throws -> [CommunityRecipe] {
        var q = [URLQueryItem(name: "status", value: "eq.approved"), URLQueryItem(name: "order", value: "created_at.desc"),
                 URLQueryItem(name: "limit", value: "200"), URLQueryItem(name: "select", value: "id,author_name,status,recipe,photo_path,reject_reason,created_at")]
        let s = search.trimmingCharacters(in: .whitespaces)
        if !s.isEmpty { q.append(URLQueryItem(name: "recipe->>name", value: "ilike.*\(s.replacingOccurrences(of: "*", with: ""))*")) }
        return try Self.decodeRecipes(try await send("rest/v1/community_recipes", query: q, auth: isSignedIn))
    }

    /// The signed-in person's own submissions, in any state.
    func mySubmissions() async throws -> [CommunityRecipe] {
        guard let s = current else { throw BackendError.signedOut }
        let q = [URLQueryItem(name: "author", value: "eq.\(s.userID)"), URLQueryItem(name: "order", value: "created_at.desc")]
        return try Self.decodeRecipes(try await send("rest/v1/community_recipes", query: q))
    }

    /// Submits a recipe for review. It stays private to its author until an admin approves it.
    func submit(_ recipe: Recipe, authorName: String, photoJPEG: Data?) async throws {
        try await refreshIfNeeded()
        guard let s = current else { throw BackendError.signedOut }
        var photoPath: String? = nil
        if let jpeg = photoJPEG {
            let path = "\(s.userID)/\(UUID().uuidString.lowercased()).jpg"
            _ = try await send("storage/v1/object/recipe-photos/\(path)", method: "POST", raw: jpeg, contentType: "image/jpeg")
            photoPath = path
        }
        let recipeJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(recipe))
        var row: [String: Any] = ["recipe": recipeJSON, "author_name": String(authorName.prefix(40))]
        if let photoPath { row["photo_path"] = photoPath }
        _ = try await send("rest/v1/community_recipes", method: "POST", body: row, extraHeaders: ["Prefer": "return=minimal"])
    }

    func withdraw(_ id: String) async throws {
        _ = try await send("rest/v1/community_recipes", query: [URLQueryItem(name: "id", value: "eq.\(id)")], method: "DELETE")
    }

    /// Flags a published recipe for an admin to look at again.
    func report(_ recipeID: String, reason: String) async throws {
        guard isSignedIn else { throw BackendError.signedOut }
        try await refreshIfNeeded()
        _ = try await send("rest/v1/recipe_reports", method: "POST", body: ["recipe_id": recipeID, "reason": String(reason.prefix(500))],
                           extraHeaders: ["Prefer": "return=minimal"])
    }

    // MARK: Admin review (the server only allows this for admins)

    func isAdmin() async -> Bool {
        guard let s = current,
              let data = try? await send("rest/v1/profiles", query: [URLQueryItem(name: "id", value: "eq.\(s.userID)"), URLQueryItem(name: "select", value: "is_admin")]),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return false }
        return (rows.first?["is_admin"] as? Bool) ?? false
    }

    func pendingRecipes() async throws -> [CommunityRecipe] {
        let q = [URLQueryItem(name: "status", value: "eq.pending"), URLQueryItem(name: "order", value: "created_at.asc")]
        return try Self.decodeRecipes(try await send("rest/v1/community_recipes", query: q))
    }

    func review(_ id: String, approve: Bool, reason: String? = nil) async throws {
        guard let s = current else { throw BackendError.signedOut }
        var body: [String: Any] = ["status": approve ? "approved" : "rejected", "reviewed_by": s.userID,
                                   "reviewed_at": ISO8601DateFormatter().string(from: .now)]
        body["reject_reason"] = approve ? NSNull() : (reason ?? "")
        _ = try await send("rest/v1/community_recipes", query: [URLQueryItem(name: "id", value: "eq.\(id)")], method: "PATCH", body: body)
    }

    static func decodeRecipes(_ data: Data) throws -> [CommunityRecipe] {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: s) { return date }
            f.formatOptions = [.withInternetDateTime]
            return f.date(from: s) ?? .distantPast
        }
        return try d.decode([CommunityRecipe].self, from: data)
    }

    // MARK: AI food scan

    /// Sends a downscaled JPEG; returns the estimate and how many scans are left this month.
    func scanFood(jpeg: Data) async throws -> (FoodScan, Int) {
        try await refreshIfNeeded()
        let data = try await send("functions/v1/scan-food", method: "POST",
                                  body: ["image": jpeg.base64EncodedString(), "mediaType": "image/jpeg"], timeout: 60)
        return try Self.parseScan(data)
    }

    /// Fridge or pantry photo: returns the catalog ingredient ids it can see, and scans left this month.
    func scanFridge(jpeg: Data, catalog: [Ingredient]) async throws -> ([String], Int) {
        try await refreshIfNeeded()
        let list = catalog.filter { !$0.staple }.map { ["id": $0.id, "name": $0.name] }
        let data = try await send("functions/v1/scan-food", method: "POST",
                                  body: ["image": jpeg.base64EncodedString(), "mediaType": "image/jpeg", "mode": "fridge", "catalog": list], timeout: 60)
        return try Self.parseFridge(data, known: Set(catalog.map(\.id)))
    }

    static func parseFridge(_ data: Data, known: Set<String>) throws -> ([String], Int) {
        struct Item: Decodable { let id: String }
        struct Result: Decodable { let items: [Item] }
        struct Reply: Decodable { let result: Result; let remaining: Int }
        let r = try JSONDecoder().decode(Reply.self, from: data)
        var seen = Set<String>()
        return (r.result.items.map(\.id).filter { known.contains($0) && seen.insert($0).inserted }, r.remaining)
    }

    static func parseScan(_ data: Data) throws -> (FoodScan, Int) {
        struct Reply: Decodable { let result: FoodScan; let remaining: Int }
        let r = try JSONDecoder().decode(Reply.self, from: data)
        return (r.result, r.remaining)
    }

    // MARK: Plumbing

    @discardableResult
    private func send(_ path: String, query: [URLQueryItem] = [], method: String = "GET", body: [String: Any]? = nil,
                      raw: Data? = nil, contentType: String = "application/json", auth: Bool = true,
                      extraHeaders: [String: String] = [:], timeout: TimeInterval = 20) async throws -> Data {
        guard BackendConfig.isConfigured || base != BackendConfig.url else { throw BackendError.notConfigured }
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!, timeoutInterval: timeout)
        req.httpMethod = method
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(auth ? (current?.accessToken ?? anonKey) : anonKey)", forHTTPHeaderField: "Authorization")
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        for (k, v) in extraHeaders { req.setValue(v, forHTTPHeaderField: k) }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) } else if let raw { req.httpBody = raw }
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: req) } catch { throw BackendError.network }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw Self.error(code: code, data: data) }
        return data
    }

    static func error(code: Int, data: Data) -> BackendError {
        let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let msg = (o?["error"] as? String) ?? (o?["msg"] as? String) ?? (o?["message"] as? String) ?? (o?["error_description"] as? String)
        if code == 429 { return .overLimit(msg ?? "Too many tries. Wait a minute and try again.") }
        if code == 401 { return .signedOut }
        return .server(msg ?? "Something went wrong (\(code)). Try again.")
    }
}

// MARK: - Where the session is kept

protocol SessionStore {
    func load() -> Session?
    func save(_ s: Session?)
}

/// The Keychain on iPhone (survives app updates, never in backups unencrypted); memory elsewhere.
struct KeychainSessionStore: SessionStore {
    private let account = "supperwise.session"
    func load() -> Session? {
        #if canImport(Security)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
        #else
        return nil
        #endif
    }
    func save(_ s: Session?) {
        #if canImport(Security)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
        guard let s, let data = try? JSONEncoder().encode(s) else { return }
        var add = q
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
        #endif
    }
}

final class MemorySessionStore: SessionStore {
    var value: Session?
    init(_ v: Session? = nil) { value = v }
    func load() -> Session? { value }
    func save(_ s: Session?) { value = s }
}

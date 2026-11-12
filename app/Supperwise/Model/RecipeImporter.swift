import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking   // URLSession on Linux (used by the logic tests)
#endif

enum ImportError: LocalizedError {
    case badLink, network, noRecipe
    var errorDescription: String? {
        switch self {
        case .badLink: "That doesn't look like a link."
        case .network: "Couldn't open that page. Check your connection and try again."
        case .noRecipe: "Couldn't find a recipe on that page. Most recipe websites work; TikTok and Instagram are coming."
        }
    }
}

/// Saves recipes from websites by reading the schema.org Recipe data most recipe sites publish (JSON-LD).
/// Ingredients are matched to the catalog by name so they can be priced by the pack; unmatched lines stay as written.
struct RecipeImporter {
    let catalog: Catalog
    var session: URLSession = .shared

    func importRecipe(from link: String) async throws -> Recipe {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme?.hasPrefix("http") == true else { throw ImportError.badLink }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) Supperwise", forHTTPHeaderField: "User-Agent")
        let data: Data
        do { (data, _) = try await session.data(for: req) } catch { throw ImportError.network }
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { throw ImportError.noRecipe }
        return try parse(html: html, source: url.host ?? "link")
    }

    func parse(html: String, source: String) throws -> Recipe {
        for block in Self.jsonLDBlocks(html) {
            guard let data = block.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            if let r = Self.findRecipe(json) { return build(r, source: source) }
        }
        throw ImportError.noRecipe
    }

    static func jsonLDBlocks(_ html: String) -> [String] {
        var out: [String] = []
        var rest = html[...]
        while let start = rest.range(of: "application/ld+json", options: .caseInsensitive),
              let open = rest[start.upperBound...].range(of: ">"),
              let close = rest[open.upperBound...].range(of: "</script>", options: .caseInsensitive) {
            out.append(String(rest[open.upperBound..<close.lowerBound]))
            rest = rest[close.upperBound...]
        }
        return out
    }

    static func findRecipe(_ json: Any) -> [String: Any]? {
        if let d = json as? [String: Any] {
            let type = d["@type"]
            if (type as? String) == "Recipe" || (type as? [String])?.contains("Recipe") == true { return d }
            if let graph = d["@graph"] { return findRecipe(graph) }
        }
        if let a = json as? [Any] { for x in a { if let r = findRecipe(x) { return r } } }
        return nil
    }

    private func build(_ r: [String: Any], source: String) -> Recipe {
        let name = (r["name"] as? String)?.trimmingCharacters(in: .whitespaces) ?? "Saved recipe"
        let lines = (r["recipeIngredient"] as? [String]) ?? []
        var steps: [String] = []
        func collect(_ x: Any) {
            if let s = x as? String { steps.append(s) }
            else if let d = x as? [String: Any] {
                if let t = d["text"] as? String { steps.append(t) }
                if let items = d["itemListElement"] { collect(items) }
            } else if let a = x as? [Any] { a.forEach(collect) }
        }
        if let ins = r["recipeInstructions"] { collect(ins) }
        let servings = Self.servings(r["recipeYield"]) ?? 4
        let minutes = Self.minutes(r["totalTime"] as? String) ?? Self.minutes(r["cookTime"] as? String) ?? 30
        let ingredients = lines.map { match($0) }
        let stableID = "saved_" + String((source + "_" + name).lowercased().filter { $0.isLetter || $0.isNumber }.prefix(60))
        return Recipe(id: stableID, name: name, side: "Saved from \(source).", cuisine: "Saved", minutes: minutes,
                      difficulty: "Saved", protein: "none", allergens: [], equipment: [], spice: 0, ingredients: ingredients,
                      steps: steps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                      photo: nil, vegetarian: false, pescatarian: false, mildNote: nil, vegetarianSwap: nil, servings: servings, source: source)
    }

    /// Matches "2 cans (15 oz) chickpeas, drained" to the catalog's chickpeas by whole words (plural-insensitive).
    /// Unmatched lines keep their text and aren't priced.
    func match(_ line: String) -> RecipeIngredient {
        func stem<S: StringProtocol>(_ w: S) -> String { let s = w.lowercased(); return s.hasSuffix("s") ? String(s.dropLast()) : s }
        let words = Set(line.split(whereSeparator: { !$0.isLetter }).map(stem))
        let best = catalog.ingredients.values.map { i -> (Ingredient, Int) in
            let name = i.name.split(separator: ",").first ?? ""
            return (i, name.split(whereSeparator: { !$0.isLetter }).filter { $0.count > 2 && words.contains(stem($0)) }.count)
        }
        .filter { $0.1 > 0 }
        .max { ($0.1, -$0.0.name.count) < ($1.1, -$1.0.name.count) }?.0
        guard let ing = best else { return RecipeIngredient(ingredient: "", amount: 0, text: line, note: "") }
        // Without a reliable unit parse, assume half a pack is needed so the list prices it by the pack.
        return RecipeIngredient(ingredient: ing.id, amount: ing.unit == .count ? 1 : ing.packSize * 0.5, text: line, note: "")
    }

    static func servings(_ y: Any?) -> Int? {
        if let i = y as? Int { return i }
        let s = (y as? String) ?? (y as? [Any])?.first.map { "\($0)" }
        return s.flatMap { Int($0.filter(\.isNumber).prefix(2)) }
    }

    /// ISO 8601 durations like PT1H15M.
    static func minutes(_ iso: String?) -> Int? {
        guard let iso, iso.hasPrefix("P") else { return nil }
        var total = 0, num = ""
        for c in iso.drop(while: { $0 != "T" }).dropFirst() {
            if c.isNumber { num.append(c) } else {
                let v = Int(num) ?? 0
                if c == "H" { total += v * 60 } else if c == "M" { total += v }
                num = ""
            }
        }
        return total > 0 ? total : nil
    }
}

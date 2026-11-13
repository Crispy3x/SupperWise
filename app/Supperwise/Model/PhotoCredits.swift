import Foundation

/// Credits for the recipe photos (photo-credits.json). They're openly licensed (CC0, public domain, CC BY,
/// CC BY-SA), which allows use in the app with the photographer credited and the license linked.
struct PhotoCredit: Codable, Hashable {
    let title: String
    let creator: String
    let license: String          // cc0, pdm, by, by-sa
    let licenseVersion: String
    let licenseURL: String?
    let page: String?            // where the original lives

    var licenseName: String {
        switch license {
        case "cc0": "CC0"
        case "pdm": "Public domain"
        case "by-sa": "CC BY-SA \(licenseVersion)"
        default: "CC BY \(licenseVersion)"
        }
    }
    /// "Photo: Jane Doe, CC BY 2.0"
    var line: String { license == "pdm" || license == "cc0" ? "Photo: \(creator) (\(licenseName))" : "Photo: \(creator), \(licenseName)" }
}

enum PhotoCredits {
    static let bundled: [String: PhotoCredit] = load()

    static func load(bundle: Bundle = .main) -> [String: PhotoCredit] {
        guard let url = bundle.url(forResource: "photo-credits", withExtension: "json"), let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: PhotoCredit].self, from: data)) ?? [:]
    }
}

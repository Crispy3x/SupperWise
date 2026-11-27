import Foundation

/// Clients sign in to the tracker on the owner's website with their last name and house number instead of a code
/// (server/lookup.mjs). Names never leave the phone: per site the snapshot carries
///   lookup     = SHA-256 of "<salt>|<last name>|<house number>"   (lowercase hex)
///   lookupName = SHA-256 of "<salt>|<last name>"                  (for servers set to PORTAL_LOOKUP=lastname)
/// and the business's random salt. The server hashes what the visitor types the same way and compares.
/// `normalize` must stay the same as normalizeName in server/lookup.mjs.
public enum PortalLookup {
    /// Letters only, lowercase, accents folded, apostrophes and hyphens gone: "O'Neil" -> "oneil", "García" -> "garcia",
    /// "Smith-Jones" -> "smithjones". Compatibility decomposition, combining marks dropped, lowercased, a to z kept.
    public static func normalize(_ text: String) -> String {
        let unmarked = text.decomposedStringWithCompatibilityMapping.unicodeScalars.filter { !(0x300...0x36F).contains($0.value) }
        let lower = String(String.UnicodeScalarView(unmarked)).lowercased()
        return String(String.UnicodeScalarView(lower.unicodeScalars.filter { (97...122).contains($0.value) }))
    }

    /// The name this client signs in with: the owner's "Name for their tracker" when set (used whole), otherwise the last
    /// word of the client's name ("Lakeside Clinic" gives "clinic"). Empty when neither has a letter.
    public static func lastName(for customer: Customer) -> String {
        let own = normalize(customer.portalLastName)
        if !own.isEmpty { return own }
        return customer.name.split(whereSeparator: { $0.isWhitespace }).map { normalize(String($0)) }.last(where: { !$0.isEmpty }) ?? ""
    }

    /// The leading digits of the address: "14B Elm Ave" -> "14". Empty when the address does not start with a number.
    public static func houseNumber(_ address: String) -> String {
        String(address.trimmingCharacters(in: .whitespacesAndNewlines).prefix { $0.isASCII && $0.isNumber }.prefix(10))
    }

    public static func isSalt(_ text: String) -> Bool {
        text.count == 32 && text.allSatisfy { "0123456789abcdef".contains($0) }
    }

    /// 16 random bytes as 32 lowercase hex characters.
    public static func newSalt() -> String {
        var rng = SystemRandomNumberGenerator()
        return (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255, using: &rng)) }.joined()
    }

    /// Nil when there is no usable salt, last name or house number: that site simply cannot be found by name.
    public static func lookup(salt: String, lastName: String, houseNumber: String) -> String? {
        guard isSalt(salt), !lastName.isEmpty, !houseNumber.isEmpty else { return nil }
        return SHA256.hex("\(salt)|\(lastName)|\(houseNumber)")
    }

    public static func lookupName(salt: String, lastName: String) -> String? {
        guard isSalt(salt), !lastName.isEmpty else { return nil }
        return SHA256.hex("\(salt)|\(lastName)")
    }
}

extension AppData {
    /// Makes the business's sign-in salt once. Changing it later would only mean the server needs a new publish.
    public mutating func ensurePortalLookupSalt() {
        if !PortalLookup.isSalt(portalLookupSalt) { portalLookupSalt = PortalLookup.newSalt() }
    }
}

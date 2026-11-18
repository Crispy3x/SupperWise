import Foundation

public enum AccountError: Error, Equatable {
    case missingIdentifier
    case differentAccount
}

/// Who owns this app's data. Sign-in is optional and local for now: it identifies the owner, with no cloud copy.
public struct AccountProfile: Equatable, Codable, Sendable {
    /// Apple's stable identifier for this person and this app (never their email).
    public let appleUserID: String
    public var displayName: String
    public var email: String
    public let createdAt: Date
}

extension AppData {
    /// Records a sign-in. Apple gives the name and email only the first time, so a later sign-in never blanks them.
    public mutating func signIn(appleUserID: String, displayName: String, email: String, now: Date) throws {
        let id = appleUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { throw AccountError.missingIdentifier }
        if var existing = account {
            guard existing.appleUserID == id else { throw AccountError.differentAccount }
            if !displayName.isEmpty { existing.displayName = displayName }
            if !email.isEmpty { existing.email = email }
            account = existing
        } else {
            account = AccountProfile(appleUserID: id, displayName: displayName, email: email, createdAt: now)
        }
    }

    public mutating func signOut() { account = nil }

    /// Everything wiped for "Delete my account and data". The trial or plan is kept: it belongs to the device's Apple
    /// account, and wiping it would let a deleted account start a new free trial.
    public func erasedCopy() -> AppData {
        var fresh = AppData()
        fresh.subscription = subscription
        return fresh
    }
}

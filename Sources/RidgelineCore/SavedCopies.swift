import Foundation

// MARK: - Schema migrations

/// One upgrade of the saved file, from `from` to `from + 1`. It works on the raw JSON so renamed or moved fields can be carried over.
public struct SchemaMigrationStep: Sendable {
    public let from: Int
    public let run: @Sendable (inout [String: Any]) throws -> Void

    public init(from: Int, run: @escaping @Sendable (inout [String: Any]) throws -> Void) {
        self.from = from
        self.run = run
    }
}

public enum SchemaMigrationError: Error, Equatable {
    /// There is no step to upgrade a file saved at this version.
    case missingStep(from: Int)
}

/// Upgrades files saved by older versions of the app instead of failing to read them.
public enum SchemaMigrations {
    /// The format this version of the app writes. When the format changes, raise this by one and add a step for the old number.
    public static let currentVersion = 1
    /// Upgrades in order, one per version. Empty until the format first changes.
    public static let steps: [SchemaMigrationStep] = []

    /// The `schemaVersion` written in a file. Files from before it existed count as 1. Nil when the file is not a JSON object.
    public static func version(of json: Data) -> Int? {
        guard let object = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else { return nil }
        return (object["schemaVersion"] as? Int) ?? 1
    }

    /// Runs every step from the file's version up to `target`, in order. Returns the file unchanged when it is already current
    /// (or newer, or not a JSON object, which the decoder then reports).
    public static func migrate(_ json: Data, steps: [SchemaMigrationStep] = SchemaMigrations.steps,
                               to target: Int = SchemaMigrations.currentVersion) throws -> Data {
        guard var object = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else { return json }
        var version = (object["schemaVersion"] as? Int) ?? 1
        guard version < target else { return json }
        var byVersion: [Int: SchemaMigrationStep] = [:]
        for step in steps where byVersion[step.from] == nil { byVersion[step.from] = step }
        while version < target {
            guard let step = byVersion[version] else { throw SchemaMigrationError.missingStep(from: version) }
            try step.run(&object)
            version += 1
            object["schemaVersion"] = version
        }
        return try JSONSerialization.data(withJSONObject: object)
    }
}

// MARK: - Saved copies of the data file

/// A copy of the data file kept next to it, that the owner can go back to.
public struct SavedCopy: Equatable, Sendable, Identifiable {
    public enum Kind: String, Equatable, Sendable {
        /// data.json.bak: the file as it was the last time the app opened.
        case lastOpened
        /// data-YYYYMMDD.json: the file as it was the first time the app opened that day.
        case daily
        /// before-restore-…json: what was on the device just before a restore.
        case beforeRestore
    }

    public let url: URL
    public let kind: Kind
    /// When the data in this copy was last saved.
    public let savedAt: Date
    public let clientCount: Int

    public var id: String { url.lastPathComponent }

    public var title: String {
        switch kind {
        case .lastOpened: return "Last time the app opened"
        case .daily: return "Daily copy"
        case .beforeRestore: return "Before a restore"
        }
    }

    public var clientText: String { "\(clientCount) client\(clientCount == 1 ? "" : "s")" }

    /// Plain words for the restore notice, such as "the daily copy from Nov 20, 2026 at 6:10 AM (12 clients)".
    public func describe(timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.timeZone = timeZone
        let when = f.string(from: savedAt)
        switch kind {
        case .lastOpened: return "the copy from the last time the app opened, saved \(when) (\(clientText))"
        case .daily: return "the daily copy from \(when) (\(clientText))"
        case .beforeRestore: return "the copy made before a restore on \(when) (\(clientText))"
        }
    }
}

extension AppData {
    /// True when there is real business data worth keeping a copy of.
    var hasBusinessRecords: Bool {
        !(customers.isEmpty && sites.isEmpty && invoices.isEmpty && jobs.isEmpty && quotes.isEmpty
          && team.isEmpty && timeEntries.isEmpty && visitLog.entries.isEmpty)
    }
}

extension FileStore {
    /// How many daily copies are kept. Older ones are deleted.
    public static let dailyCopiesKept = 3

    /// data.json.bak, next to the data file.
    public var backupURL: URL { url.appendingPathExtension("bak") }

    private var folder: URL { url.deletingLastPathComponent() }
    private var baseName: String { url.deletingPathExtension().lastPathComponent }

    /// The file name of the daily copy for a day, such as data-20261121.json.
    public func dailyCopyName(for date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(baseName)-" + String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0) + ".json"
    }

    /// The daily copies on disk, newest day first.
    public func dailyCopyURLs() -> [URL] {
        let prefix = baseName + "-"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { name in
            guard name.hasPrefix(prefix), name.hasSuffix(".json") else { return false }
            let stamp = name.dropFirst(prefix.count).dropLast(5)
            return stamp.count == 8 && stamp.allSatisfy { $0.isASCII && $0.isNumber }
        }
        .sorted(by: >)
        .map { folder.appendingPathComponent($0) }
    }

    /// Deletes daily copies beyond the newest `keep`.
    public func pruneDailyCopies(keep: Int = FileStore.dailyCopiesKept) {
        for old in dailyCopyURLs().dropFirst(max(0, keep)) {
            try? FileManager.default.removeItem(at: old)
        }
    }

    /// After a good load: refreshes data.json.bak, writes today's daily copy if there is none yet, and keeps only the newest
    /// daily copies. A file with no business records is never copied, so it cannot push a good copy out. Returns true if copied.
    @discardableResult
    public func keepCopies(of loaded: AppData, now: Date = Date(), timeZone: TimeZone = .current) -> Bool {
        guard loaded.hasBusinessRecords, let bytes = try? Data(contentsOf: url) else { return false }
        let savedAt = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date) ?? now
        writeCopy(bytes, to: backupURL, savedAt: savedAt)
        let today = folder.appendingPathComponent(dailyCopyName(for: now, timeZone: timeZone))
        if !FileManager.default.fileExists(atPath: today.path) {
            writeCopy(bytes, to: today, savedAt: savedAt)
        }
        pruneDailyCopies()
        return true
    }

    private func writeCopy(_ bytes: Data, to destination: URL, savedAt: Date) {
        do {
            try bytes.write(to: destination, options: .atomic)
            try? FileManager.default.setAttributes([.modificationDate: savedAt], ofItemAtPath: destination.path)
        } catch {
            // A missing copy is not worth stopping the app for; the main file is untouched.
        }
    }

    /// Copies to fall back on when the data file cannot be read, in the order they are tried: data.json.bak, then the
    /// daily copies, newest first.
    public func recoveryCandidates() -> [URL] {
        var list: [URL] = []
        if FileManager.default.fileExists(atPath: backupURL.path) { list.append(backupURL) }
        return list + dailyCopyURLs()
    }

    /// Reads one copy, upgrading it if it was saved by an older version.
    public func readCopy(at file: URL) throws -> AppData {
        let bytes = try Data(contentsOf: file)
        return try Self.decoder.decode(AppData.self, from: SchemaMigrations.migrate(bytes))
    }

    /// The first copy, in recovery order, that can be read.
    func firstReadableCopy() -> (data: AppData, copy: SavedCopy)? {
        for file in recoveryCandidates() {
            guard let data = try? readCopy(at: file) else { continue }
            return (data, savedCopy(at: file, data: data))
        }
        return nil
    }

    private func kind(of file: URL) -> SavedCopy.Kind {
        let name = file.lastPathComponent
        if name == backupURL.lastPathComponent { return .lastOpened }
        if name.hasPrefix("before-restore-") { return .beforeRestore }
        return .daily
    }

    private func savedCopy(at file: URL, data: AppData) -> SavedCopy {
        let date = ((try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date) ?? Date(timeIntervalSince1970: 0)
        return SavedCopy(url: file, kind: kind(of: file), savedAt: date, clientCount: data.customers.count)
    }

    /// Every copy the owner can go back to, newest first: data.json.bak, the daily copies and the copies made before a restore.
    /// Copies that cannot be read, have no business records, or match data.json.bak byte for byte are left out.
    public func savedCopies() -> [SavedCopy] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let beforeRestore = names.filter { $0.hasPrefix("before-restore-") && $0.hasSuffix(".json") }
            .map { folder.appendingPathComponent($0) }
        let lastOpenedBytes = try? Data(contentsOf: backupURL)
        var copies: [SavedCopy] = []
        for file in recoveryCandidates() + beforeRestore {
            guard let bytes = try? Data(contentsOf: file) else { continue }
            if file != backupURL, let lastOpenedBytes, bytes == lastOpenedBytes { continue }
            guard let data = try? Self.decoder.decode(AppData.self, from: SchemaMigrations.migrate(bytes)),
                  data.hasBusinessRecords else { continue }
            copies.append(savedCopy(at: file, data: data))
        }
        return copies.sorted { $0.savedAt > $1.savedAt }
    }
}

// MARK: - Restoring safely

extension DataExport {
    /// Whether a backup has the same owner as this device. Nil when this device has no owner login or Apple account yet.
    /// Every identity both sides have must match, and at least one must be shared.
    public static func sameOwner(backup: AppData, device: AppData) -> Bool? {
        guard device.ownerIsProtected else { return nil }
        var compared = false
        if let mine = device.account?.appleUserID, let theirs = backup.account?.appleUserID {
            if mine != theirs { return false }
            compared = true
        }
        if let mine = device.ownerEmail, let theirs = backup.ownerEmail {
            if mine != theirs { return false }
            compared = true
        }
        return compared
    }

    /// What to warn about before restoring onto a device that has no owner login or Apple account of its own: the backup's
    /// owner sign-in comes with it, everyone is signed out, and getting back in then needs that sign-in. Someone who forgot
    /// it would be locked out again. Nil when this device keeps its own owner sign-in, or the backup has none.
    public static func signInWarning(backup: AppData, device: AppData) -> String? {
        guard !device.ownerIsProtected else { return nil }
        let wayOut = "If you cannot, cancel, create a login in Profile first and then restore. Your new login is kept."
        if let email = backup.ownerEmail {
            return "This backup has its own owner login (\(email)). After restoring you sign in with that email and its password. \(wayOut)"
        }
        if backup.account != nil {
            return "This backup is linked to an Apple account. After restoring you sign in with that Apple account. \(wayOut)"
        }
        return nil
    }

    /// Makes restored data safe to use on this device.
    /// - Nobody stays signed in: whoever uses the app next signs in again.
    /// - If this device already has an owner, the owner's login and Apple account stay exactly as they are here, so the
    ///   person who knows this device's password is never locked out by an older one.
    /// - Employee logins come from the backup only when it has the same owner. A backup from someone else brings no
    ///   password hashes at all, and that owner's assistant consent stays behind too.
    /// - If this device has no owner yet (a new phone), the backup's logins come with it.
    public static func preparedForDevice(_ backup: AppData, current: AppData) -> AppData {
        var out = backup
        out.session = nil
        out.teamSync = current.teamSync?.resetForRestore()   // this device's team link stays; the backup's is not used
        guard let same = sameOwner(backup: backup, device: current) else { return out }
        out.account = current.account
        let ownerLogins = current.logins.filter { $0.role == .owner }
        let employees: [LoginCredential]
        if same {
            employees = backup.logins.filter { $0.role == .employee }
        } else {
            let restoredTeam = Set(backup.team.map(\.id))
            employees = current.logins.filter { login in
                login.role == .employee && login.memberID.map { restoredTeam.contains($0) } == true
            }
            out.assistantConsentAt = current.assistantConsentAt
        }
        let taken = Set(ownerLogins.map(\.username))
        out.logins = ownerLogins + employees.filter { !taken.contains($0.username) }
        return out
    }
}

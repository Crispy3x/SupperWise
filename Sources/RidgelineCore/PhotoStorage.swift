import Foundation

public enum PhotoStorageError: Error, Equatable {
    case missing
    case hashMismatch
}

/// Keeps photo files in a folder and proves they were not swapped: every photo is stored under its own name and
/// its SHA-256 is kept in the visit log.
public struct PhotoStorage: Sendable {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    public func save(_ data: Data, kind: PhotoKind, capturedAt: Date) throws -> PhotoRef {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ref = PhotoRef.make(imageData: data, kind: kind, capturedAt: capturedAt)
        try data.write(to: directory.appendingPathComponent(ref.filename), options: .atomic)
        return ref
    }

    /// The photo's bytes, checked against the hash recorded when it was taken.
    public func data(for ref: PhotoRef) throws -> Data {
        let url = directory.appendingPathComponent(ref.filename)
        guard FileManager.default.fileExists(atPath: url.path) else { throw PhotoStorageError.missing }
        let data = try Data(contentsOf: url)
        let hash = SHA256.hash(Array(data)).map { String(format: "%02x", $0) }.joined()
        guard hash == ref.sha256 else { throw PhotoStorageError.hashMismatch }
        return data
    }

    public func isIntact(_ ref: PhotoRef) -> Bool { (try? data(for: ref)) != nil }

    /// Deletes every stored photo (for "Delete my account and data").
    public func deleteAll() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
}

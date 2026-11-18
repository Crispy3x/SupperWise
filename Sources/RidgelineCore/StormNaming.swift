import Foundation

public enum StormNaming {
    /// The base name if no storm has it, otherwise "name (2)", "name (3)" and so on. Two storms never share a name,
    /// so their messages and requests never get mixed up.
    public static func uniqueName(base: String, existing: [String]) -> String {
        let clean = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = clean.isEmpty ? "Storm" : clean
        guard existing.contains(root) else { return root }
        var n = 2
        while existing.contains("\(root) (\(n))") { n += 1 }
        return "\(root) (\(n))"
    }
}

import Foundation

public enum NoticeKind: String, Codable, CaseIterable, Sendable {
    case scheduled, enRoute, delayed, skipped, complete
}

/// Customer-facing messages. Customers' top complaint is silence, so every status has plain wording.
public enum NoticeTemplates {
    public static func message(_ kind: NoticeKind, company: String, address: String,
                               etaMinutes: Int? = nil, reason: String? = nil, photoLink: String? = nil) -> String {
        switch kind {
        case .scheduled:
            return "\(company): we're planning to service \(address) during the storm. We'll text when we're on the way."
        case .enRoute:
            if let eta = etaMinutes {
                return "\(company): our crew is on the way to \(address), about \(eta) min."
            }
            return "\(company): our crew is on the way to \(address)."
        case .delayed:
            let why = reason.map { " (\($0))" } ?? ""
            if let eta = etaMinutes {
                return "\(company): we're running behind\(why). New estimate for \(address): about \(eta) min."
            }
            return "\(company): we're running behind\(why) and will reach \(address) as soon as we can."
        case .skipped:
            let why = reason ?? "an issue at the site"
            return "\(company): we couldn't service \(address) this visit because of \(why). You won't be charged for this visit. We'll be in touch."
        case .complete:
            let link = photoLink.map { " Photos: \($0)" } ?? ""
            return "\(company): \(address) is done.\(link)"
        }
    }

    /// Completion notices must not go out until the work is documented.
    public static func canSendComplete(record: VisitRecord) -> Bool {
        record.status == .completed && record.hasAfterPhoto
    }
}

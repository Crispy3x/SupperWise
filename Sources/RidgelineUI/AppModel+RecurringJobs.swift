#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Repeating jobs: weekly mowing, monthly service, seasonal contracts. Each visit can be marked on its own.
extension AppModel {
    /// Adds a job and, when `repeatRule` repeats, sets how often it comes back. Returns a message to show, or nil on success.
    public func addJob(title: String, kind: JobKind, customerID: UUID?, siteID: UUID?, start: Date, durationMinutes: Int,
                       assigneeIDs: [UUID], notes: String, isTask: Bool, repeatRule: RepeatRule?) -> String? {
        edit { d in
            let job = try d.addJob(title: title, kind: kind, customerID: customerID, siteID: siteID, start: start,
                                   durationMinutes: durationMinutes, assigneeIDs: assigneeIDs, notes: notes, isTask: isTask, now: Date())
            try d.setJobRepeat(repeatRule, id: job.id)
        }
    }

    /// Marks one visit of a repeating job, leaving the others as they are.
    public func setOccurrenceStatus(_ status: JobStatus, id: UUID, on day: Date) -> String? {
        edit { try $0.setOccurrenceStatus(status, id: id, on: day) }
    }

    /// Stops a repeating job from coming back, or changes how often it does.
    public func setJobRepeat(_ rule: RepeatRule?, id: UUID) -> String? {
        edit { try $0.setJobRepeat(rule, id: id) }
    }
}

extension RepeatRule {
    /// "Repeats every week until Mar 1".
    var fullSummary: String {
        guard repeats, let end = endDate else { return summary }
        return summary + " until " + DateFormatter.make("MMM d, yyyy").string(from: end)
    }
}
#endif

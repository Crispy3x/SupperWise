#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// "On my way" and "Job done" texts sent from this phone (see ClientTexts.swift). No server is involved.
extension AppModel {
    /// Notes on the job that a text to the client went out. Returns a message to show, or nil on success.
    func recordClientText(_ kind: ClientTextKind, jobID: UUID) -> String? {
        var copy = data
        do {
            try copy.recordClientText(kind, jobID: jobID, now: Date())
        } catch let blocker as ClientTextBlocker {
            return blocker.message
        } catch {
            return Self.describe(error)
        }
        data = copy
        save()
        return nil
    }

    /// Drive time to this job in today's planned route, if the job is on it.
    func plannedDriveSeconds(toJob id: UUID) -> Double? {
        plannedRoute?.planned.first { $0.stop.id == id }?.driveSeconds
    }

    /// The latest after photo from today's visit at the job's site, checked against its fingerprint. Nil when there is none.
    func todaysAfterPhotoData(for job: Job) -> Data? {
        guard let ref = data.latestAfterPhoto(siteID: job.siteID, on: Date()), let storage = photoStorage else { return nil }
        return try? storage.data(for: ref)
    }
}
#endif

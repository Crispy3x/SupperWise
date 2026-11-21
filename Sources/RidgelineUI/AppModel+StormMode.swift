#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

/// Storm mode: start a storm with today's jobs, follow progress, finish it with draft invoices. Works without the server.
extension AppModel {
    /// Starts the storm and switches the crew's storm name to it. Returns a problem to show, or nil when it worked.
    public func startStormMode(name: String, inches: Double, siteIDs: [UUID]) -> String? {
        var copy = data
        let run: StormRun
        do {
            run = try copy.startStorm(baseName: name, expectedInches: inches, siteIDs: siteIDs, now: Date())
        } catch let error as StormModeError {
            return Self.stormProblem(error)
        } catch {
            return Self.describe(error)
        }
        data = copy
        save()
        stormName = run.stormName
        plannedRoute = nil
        notice = "Storm \(run.stormName) started. \(run.jobIDs.count) job\(run.jobIDs.count == 1 ? "" : "s") added for today."
        return nil
    }

    /// Finishes the storm in progress and makes the draft invoices. Nil when no storm is in progress.
    public func finishStormMode() -> StormFinishResult? {
        var result: StormFinishResult?
        edit { result = try $0.finishStorm(now: Date()) }
        if result != nil { Task { _ = await republishPortal() } }
        return result
    }

    static func stormProblem(_ error: StormModeError) -> String {
        switch error {
        case .stormAlreadyActive: return "A storm is already in progress. Finish it first."
        case .noSitesChosen: return "Pick at least one site."
        case .noActiveStorm: return "No storm is in progress."
        }
    }
}
#endif

#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore

extension AppModel {
    /// Copies of the data file kept on this device that the owner can go back to, newest first.
    public func savedCopies() -> [SavedCopy] {
        store?.savedCopies() ?? []
    }

    /// Puts one saved copy back, after saving a safety copy of what is on the device now. Everyone signs in again after.
    /// Returns a message for the user.
    public func restoreSavedCopy(_ copy: SavedCopy) -> String {
        do {
            pendingRestore = try DataExport.restore(from: try Data(contentsOf: copy.url))
        } catch BackupError.newerVersion {
            return "That copy was made by a newer version of the app. Update the app first."
        } catch {
            return "That copy could not be read."
        }
        let before = data
        let message = applyPendingRestore()
        if data != before && !savingIsBlocked { loadNotice = nil }
        return message
    }
}
#endif

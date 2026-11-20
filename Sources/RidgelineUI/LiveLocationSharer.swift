#if canImport(SwiftUI) && canImport(CoreLocation)
import Foundation
import CoreLocation
import Observation
import RidgelineCore

/// Shares this device's position with clients' pages while the owner or a crew member has it switched on.
/// It only runs while the app is open, and it sends at most one position every 20 seconds.
@MainActor @Observable
public final class LiveLocationSharer: NSObject, CLLocationManagerDelegate {
    public private(set) var isSharing = false
    public private(set) var note = ""
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var lastSent = Date.distantPast
    @ObservationIgnored private var label = "Truck"
    @ObservationIgnored private var send: ((PortalTruck) async -> Bool)?
    @ObservationIgnored private var inFlight = false

    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 25
    }

    /// `send` returns true when the server took the position.
    public func start(label: String, send: @escaping (PortalTruck) async -> Bool) {
        guard !isSharing else { return }
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted {
            note = "Location is off for this app. Turn it on in Settings, then try again."
            return
        }
        self.label = label
        self.send = send
        isSharing = true
        note = "Finding your position..."
        if status == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.startUpdatingLocation()
    }

    public func stop() {
        guard isSharing else { return }
        manager.stopUpdatingLocation()
        isSharing = false
        send = nil
        note = ""
    }

    private func handle(_ location: CLLocation) async {
        guard isSharing, let send, !inFlight, location.horizontalAccuracy >= 0, location.horizontalAccuracy < 200 else { return }
        guard Date().timeIntervalSince(lastSent) >= 20 else { return }
        inFlight = true
        defer { inFlight = false }
        let ok = await send(PortalTruck(label: label, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude))
        guard isSharing else { return }
        if ok {
            lastSent = Date()
            note = "Sharing. Last sent \(Date().formatted(date: .omitted, time: .shortened))."
        } else {
            note = "Could not reach your server. Still trying."
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in await self.handle(last) }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in if self.isSharing { self.note = "Could not find your position. Still trying." } }
    }

    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if self.isSharing && (status == .denied || status == .restricted) {
                self.stop()
                self.note = "Location was turned off, so sharing stopped."
            }
        }
    }
}
#endif

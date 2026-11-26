#if canImport(SwiftUI) && canImport(CoreLocation)
import Foundation
import CoreLocation
import Observation
import RidgelineCore

/// Shares this device's position with clients' pages while the owner or a crew member has it switched on.
/// It only runs while the app is open. It sends at most one position every 20 seconds, and about one a minute even
/// when the truck is standing still, so a parked truck does not drop off the client's map.
@MainActor @Observable
public final class LiveLocationSharer: NSObject, CLLocationManagerDelegate {
    public private(set) var isSharing = false
    public private(set) var note = ""
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var lastSent = Date.distantPast
    @ObservationIgnored private var label = "Truck"
    @ObservationIgnored private var send: ((PortalTruck) async -> Bool)?
    @ObservationIgnored private var inFlight = false
    @ObservationIgnored private var heartbeat: Task<Void, Never>?

    /// The name this truck is on the map under right now.
    public var sharedLabel: String { label }

    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 25
        #if os(iOS)
        manager.pausesLocationUpdatesAutomatically = false     // a plow that stops to clear a lot must stay on the map
        #endif
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
        // New positions only arrive when the truck moves 25 metres, and the server hides a truck it has not heard from
        // for a few minutes. So when nothing was sent for a while, updates are restarted: that makes the system report
        // where the truck is now (a fresh fix, not an old one sent again), and a parked truck stays on the map.
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                if Task.isCancelled { return }
                guard let sharer = self, sharer.isSharing else { return }
                if Date().timeIntervalSince(sharer.lastSent) >= 50 {
                    sharer.manager.stopUpdatingLocation()
                    sharer.manager.startUpdatingLocation()
                }
            }
        }
    }

    public func stop() {
        guard isSharing else { return }
        manager.stopUpdatingLocation()
        heartbeat?.cancel()
        heartbeat = nil
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

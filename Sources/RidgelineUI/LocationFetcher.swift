#if canImport(CoreLocation)
import CoreLocation
import RidgelineCore

/// One-time "where am I" for checking arrival at a site and for setting the yard location. Asks permission only
/// when first used, and only while the app is open.
@MainActor
public final class LocationFetcher: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<Coordinate?, Never>?

    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    /// The current location, or nil if permission is denied or it could not be found.
    public func currentLocation() async -> Coordinate? {
        guard continuation == nil else { return nil }
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted { return nil }
        return await withCheckedContinuation { cont in
            continuation = cont
            if status == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
        }
    }

    private func finish(_ coordinate: Coordinate?) {
        continuation?.resume(returning: coordinate)
        continuation = nil
    }

    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard self.continuation != nil else { return }
            switch status {
            case .denied, .restricted: self.finish(nil)
            case .notDetermined: break
            default: self.manager.requestLocation()
            }
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let found = locations.last.map { Coordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
        Task { @MainActor in self.finish(found) }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }
}

/// Turns a typed address into map coordinates. The address is sent to Apple's geocoding service.
public enum AddressGeocoder {
    public static func coordinate(for address: String) async -> Coordinate? {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard let mark = try? await CLGeocoder().geocodeAddressString(text).first, let c = mark.location?.coordinate else { return nil }
        return Coordinate(latitude: c.latitude, longitude: c.longitude)
    }
}
#endif

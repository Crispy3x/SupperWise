#if canImport(MapKit)
import MapKit
import RidgelineCore

/// Live drive time for one leg from Apple Maps, on the device. Apple's API handles one origin and destination
/// per request, so use it for the next few legs (`LegRefiner`) and not for a full matrix.
/// Not yet compiled or run: needs Xcode.
public struct MapKitETASource: ETASource {
    public init() {}

    public func etaSeconds(from: Coordinate, to: Coordinate) async throws -> Double {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: from.latitude, longitude: from.longitude)))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: to.latitude, longitude: to.longitude)))
        request.transportType = .automobile
        request.departureDate = Date()
        let response = try await MKDirections(request: request).calculateETA()
        return response.expectedTravelTime
    }
}
#endif

#if canImport(SwiftUI)
import SwiftUI
import RidgelineCore
#if canImport(MapKit)
import MapKit
#endif

/// Measure a lawn, driveway or lot by tapping its corners on the satellite map.
/// `start` centers the map (a site's saved location). Without it, the typed `address` is looked up, then the yard, then the phone's location.
struct MeasureSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var title = "Measure on map"
    var start: Coordinate?
    var address = ""
    var useTitle = "Use this area"
    let onUse: (PropertyMeasurement) -> Void

    @State private var points: [Coordinate] = []

    private var measurement: PropertyMeasurement { PropertyMeasurement(points: points) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.title3.weight(.medium))
                Spacer()
                CircleButton(icon: "xmark", label: "Close") { dismiss() }
            }
            .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 6)
            AppPage(clearTabBar: false) {
                #if canImport(MapKit)
                MeasureMap(points: $points, start: start, address: address, fallback: model.data.depot)
                    .frame(height: 420)
                    .clipShape(RoundedRectangle(cornerRadius: Look.cardCorner, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Look.cardCorner, style: .continuous).stroke(Look.stroke, lineWidth: 1))
                #else
                EmptyCard(icon: "map", title: "Map not available", message: "Measuring needs Apple Maps on this device.")
                #endif
                CardGroup(title: "Area", footer: "Tap each corner of the lawn or lot. Pinch to zoom in close for the best result.") {
                    FactRow(label: "Size", value: points.count < 3 ? "Tap 3 or more corners" : PropertyMeasure.squareFeetText(measurement.squareFeet))
                    RowDivider()
                    FactRow(label: "Acres", value: PropertyMeasure.acresText(measurement.squareFeet))
                    RowDivider()
                    FactRow(label: "Corners", value: "\(points.count)")
                    if points.count >= 2 {
                        RowDivider()
                        FactRow(label: "Edge length", value: "\(Int(measurement.perimeterFeet.rounded())) ft")
                    }
                }
                HStack(spacing: 10) {
                    SecondaryActionButton(title: "Undo", icon: "arrow.uturn.backward") { if !points.isEmpty { points.removeLast() } }
                        .disabled(points.isEmpty).opacity(points.isEmpty ? 0.4 : 1)
                    SecondaryActionButton(title: "Clear", icon: "trash") { points.removeAll() }
                        .disabled(points.isEmpty).opacity(points.isEmpty ? 0.4 : 1)
                }
                PrimaryActionButton(title: useTitle, icon: "checkmark") {
                    onUse(measurement)
                    dismiss()
                }
                .disabled(!measurement.isUsable).opacity(measurement.isUsable ? 1 : 0.4)
            }
        }
        .background(Look.sheet.ignoresSafeArea())
    }
}

#if canImport(MapKit)
/// The satellite map: each tap adds a corner, and the outline closes back to the first corner.
private struct MeasureMap: View {
    @Binding var points: [Coordinate]
    let start: Coordinate?
    let address: String
    let fallback: Coordinate?
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var centered = false

    private var corners: [CLLocationCoordinate2D] {
        points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    var body: some View {
        MapReader { proxy in
            Map(position: $position) {
                UserAnnotation()
                if corners.count >= 3 {
                    MapPolygon(coordinates: corners)
                        .foregroundStyle(Color.yellow.opacity(0.28))
                        .stroke(Color.yellow, lineWidth: 2)
                } else if corners.count == 2 {
                    MapPolyline(coordinates: corners)
                        .stroke(Color.yellow, lineWidth: 2)
                }
                ForEach(Array(corners.enumerated()), id: \.offset) { index, corner in
                    Annotation("Corner \(index + 1)", coordinate: corner) {
                        Circle().fill(Color.yellow)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 1.5))
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.imagery(elevation: .flat))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .onTapGesture { location in
                guard let c = proxy.convert(location, from: .local) else { return }
                points.append(Coordinate(latitude: c.latitude, longitude: c.longitude))
            }
        }
        .overlay(alignment: .bottomLeading) {
            Text(points.count < 3 ? "Tap the corners" : PropertyMeasure.squareFeetText(PropertyMeasure.areaSquareFeet(points)))
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule()).padding(14)
        }
        .task { await center() }
    }

    private func center() async {
        guard !centered else { return }
        centered = true
        var found = start
        if found == nil { found = await AddressGeocoder.coordinate(for: address) }
        guard let target = found ?? fallback else { return }
        let c = CLLocationCoordinate2D(latitude: target.latitude, longitude: target.longitude)
        position = .region(MKCoordinateRegion(center: c, latitudinalMeters: 140, longitudinalMeters: 140))
    }
}
#endif
#endif

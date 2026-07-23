import SwiftUI
import MapKit

/// Draws the route line plus waypoint markers colored by hazard tier. Uses the
/// iOS 17 Map API with MapPolyline and Annotations.
struct RouteMapView: View {
    let plan: TripPlan
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $position) {
            // The route line.
            MapPolyline(coordinates: plan.routeGeometry)
                .stroke(.blue, lineWidth: 4)

            // Waypoint markers — show hazardous ones plus the two endpoints
            // (identified by stable index, not fragile float comparison).
            ForEach(markerWaypoints) { wp in
                Annotation(wp.city ?? "", coordinate: wp.coordinate) {
                    Image(systemName: wp.tier.systemIcon)
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(wp.tier.color, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                }
            }

            // Stop markers sit at the resolved POI when we have one, else at
            // the route point. Label shows the real establishment name.
            ForEach(plan.stops) { stop in
                Annotation(stop.poi?.name ?? (stop.kind == .fuel ? "Fuel" : "Rest"),
                           coordinate: stop.poi?.coordinate ?? stop.coordinate) {
                    Image(systemName: stop.kind == .fuel ? "fuelpump.fill" : "cup.and.saucer.fill")
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(stop.nudged ? Color.purple : Color.secondary,
                                    in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Endpoints (first and last by index) plus any non-clear waypoint.
    private var markerWaypoints: [Waypoint] {
        let lastIndex = plan.waypoints.last?.index
        return plan.waypoints.filter {
            $0.tier != .clear || $0.index == 0 || $0.index == lastIndex
        }
    }
}

import SwiftUI
import MapKit

/// Full-screen live navigation-style view. Follows the user's real location,
/// draws the route and stops, and surfaces the announcement banner when a stop
/// is ~15 minutes out (with a spoken cue via LiveTripManager).
struct LiveTripView: View {
    let plan: TripPlan
    @Environment(\.dismiss) private var dismiss
    @StateObject private var live: LiveTripManager
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)

    init(plan: TripPlan) {
        self.plan = plan
        _live = StateObject(wrappedValue: LiveTripManager(plan: plan))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $camera) {
                UserAnnotation()
                MapPolyline(coordinates: plan.routeGeometry)
                    .stroke(.blue, lineWidth: 5)
                ForEach(plan.stops) { stop in
                    Annotation(stop.poi?.name ?? (stop.kind == .fuel ? "Fuel" : "Rest"),
                               coordinate: stop.poi?.coordinate ?? stop.coordinate) {
                        Image(systemName: stop.kind == .fuel ? "fuelpump.fill" : "cup.and.saucer.fill")
                            .foregroundStyle(.white).padding(6)
                            .background(stop.nudged ? Color.purple : Color.secondary, in: Circle())
                    }
                }
            }
            .mapControls { MapUserLocationButton() }
            .ignoresSafeArea()

            VStack(spacing: 12) {
                // Announcement banner.
                if let banner = live.currentBanner {
                    bannerView(banner)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer()

                // Persistent "next stop" strip.
                if let stop = live.nextStop, let miles = live.distanceToNextStopMiles {
                    nextStopStrip(stop: stop, miles: miles)
                }
            }
            .padding()
            .animation(.spring(duration: 0.4), value: live.currentBanner)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                live.stop(); dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline).foregroundStyle(.primary)
                    .padding(10).background(.ultraThinMaterial, in: Circle())
            }
            .padding()
        }
        .onAppear { live.start() }
        .onDisappear { live.stop() }
    }

    private func bannerView(_ banner: LiveTripManager.LiveBanner) -> some View {
        HStack(spacing: 12) {
            Image(systemName: banner.systemIcon)
                .font(.title3)
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(banner.title).font(.subheadline).bold().foregroundStyle(.white)
                Text(banner.subtitle).font(.caption).foregroundStyle(.white.opacity(0.9))
            }
            Spacer()
        }
        .padding()
        .background(banner.isHazard ? Color.red : Color.blue, in: RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 8)
    }

    private func nextStopStrip(stop: PlannedStop, miles: Double) -> some View {
        HStack(spacing: 12) {
            Image(systemName: stop.kind == .fuel ? "fuelpump.fill" : "cup.and.saucer.fill")
                .foregroundStyle(stop.nudged ? .purple : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Next: \(stop.poi?.name ?? stop.city ?? "stop")")
                    .font(.subheadline).bold()
                Text(stop.nudged ? "Moved to avoid weather" : "On your route")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(String(format: "%.0f mi", miles))
                .font(.headline).monospacedDigit()
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

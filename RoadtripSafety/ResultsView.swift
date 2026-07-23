import SwiftUI

/// "Your Trip" — Image 2 layout: a collapsible map header, the always-visible
/// hazard banner, then a Weather / Stops segmented control so each list gets the
/// full screen instead of competing for space.
struct ResultsView: View {
    let plan: TripPlan
    let originName: String
    let destName: String

    enum Segment: String, CaseIterable { case weather = "Weather", stops = "Stops" }

    @State private var showLiveTrip = false
    @State private var mapExpanded = true
    @State private var segment: Segment = .stops

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                mapHeader
                statRow
                SafetyBanner(plan: plan)
                segmentedControl

                switch segment {
                case .weather: WeatherList(plan: plan)
                case .stops:   StopsList(plan: plan)
                }

                DisclaimerFooter()
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) { startButton }
        .navigationTitle("Your Trip")
        .navigationBarTitleDisplayMode(.large)
        .scrollContentBackground(.hidden)
        .background(ScreenGradient())
        .fullScreenCover(isPresented: $showLiveTrip) {
            LiveTripView(plan: plan)
        }
    }

    // MARK: - Map header (collapsible)

    private var mapHeader: some View {
        VStack(spacing: 0) {
            if mapExpanded {
                RouteMapView(plan: plan)
                    .overlay(alignment: .bottomTrailing) {
                        collapseButton(expanded: true)
                            .padding(10)
                    }
            } else {
                Button {
                    withAnimation(.easeInOut) { mapExpanded = true }
                } label: {
                    HStack {
                        Image(systemName: "map")
                        Text("Show map").font(.subheadline)
                        Spacer()
                        Image(systemName: "chevron.down")
                    }
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func collapseButton(expanded: Bool) -> some View {
        Button {
            withAnimation(.easeInOut) { mapExpanded.toggle() }
        } label: {
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.subheadline).foregroundStyle(.primary)
                .padding(8)
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    // MARK: - Stat row

    private var statRow: some View {
        HStack {
            stat("\(Int(plan.distanceMiles)) mi", "Distance", "ruler")
            Divider().frame(height: 40)
            stat(durationText, "Duration", "clock")
            Divider().frame(height: 40)
            stat("\(Int(plan.avgSpeedMph)) mph", "Avg speed", "gauge.with.dots.needle.67percent")
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func stat(_ value: String, _ label: String, _ icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(.blue).font(.subheadline)
            Text(value).font(.headline)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Segmented control

    private var segmentedControl: some View {
        Picker("View", selection: $segment) {
            Text("☁ Weather").tag(Segment.weather)
            Text("📍 Stops (\(plan.stops.count))").tag(Segment.stops)
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Start button

    private var startButton: some View {
        Button {
            showLiveTrip = true
        } label: {
            HStack {
                Text("🚗")
                Text("Start Trip").bold()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .padding()
        .background(.ultraThinMaterial)
    }

    private var durationText: String {
        let total = Int(plan.durationSec)
        let h = total / 3600
        let m = (total % 3600) / 60
        return h > 0 ? "\(h) hr \(m) min" : "\(m) min"
    }
}

/// Small persistent advisory line under a plan.
struct DisclaimerFooter: View {
    var body: some View {
        Text("Advisory only — verify with official sources (weather.gov) and use your own judgment. Conditions can change without warning.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.top, 4)
    }
}

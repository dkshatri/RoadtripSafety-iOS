import SwiftUI

// MARK: - Safety banner (shared)

/// The always-visible hazard banner. Escalates green → orange → red, and shows
/// a distinct blue "no coverage" state outside the US. Safety-critical, so it's
/// never hidden behind a toggle.
struct SafetyBanner: View {
    let plan: TripPlan

    var body: some View {
        if !plan.hasWeatherCoverage {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "globe.americas.fill").foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Route planned — live weather unavailable here")
                        .font(.subheadline).bold().foregroundStyle(.primary)
                    Text("Severe-weather warnings currently cover the US only. Your route, fuel, and rest stops are ready, but check local forecasts for this trip.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        } else if plan.hasCritical {
            let crit = plan.criticalWaypoints
            HStack(alignment: .top, spacing: 12) {
                Text("🛑").font(.title3)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Severe weather warning")
                        .font(.headline).foregroundStyle(.white)
                    Text("Stops and timing were adjusted to avoid the worst of it.")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.95))
                    ForEach(crit) { w in
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(w.alert?.event ?? "Warning") — \(w.city ?? "route")")
                                .font(.subheadline).bold().foregroundStyle(.white)
                            Text("ETA \(shortTime(w.etaISO)): \(hazardDetail(w))")
                                .font(.caption).foregroundStyle(.white.opacity(0.9))
                        }
                        .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red, in: RoundedRectangle(cornerRadius: 16))
        } else if !plan.watchWaypoints.isEmpty {
            Label("\(plan.watchWaypoints.count) watch/advisory condition(s) on route",
                  systemImage: "exclamationmark.circle.fill")
                .font(.subheadline).foregroundStyle(.orange)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        } else {
            Label("No active warnings on your route", systemImage: "checkmark.circle.fill")
                .font(.subheadline).foregroundStyle(.green)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    /// Pull a short human detail from the alert headline, if any.
    private func hazardDetail(_ w: Waypoint) -> String {
        if let h = w.alert?.headline, !h.isEmpty { return h }
        return w.conditions
    }
}

// MARK: - Weather list (shared)

/// The per-waypoint weather list — conditions at each checkpoint's arrival time.
struct WeatherList: View {
    let plan: TripPlan

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(plan.waypoints.enumerated()), id: \.element.id) { idx, wp in
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(wp.tier.color.opacity(0.18)).frame(width: 40, height: 40)
                        Image(systemName: wp.tier.systemIcon).foregroundStyle(wp.tier.color)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(wp.city ?? String(format: "%.2f, %.2f", wp.coordinate.latitude, wp.coordinate.longitude))
                            .font(.headline)
                        HStack(spacing: 4) {
                            Text(wp.conditions)
                            if let t = wp.temp { Text("· \(t)°") }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(shortTime(wp.etaISO)).font(.headline).monospacedDigit()
                }
                .padding(.vertical, 12)
                if idx < plan.waypoints.count - 1 { Divider() }
            }
        }
        .padding(.horizontal, 16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Stops list (shared)

/// The planned fuel/rest stops, each with resolved POI and nudge reasoning.
struct StopsList: View {
    let plan: TripPlan

    var body: some View {
        if plan.stops.isEmpty {
            Text("Route too short for scheduled stops.")
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        } else {
            VStack(spacing: 14) {
                ForEach(plan.stops) { stop in
                    StopCard(stop: stop)
                }
            }
        }
    }
}

/// A single stop card, matching the mockups: colored icon, NUDGED tag, POI name,
/// off-route distance, and (for nudged stops) the plain-English reason box.
struct StopCard: View {
    let stop: PlannedStop

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(stop.nudged ? Color.purple : Color.blue)
                        .frame(width: 40, height: 40)
                    Image(systemName: stop.kind == .fuel ? "fuelpump.fill" : "cup.and.saucer.fill")
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(stop.kind == .fuel ? "FUEL STOP" : "REST STOP")
                            .font(.caption).bold()
                            .foregroundStyle(stop.nudged ? .purple : .secondary)
                        if stop.nudged {
                            Text("↝ NUDGED").font(.caption2).bold()
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.purple.opacity(0.15), in: Capsule())
                                .foregroundStyle(.purple)
                        }
                    }
                    Text(stop.poi?.name ?? stop.city ?? "Stop").font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(shortTime(stop.etaISO)).font(.headline).monospacedDigit()
            }

            if stop.nudged {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.square.fill").foregroundStyle(.secondary).font(.caption)
                    Text(stop.reason).font(.caption).foregroundStyle(.primary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(stop.nudged ? Color.purple.opacity(0.5) : Color.clear, lineWidth: 1)
        )
    }

    private var subtitle: String {
        var parts: [String] = []
        if let poi = stop.poi {
            if let cat = poi.category { parts.append(cat) }
            parts.append(String(format: "%.1f mi off route", poi.distanceMiles))
        }
        if let city = stop.city { parts.append(city) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Combined timeline (kept for compatibility / simple contexts)

/// The original stacked timeline: banner + weather + stops. Still usable, though
/// ResultsView now presents weather and stops via a segmented control instead.
struct TripTimelineView: View {
    let plan: TripPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SafetyBanner(plan: plan)
            Text("Weather along route").font(.headline)
            WeatherList(plan: plan)
            Text("Planned stops").font(.headline)
            StopsList(plan: plan)
        }
    }
}

import Foundation
import CoreLocation
import AVFoundation

/// Drives the live trip: tracks real GPS location, figures out the next stop
/// ahead, and fires a banner + spoken announcement when that stop is roughly
/// 15 minutes away. Real GPS means this does nothing in the Simulator unless a
/// GPX route is supplied (Xcode: Debug > Simulate Location) — it's built for a
/// real device.
@MainActor
final class LiveTripManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    // What the UI shows.
    @Published var currentBanner: LiveBanner?
    @Published var distanceToNextStopMiles: Double?
    @Published var nextStop: PlannedStop?
    @Published var authorized = false

    private let plan: TripPlan
    private let manager = CLLocationManager()
    private let speaker = AVSpeechSynthesizer()

    // Track which stops we've already announced so we announce each once.
    private var announcedStopIDs = Set<UUID>()
    // Assumed cruising speed for the "15 minutes away" trigger distance.
    private let assumedMph: Double

    struct LiveBanner: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let subtitle: String
        let systemIcon: String
        let isHazard: Bool
    }

    init(plan: TripPlan) {
        self.plan = plan
        self.assumedMph = max(plan.avgSpeedMph, 30)
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.activityType = .automotiveNavigation
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        speaker.stopSpeaking(at: .immediate)
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            authorized = (status == .authorizedWhenInUse || status == .authorizedAlways)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in self.handle(location: loc) }
    }

    // MARK: - Core logic

    private func handle(location: CLLocation) {
        // Find the nearest stop ahead that we haven't passed. We approximate
        // "ahead" as any stop we haven't announced yet, choosing the closest.
        let upcoming = plan.stops
            .filter { !announcedStopIDs.contains($0.id) }
            .map { stop -> (PlannedStop, Double) in
                let stopLoc = CLLocation(latitude: stop.coordinate.latitude,
                                         longitude: stop.coordinate.longitude)
                return (stop, location.distance(from: stopLoc) / 1609.34)
            }
            .sorted { $0.1 < $1.1 }

        guard let (stop, miles) = upcoming.first else {
            nextStop = nil
            distanceToNextStopMiles = nil
            return
        }

        nextStop = stop
        distanceToNextStopMiles = miles

        // Trigger distance for ~15 minutes out at assumed speed.
        let triggerMiles = assumedMph * (15.0 / 60.0)

        if miles <= triggerMiles {
            announce(stop: stop)
            announcedStopIDs.insert(stop.id)
        }
    }

    private func announce(stop: PlannedStop) {
        let place = stop.poi?.name ?? stop.city ?? "your next stop"
        let kindWord = stop.kind == .fuel ? "fuel stop" : "rest stop"

        let bannerTitle = "\(stop.kind == .fuel ? "Fuel" : "Rest") stop in about 15 minutes"
        let bannerSub = "\(place)\(stop.nudged ? " · moved to avoid weather" : "")"

        currentBanner = LiveBanner(
            title: bannerTitle,
            subtitle: bannerSub,
            systemIcon: stop.kind == .fuel ? "fuelpump.fill" : "cup.and.saucer.fill",
            isHazard: stop.tier == .critical || stop.tier == .watch
        )

        let spoken = "Your \(kindWord) at \(place) is coming up in about 15 minutes."
        speak(spoken)
    }

    /// Announce an upcoming hazard directly (can be called by the view when the
    /// user crosses into a warned segment). Kept public for future use.
    func announceHazard(_ waypoint: Waypoint) {
        guard let alert = waypoint.alert else { return }
        currentBanner = LiveBanner(
            title: alert.event,
            subtitle: "Near \(waypoint.city ?? "your route") — stay alert",
            systemIcon: "exclamationmark.triangle.fill",
            isHazard: true
        )
        speak("Weather alert ahead. \(alert.event) near \(waypoint.city ?? "your route").")
    }

    private func speak(_ text: String) {
        // Route audio so it ducks music / plays over Bluetooth car audio.
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        speaker.speak(utterance)
    }
}

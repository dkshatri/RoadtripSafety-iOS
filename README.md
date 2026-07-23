# RoadtripSafety — iOS

Native SwiftUI app for weather-aware road trip planning. Plan a trip between two
places and see **the weather you'll actually hit at the time you'll be there**,
severe-weather warnings along the route, and fuel/rest stops **repositioned to
avoid hazard windows** — each with a plain-English reason.

Requires the [RoadtripSafety Engine](https://github.com/YOUR-USERNAME/Roadtrip-safety-engine)
backend, which does the routing, weather, and stop-nudging. This app is the
interface plus on-device POI resolution.

## Screens

- **Advisory** — one-time disclaimer on first launch (this is an advisory tool,
  not a guarantee).
- **Plan a Trip** — address autocomplete for origin/destination, optional custom
  stops along the way, departure time, fuel range and break cadence sliders.
- **Your Trip** — collapsible route map with hazard pins, trip stats, an
  always-visible safety banner, and a Weather / Stops toggle.
- **Live Trip** — follows your GPS and speaks an announcement when a stop is
  ~15 minutes ahead.

## Requirements

- **Xcode 15+** (iOS 17 target — uses the modern `Map` API)
- A running instance of the backend (local or deployed)
- No Apple Developer account needed for the Simulator

## Setup

Full step-by-step in **[SETUP.md](SETUP.md)**. The short version:

1. Create a new Xcode project: **iOS → App**, named `RoadtripSafety`, SwiftUI,
   Swift. Delete its two starter files.
2. Drag in the source files with **Add to targets: RoadtripSafety** checked.
   Decline the Objective-C bridging header prompt.
3. Point the app at your backend — in `Services/APIClient.swift`:
   ```swift
   static var baseURL = URL(string: "https://your-api.onrender.com")!
   ```
4. Add the location permission on the target's **Info** tab:
   **Privacy - Location When In Use Usage Description**
5. Pick a simulator and Run.

If you're testing against `http://localhost:3000`, you also need an App Transport
Security exception — see SETUP.md step B7.

Verify every file made it into **Build Phases → Compile Sources**
(see FILE_MANIFEST.txt). A missing file is the cause of nearly every
"Cannot find X in scope" error.

## Architecture

```
Models/
  Models.swift              TripPlan, Waypoint, PlannedStop, StopPOI, HazardTier
Services/
  APIClient.swift           calls the backend POST /plan, maps JSON → models
  AddressSearchService.swift  MKLocalSearchCompleter autocomplete + geocoding
  POIService.swift          MapKit search for real gas stations / rest areas
  LiveTripManager.swift     CoreLocation tracking + AVSpeechSynthesizer voice
  ISODate.swift             tolerant ISO-8601 parsing
Views/
  ContentView.swift         plan screen
  ResultsView.swift         "Your Trip" — map, stats, banner, Weather/Stops toggle
  TripTimelineView.swift    SafetyBanner, WeatherList, StopsList, StopCard
  RouteMapView.swift        route polyline + hazard/stop annotations
  LiveTripView.swift        live GPS map with announcement banner
  AdvisoryView.swift        first-launch disclaimer
  AddressField.swift        autocomplete text field
  PlanningLoadingView.swift loading overlay
  ScreenGradient.swift      shared background gradient
  TripViewModel.swift       state + orchestration
```

## How the split works

```
iPhone  ──POST /plan──▶  Backend  ──▶ OSRM (routing)
                            │       └─▶ National Weather Service
        ◀──TripPlan JSON────┘
   │
   └─▶ MapKit resolves real gas-station names on-device
```

Routing, weather, and the nudge algorithm run on the server — shared, cacheable,
and one place to change. POI lookup stays on the phone because MapKit is a
device-only API (and it's free there).

`Services/Planner.swift`, `RoutingService.swift`, and `NWSService.swift` are the
original on-device engine, kept on disk as a possible offline fallback but
**removed from Compile Sources** (SETUP.md B5) since the server does that work now.

## Live trip mode

"Start Trip" uses **real GPS**, so it only does something meaningful on a physical
iPhone in motion. In the Simulator, feed it fake movement via
**Debug ▸ Simulate Location** or a GPX file. Announcements play through the system
speech synthesizer and duck other audio, so they work over Bluetooth car audio.

## Known limitations

- **US-only weather.** The backend uses NWS. Trips elsewhere still route and get
  stops, and the app shows an honest "live weather unavailable here" banner
  rather than implying clear conditions.
- **POI search is sequential.** MapKit requires main-actor serialization, so a
  trip with several stops resolves names over a couple of seconds.
- **Rural gaps.** MapKit sometimes returns no POI on remote stretches; the stop
  stays valid but unnamed rather than inventing a station.
- **No accounts or history yet.** Trips aren't persisted between launches.

## Advisory

This is a planning aid, not a safety guarantee. It doesn't control weather or
road conditions and can't guarantee forecasts, alerts, or routes are accurate,
complete, or current. Always verify with official sources
([weather.gov](https://www.weather.gov)) and local authorities, and use your own
judgment before and during travel.

## Copyright and license

Copyright © 2026 Divya Kshatri. All rights reserved.

This source code is made publicly viewable for reference and portfolio purposes
only. It is **not** licensed for reuse.

No permission is granted to copy, modify, merge, publish, distribute, sublicense,
create derivative works from, or sell any part of this software, in whole or in
part, without prior written permission from the copyright holder.

Viewing the code and referencing its techniques for learning is welcome.
Republishing it, deploying it as a service, or incorporating it into another
product is not.

If you'd like to use any part of this project, please open an issue or get in
touch — I'm open to discussing it.

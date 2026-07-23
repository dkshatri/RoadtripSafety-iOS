# Road Trip Safety — iOS app (SwiftUI)

Native SwiftUI app that ports the road-trip planning engine to Swift: real OSRM
routing, live NWS forecasts and alert polygons, ETA-matched weather, and
fuel/rest stops nudged off hazards — all running on-device, no backend.

This runs in the **iOS Simulator** on your Mac. You do NOT need an Apple
Developer account.

## What you need

- A Mac with **Xcode 15 or newer** (free from the Mac App Store — it's a large
  download, ~7 GB, so start it first). Xcode includes the iOS Simulator.

## One-time setup: create the Xcode project

A `.xcodeproj` file is fragile to hand-edit, so you'll create an empty project
in Xcode (about 30 seconds) and drop these source files in.

1. Open **Xcode** → **Create New Project**.
2. Choose **iOS** → **App**, click Next.
3. Fill in:
   - Product Name: **RoadtripSafety** (exactly, so it matches the code)
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Leave "Use Core Data" and "Include Tests" unchecked.
4. Click Next, pick any folder to save it, click Create.
5. Xcode opens with a starter project containing `RoadtripSafetyApp.swift` and
   `ContentView.swift`. **Delete both** (right-click → Delete → Move to Trash).
6. In Finder, open the `RoadtripSafety` folder from this bundle. Select all the
   `.swift` files and the folders (`Models`, `Services`, `Views`,
   `RoadtripSafetyApp.swift`).
7. Drag them into the Xcode file navigator (the left panel), dropping them onto
   the yellow **RoadtripSafety** group. In the dialog that appears:
   - Check **Copy items if needed**
   - Check **Create groups**
   - Ensure the **RoadtripSafety** target is checked
   - Click Finish.
8. Xcode may then ask **"Would you like to configure an Objective-C bridging
   header?"** — click **Don't Create**. This project is 100% Swift; the prompt
   appears on any multi-file add and a bridging header is only needed when mixing
   in Objective-C, which we don't. Choosing "Don't Create" is correct and changes
   nothing about the build.

## Enable network + location

The app uses your location for the live trip map and to center the map. Add
this permission string:

1. Click the blue **RoadtripSafety** project icon at the top of the navigator.
2. Select the **RoadtripSafety** target → **Info** tab.
3. Add one row (hover a row, click +):
   - Key: **Privacy - Location When In Use Usage Description**
   - Value: `Used to show your position on the map and announce upcoming stops during a trip.`

(Modern Xcode manages App Transport Security so calls to https endpoints like
api.weather.gov and router.project-osrm.org work without extra config. Both are
https, so no ATS exception is needed. Spoken announcements use AVSpeechSynthesizer,
which needs no permission.)

## Run it

1. At the top of Xcode, next to the Run button, pick a simulator — e.g.
   **iPhone 15** — or your own iPhone (plugged in) to test live GPS.
2. Press the **Run** button (▶) or Cmd+R.
3. On first launch you'll see the **Advisory** screen — tap "I Understand,
   Continue" (it's shown only once). Then the **Plan a Trip** screen appears.
4. Type a city or address for origin and destination — suggestions appear as you
   type; tap one to fill it. Set departure, adjust the sliders, tap **Plan
   Route**. The loading screen shows, then the **Your Trip** results appear.

## About "Start Trip" (live mode)

Tapping **Start Trip** opens a live map that follows your real GPS location and
speaks an announcement when a fuel/rest stop is about 15 minutes ahead.

**Important:** this uses real GPS, so it only does something meaningful on a
real iPhone while actually moving. In the Simulator there's no real movement —
to test it there, use Xcode's **Debug ▸ Simulate Location** (or attach a GPX
route) to feed the simulator fake movement. On a real device it works as you'd
expect. The voice uses the system speech synthesizer and ducks car audio over
Bluetooth.

## What you'll see

After planning: a map with the route and hazard-colored markers, a three-stat
header (distance / duration / avg speed), a safety banner (green → red by
severity), per-waypoint weather at your arrival times, and your fuel/rest stops
with nudge reasons and resolved
reasons.

## Trying your own trips

Coordinates are `lat,lon`. Grab them by right-clicking any point in Google Maps
— the lat/lon appears at the top of the menu; click to copy. Paste into the
Origin / Destination fields.

## How the code maps to the Node engine

| Swift file | Node equivalent | Role |
|---|---|---|
| `Services/RoutingService.swift` | `routing.js` | OSRM route, polyline decode, ETA sampling |
| `Services/NWSService.swift` | `nws.js` | forecast + alert polygons, time matching |
| `Services/Planner.swift` | `planner.js` | hazard scoring, point-in-polygon, nudging |
| `Services/POIService.swift` | (new) | MapKit search for real gas stations / rest areas |
| `Services/ISODate.swift` | (new) | tolerant ISO date parsing |
| `Models/Models.swift` | (the shapes) | Swift structs for plan/waypoint/stop/POI |
| `Views/*` | (new) | SwiftUI map + timeline UI |

The planning algorithm is identical to the Node version you already tested —
same range logic, same nudge rule, same reason strings. POI resolution is a new
stage layered on top: after the plan is computed, each stop's route coordinate
is searched via MapKit for the nearest real establishment.

## How POI search works

After `planTrip` returns, the view model calls `POIService.enrich(stops:)`. For
each stop it runs an `MKLocalSearch`: fuel stops filter on Apple's `.gasStation`
point-of-interest category, rest stops query "rest area" and fall back to
gas/café/restaurant. The nearest result to the stop's route point is attached as
`stop.poi`, and the map pin + timeline row update to show the real name and how
far off-route it sits. The plan shows immediately; POI names fill in a moment
later (progressive loading).

## Honest status

- This is syntax-checked but **not compile-verified** by me (I don't have Xcode
  in my environment). Expect to fix a small type error or two on first build —
  Xcode will point right at them. The logic is a faithful port of the tested
  Node engine.
- POI searches run sequentially on the main actor (MapKit's requirement), so a
  trip with many stops resolves names over a couple of seconds rather than all
  at once. Fine for the handful of stops a normal trip has.
- MapKit local search occasionally returns nothing on very rural stretches — the
  stop stays valid, just without a named establishment.
- The departure-time slider from the earlier web prototype isn't in this build
  yet; the DatePicker sets a single departure. Adding the slider means calling
  `planTrip` across several departure times and comparing hazard counts.
- US-only (NWS coverage). Off-grid coordinates surface a clear error.

# PhoneThing

A driving companion app: a distraction-free, "lap time"-style display for turn-by-turn
trips, built on MapKit/CoreLocation.

## Current stage: 2 — speed limit + landscape layout

Landscape-locked, speed + speed limit readout pushed to the left (leaving room for the
map in a later stage). Current speed shades from green to red the further it climbs
over the speed limit. Speed limit is looked up from OpenStreetMap's public Overpass
API (nearest tagged road within 25m of your location) — Apple doesn't expose speed
limit data through any public API, so this is the closest free, keyless equivalent.
Coverage depends on how well the local roads are tagged in OSM; an unanswered lookup
just keeps the last known value rather than blanking out. No map or timing yet — those
come in later stages.

## Building (requires a Mac with Xcode)

This project's `.xcodeproj` is generated from [`project.yml`](project.yml) via
[XcodeGen](https://github.com/yonaskolb/XcodeGen), so the fragile Xcode project file
itself isn't committed to git.

1. Install XcodeGen once: `brew install xcodegen`
2. From the project root: `xcodegen generate`
3. Open `PhoneThing.xcodeproj` in Xcode.
4. In the project settings, set your own Team under Signing & Capabilities (the
   `DEVELOPMENT_TEAM` in `project.yml` is left blank).
5. Run on a **real device** — the simulator has no real GPS speed. To test without
   driving, you can feed the simulator a simulated route: in Xcode, with the app
   running, use Debug → Simulate Location → and choose/add a GPX route (e.g. Apple's
   built-in "City Run" or "Freeway Drive" simulations report varying speed).
6. Allow the location permission prompt when the app launches.

Whenever `project.yml` changes, re-run `xcodegen generate`.

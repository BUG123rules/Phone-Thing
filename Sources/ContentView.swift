import SwiftUI
import MapKit

struct ContentView: View {
    @StateObject private var speedProvider: LocationSpeedProvider
    @StateObject private var speedBlender: SpeedBlender
    @StateObject private var speedLimitProvider: SpeedLimitProvider
    @StateObject private var driveTimer = DriveTimer()
    @StateObject private var routePlanner: RoutePlanner
    @StateObject private var destinationSearch: DestinationSearchService

    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var isShowingStartSearch = false
    @State private var isShowingDestinationSearch = false

    init() {
        let provider = LocationSpeedProvider()
        _speedProvider = StateObject(wrappedValue: provider)
        _speedBlender = StateObject(wrappedValue: SpeedBlender(locationProvider: provider))
        _speedLimitProvider = StateObject(wrappedValue: SpeedLimitProvider(locationProvider: provider))
        _routePlanner = StateObject(wrappedValue: RoutePlanner(locationProvider: provider))
        _destinationSearch = StateObject(wrappedValue: DestinationSearchService(locationProvider: provider))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch speedProvider.authorizationStatus {
            case .denied, .restricted:
                permissionDeniedView
            default:
                HStack(spacing: 16) {
                    SpeedometerView(
                        speedKmh: speedBlender.speedKmh,
                        speedLimitKmh: speedLimitProvider.speedLimitKmh
                    )
                    .padding(.leading, 32)

                    MapPanelView(
                        routePlanner: routePlanner,
                        cameraPosition: $cameraPosition,
                        onTapSetStart: { isShowingStartSearch = true },
                        onTapSetDestination: { isShowingDestinationSearch = true }
                    )
                    .padding(.vertical, 16)

                    TimeView(driveTimer: driveTimer)
                        .padding(.trailing, 12)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            speedProvider.requestPermissionAndStart()
            speedBlender.start()
        }
        .onDisappear {
            speedBlender.stop()
        }
        .onReceive(routePlanner.$route.compactMap { $0 }) { route in
            let rect = route.polyline.boundingMapRect
            let padded = rect.insetBy(dx: -rect.width * 0.15, dy: -rect.height * 0.15)
            withAnimation {
                cameraPosition = .rect(padded)
            }
            driveTimer.intervalTargetSeconds = route.expectedTravelTime
        }
        .sheet(isPresented: $isShowingStartSearch) {
            LocationSearchSheet(
                searchService: destinationSearch,
                title: "Starting Point",
                onUseCurrentLocation: { routePlanner.setStartingPoint(nil) }
            ) { suggestion in
                destinationSearch.resolve(suggestion) { mapItem in
                    if let mapItem {
                        routePlanner.setStartingPoint(mapItem)
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingDestinationSearch) {
            LocationSearchSheet(searchService: destinationSearch, title: "Destination") { suggestion in
                destinationSearch.resolve(suggestion) { mapItem in
                    if let mapItem {
                        routePlanner.planRoute(to: mapItem)
                    }
                }
            }
        }
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 12) {
            Text("Location access is off")
                .font(.title2.bold())
                .foregroundColor(.white)
            Text("Enable location access in Settings to see your speed.")
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}

struct SpeedometerView: View {
    let speedKmh: Double
    let speedLimitKmh: Double?

    /// Green at or under the limit, sliding toward red as the amount over the limit
    /// grows, maxing out fully red at `maxOverKmh` over.
    private var speedColor: Color {
        guard let limit = speedLimitKmh, limit > 0 else { return .white }
        let over = max(speedKmh - limit, 0)
        let maxOverKmh = 20.0
        let t = min(over / maxOverKmh, 1.0)
        let greenHue = 0.34
        return Color(hue: greenHue * (1 - t), saturation: 0.85, brightness: 0.95)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(format: "%.0f", speedKmh))
                .font(.system(size: 140, weight: .bold, design: .rounded))
                .foregroundColor(speedColor)
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .animation(.easeInOut(duration: 0.4), value: speedColor)

            Text("km/h")
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .foregroundColor(.gray)
                .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 2) {
                Text("SPEED LIMIT")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.gray)
                Text(speedLimitKmh.map { String(format: "%.0f", $0) } ?? "--")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
            }
        }
    }
}

struct TimeView: View {
    @ObservedObject var driveTimer: DriveTimer

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(Self.format(driveTimer.elapsed))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Button(action: driveTimer.toggle) {
                Text(driveTimer.isRunning ? "STOP" : "START")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .frame(width: 110, height: 36)
                    .background(driveTimer.isRunning ? Color.red : Color.green)
                    .clipShape(Capsule())
            }
            .buttonStyle(InstantButtonStyle())
            .animation(nil, value: driveTimer.isRunning)
            .padding(.top, 6)
            .padding(.bottom, 16)

            VStack(alignment: .trailing, spacing: 2) {
                Text("INTERVAL")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.gray)
                Text(Self.formatSignedDelta(driveTimer.intervalDelta))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(driveTimer.intervalDelta <= 0 ? .green : .red)
                    .monospacedDigit()
            }
        }
    }

    /// mm:ss.xx (or h:mm:ss.xx once past an hour).
    private static func format(_ interval: TimeInterval) -> String {
        let clamped = max(interval, 0)
        let totalCentiseconds = Int((clamped * 100).rounded())
        let centiseconds = totalCentiseconds % 100
        let totalSeconds = totalCentiseconds / 100
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d.%02d", hours, minutes, seconds, centiseconds)
        }
        return String(format: "%02d:%02d.%02d", minutes, seconds, centiseconds)
    }

    /// Same format as `format(_:)`, prefixed with +/- based on sign.
    private static func formatSignedDelta(_ delta: TimeInterval) -> String {
        let sign = delta <= 0 ? "-" : "+"
        return sign + format(abs(delta))
    }
}

/// No default press animation/highlight — the label swaps instantly on tap.
private struct InstantButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

#Preview {
    ContentView()
}

import SwiftUI

struct ContentView: View {
    @StateObject private var speedProvider: LocationSpeedProvider
    @StateObject private var speedBlender: SpeedBlender
    @StateObject private var speedLimitProvider: SpeedLimitProvider
    @StateObject private var driveTimer = DriveTimer()

    init() {
        let provider = LocationSpeedProvider()
        _speedProvider = StateObject(wrappedValue: provider)
        _speedBlender = StateObject(wrappedValue: SpeedBlender(locationProvider: provider))
        _speedLimitProvider = StateObject(wrappedValue: SpeedLimitProvider(locationProvider: provider))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch speedProvider.authorizationStatus {
            case .denied, .restricted:
                permissionDeniedView
            default:
                HStack(spacing: 0) {
                    SpeedometerView(
                        speedKmh: speedBlender.speedKmh,
                        speedLimitKmh: speedLimitProvider.speedLimitKmh
                    )
                    .padding(.leading, 32)

                    Spacer(minLength: 0)

                    TimeView(driveTimer: driveTimer)
                        .padding(.trailing, 32)
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
                .font(.system(size: 80, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Button(action: driveTimer.toggle) {
                Text(driveTimer.isRunning ? "STOP" : "START")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .frame(width: 140, height: 44)
                    .background(driveTimer.isRunning ? Color.red : Color.green)
                    .clipShape(Capsule())
            }
            .padding(.top, 8)
            .padding(.bottom, 24)

            VStack(alignment: .trailing, spacing: 2) {
                Text("INTERVAL \(driveTimer.intervalNumber)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.gray)
                Text(Self.format(driveTimer.intervalElapsed))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
            }
        }
    }

    private static func format(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    ContentView()
}

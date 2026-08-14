import SwiftUI

struct ContentView: View {
    @StateObject private var speedProvider: LocationSpeedProvider
    @StateObject private var speedBlender: SpeedBlender

    init() {
        let provider = LocationSpeedProvider()
        _speedProvider = StateObject(wrappedValue: provider)
        _speedBlender = StateObject(wrappedValue: SpeedBlender(locationProvider: provider))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch speedProvider.authorizationStatus {
            case .denied, .restricted:
                permissionDeniedView
            default:
                SpeedometerView(speedKmh: speedBlender.speedKmh)
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

    var body: some View {
        VStack(spacing: 8) {
            Text(String(format: "%.0f", speedKmh))
                .font(.system(size: 160, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Text("km/h")
                .font(.system(size: 28, weight: .medium, design: .rounded))
                .foregroundColor(.gray)
        }
    }
}

#Preview {
    ContentView()
}

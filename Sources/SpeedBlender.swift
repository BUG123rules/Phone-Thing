import CoreMotion
import Combine

/// Makes the speed display feel as responsive as the accelerometer (up to 60 Hz)
/// while never actually trusting the accelerometer for the absolute number.
///
/// Integrating accelerometer data directly into a speed value drifts hard within
/// seconds — there's no way for it to self-correct. So instead, GPS speed (from
/// `LocationSpeedProvider`) stays the only source of truth for *what* the speed is.
/// The accelerometer only controls *how fast the display catches up* to that truth:
/// when it senses strong acceleration/braking, the displayed number snaps toward the
/// latest GPS value almost immediately; when the car is steady, it settles gently and
/// smooths out GPS jitter. Every tick converges back toward the real GPS speed, so it
/// can never wander off into a wrong reading.
final class SpeedBlender: ObservableObject {
    @Published private(set) var speedKmh: Double = 0

    private let motionManager = CMMotionManager()
    private var cancellable: AnyCancellable?
    private var targetSpeedKmh: Double = 0

    // Tuning constants for the catch-up rate per 60 Hz tick.
    private let baseAlpha = 0.06      // gentle pull toward target while steady (smooths GPS jitter)
    private let alphaPerMs2 = 0.35    // extra pull per m/s^2 of sensed horizontal acceleration
    private let maxAlpha = 0.9        // cap so it never fully snaps in a single tick

    init(locationProvider: LocationSpeedProvider) {
        cancellable = locationProvider.$speedKmh
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newSpeed in
                self?.targetSpeedKmh = newSpeed
            }
    }

    func start() {
        guard motionManager.isDeviceMotionAvailable else {
            // No accelerometer available: just mirror GPS speed directly on each fix.
            cancellable = nil
            return
        }

        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }

            let horizontalGs = (motion.userAcceleration.x * motion.userAcceleration.x
                + motion.userAcceleration.y * motion.userAcceleration.y).squareRoot()
            let horizontalMetersPerSecondSquared = horizontalGs * 9.80665

            let alpha = min(self.baseAlpha + self.alphaPerMs2 * horizontalMetersPerSecondSquared, self.maxAlpha)
            self.speedKmh += (self.targetSpeedKmh - self.speedKmh) * alpha
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }
}

import Foundation

/// Tracks elapsed drive time via a manual start/stop toggle. Arrival won't auto-stop
/// this until routing/ETA exists, so for now it's a plain stopwatch.
///
/// Also derives an interval delta — actual elapsed time minus a target — as a
/// placeholder for the eventual ETA-based sector splits. There's no route yet to
/// compute real per-sector targets from, so every interval is compared against a
/// flat 1:00.00 for now.
final class DriveTimer: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var elapsed: TimeInterval = 0

    private var runStartDate: Date?
    private var accumulatedBeforeCurrentRun: TimeInterval = 0
    private var ticker: Timer?

    let intervalTargetSeconds: TimeInterval = 60

    /// Negative = ahead of the placeholder target, positive = behind it.
    var intervalDelta: TimeInterval {
        elapsed - intervalTargetSeconds
    }

    func toggle() {
        isRunning ? stop() : start()
    }

    private func start() {
        guard !isRunning else { return }
        isRunning = true
        runStartDate = Date()
        ticker = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func stop() {
        guard isRunning else { return }
        tick()
        isRunning = false
        ticker?.invalidate()
        ticker = nil
        accumulatedBeforeCurrentRun = elapsed
        runStartDate = nil
    }

    private func tick() {
        guard let runStartDate else { return }
        elapsed = accumulatedBeforeCurrentRun + Date().timeIntervalSince(runStartDate)
    }

    deinit {
        ticker?.invalidate()
    }
}

import Foundation

/// Tracks elapsed drive time via a manual start/stop toggle. Arrival won't auto-stop
/// this until routing/ETA exists, so for now it's a plain stopwatch.
///
/// Also derives a rolling 1-minute interval clock as a placeholder for the eventual
/// ETA-based sector splits (there's no route yet to compute real sectors from).
final class DriveTimer: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var elapsed: TimeInterval = 0

    private var runStartDate: Date?
    private var accumulatedBeforeCurrentRun: TimeInterval = 0
    private var ticker: Timer?

    private let intervalLength: TimeInterval = 60

    var intervalElapsed: TimeInterval {
        elapsed.truncatingRemainder(dividingBy: intervalLength)
    }

    var intervalNumber: Int {
        Int(elapsed / intervalLength) + 1
    }

    func toggle() {
        isRunning ? stop() : start()
    }

    private func start() {
        guard !isRunning else { return }
        isRunning = true
        runStartDate = Date()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
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

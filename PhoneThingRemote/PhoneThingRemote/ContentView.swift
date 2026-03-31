import SwiftUI
import UIKit

struct ContentView: View {
    @AppStorage("serverHosts") private var storedHostsData = ""
    @AppStorage("serverHost") private var legacyServerHost = ""

    @StateObject private var sender = CommandSender()
    @State private var haptics = UISelectionFeedbackGenerator()
    @State private var lastHapticVolume = -1
    @State private var volumeSendTask: Task<Void, Never>?
    @State private var volumeCollapseTask: Task<Void, Never>?
    @State private var isVolumeExpanded = false
    @State private var isShowingSettings = false
    @State private var savedHosts: [SavedHost] = []

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                GeometryReader { geometry in
                    let horizontalPadding = max(24, geometry.size.width * 0.08)
                    let sideButtonSize = min(max(geometry.size.width * 0.14, 50), 62)
                    let sideSpacing = max(14, geometry.size.width * 0.035)
                    let coverSize = min(
                        max(geometry.size.width - (horizontalPadding * 2) - (sideButtonSize * 2) - (sideSpacing * 2), 140),
                        geometry.size.height * 0.35,
                        320
                    )

                    VStack(spacing: 0) {
                        topBar
                            .padding(.top, 14)

                        Spacer(minLength: 18)

                        artworkRow(size: coverSize, buttonSize: sideButtonSize, spacing: sideSpacing)

                        VStack(spacing: 10) {
                            Text(sender.trackTitle)
                                .font(.system(size: 28, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)

                            Text(sender.trackArtist)
                                .font(.system(size: 17, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.58))
                                .lineLimit(1)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 28)

                        progressSection(at: context.date)
                            .padding(.top, 26)

                        Spacer(minLength: 18)

                        statusFooter
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isShowingSettings) {
            ConnectionSettingsView(
                hosts: $savedHosts,
                activeHost: sender.activeHost,
                statusMessage: sender.statusMessage,
                onScan: {
                    await sender.scanForServers()
                }
            )
        }
        .task {
            savedHosts = initialHosts()
        }
        .task(id: savedHosts.map(\.address).joined(separator: "|")) {
            saveHosts(savedHosts)
            await sender.startListening(hosts: savedHosts.map(\.address))
        }
        .onAppear {
            haptics.prepare()
        }
        .onDisappear {
            sender.stopListening()
            volumeSendTask?.cancel()
            volumeCollapseTask?.cancel()
        }
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: 12) {
            expandingVolumeBar
            Spacer(minLength: 0)

            Button {
                isShowingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var expandingVolumeBar: some View {
        let width = isVolumeExpanded ? 230.0 : 112.0
        let height = isVolumeExpanded ? 44.0 : 30.0

        return HStack(spacing: isVolumeExpanded ? 10 : 8) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: isVolumeExpanded ? 15 : 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.10))

                    Capsule()
                        .fill(Color.white)
                        .frame(width: max((sender.volumePercent / 100.0) * proxy.size.width, 8))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let percent = min(max(value.location.x / proxy.size.width, 0), 1) * 100
                            updateVolume(to: percent)
                            expandVolumeBar()
                        }
                        .onEnded { _ in
                            scheduleVolumeCollapse()
                        }
                )
            }
            .frame(height: isVolumeExpanded ? 16 : 10)

            if isVolumeExpanded {
                Text("\(Int(sender.volumePercent.rounded()))")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.68))
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, isVolumeExpanded ? 14 : 12)
        .frame(width: width, height: height)
        .background(Color.white.opacity(0.045))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: isVolumeExpanded)
    }

    private func artworkRow(size: CGFloat, buttonSize: CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            transportButton(icon: "backward.fill", size: buttonSize) {
                await sender.send(command: .previousTrack)
            }

            coverArt(size: size)

            transportButton(icon: "forward.fill", size: buttonSize) {
                await sender.send(command: .nextTrack)
            }
        }
    }

    private func coverArt(size: CGFloat) -> some View {
        Button {
            Task {
                await sender.send(command: .playPause)
            }
        } label: {
            ZStack {
                Group {
                    if let image = sender.artworkImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        placeholderCover
                    }
                }

                if !sender.isPlaying {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.58))
                            .frame(width: size * 0.26, height: size * 0.26)

                        Image(systemName: "pause.fill")
                            .font(.system(size: size * 0.09, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .buttonStyle(.plain)
    }

    private var placeholderCover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.045))

            Image(systemName: "music.note")
                .font(.system(size: 56, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.24))
        }
    }

    private func progressSection(at now: Date) -> some View {
        let duration = sender.durationSeconds
        let currentPosition = sender.currentPosition(at: now)
        let fraction = duration > 0 ? min(max(currentPosition / duration, 0), 1) : 0

        return VStack(spacing: 10) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 4)

                    Capsule()
                        .fill(Color.white)
                        .frame(width: max(proxy.size.width * fraction, fraction > 0 ? 8 : 0), height: 4)
                }
            }
            .frame(height: 4)

            HStack {
                Text(formatTime(currentPosition))
                Spacer()
                Text(formatTime(duration))
            }
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.46))
        }
    }

    private var statusFooter: some View {
        HStack {
            if sender.activeHost.isEmpty {
                Text(sender.statusMessage)
            } else {
                Text("\(sender.activeHost)  |  \(sender.statusMessage)")
            }

            Spacer()

            Text(AppVersion.current)
        }
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .foregroundStyle(Color.white.opacity(0.28))
    }

    private func transportButton(icon: String, size: CGFloat, action: @escaping () async -> Void) -> some View {
        Button {
            Task {
                await action()
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: size * 0.32, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Color.white.opacity(0.07))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func updateVolume(to proposedValue: Double) {
        let clampedValue = min(max(proposedValue, 0), 100)
        let roundedValue = Int(clampedValue.rounded())

        sender.volumePercent = Double(roundedValue)

        if roundedValue != lastHapticVolume {
            lastHapticVolume = roundedValue
            haptics.selectionChanged()
            haptics.prepare()
        }

        volumeSendTask?.cancel()
        volumeSendTask = Task {
            await sender.send(command: .setVolume, value: roundedValue)
        }
    }

    private func expandVolumeBar() {
        if !isVolumeExpanded {
            isVolumeExpanded = true
        }
    }

    private func scheduleVolumeCollapse() {
        volumeCollapseTask?.cancel()
        volumeCollapseTask = Task {
            try? await Task.sleep(nanoseconds: 1_300_000_000)

            if !Task.isCancelled {
                await MainActor.run {
                    isVolumeExpanded = false
                }
            }
        }
    }

    private func loadHosts() -> [SavedHost] {
        guard let data = storedHostsData.data(using: .utf8) else {
            return []
        }

        return (try? JSONDecoder().decode([SavedHost].self, from: data)) ?? []
    }

    private func saveHosts(_ hosts: [SavedHost]) {
        guard let data = try? JSONEncoder().encode(hosts), let json = String(data: data, encoding: .utf8) else {
            return
        }

        storedHostsData = json
    }

    private func initialHosts() -> [SavedHost] {
        let decodedHosts = loadHosts()
        guard decodedHosts.isEmpty else {
            return decodedHosts
        }

        let trimmedLegacyHost = legacyServerHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLegacyHost.isEmpty else {
            return []
        }

        let migratedHosts = [SavedHost(address: trimmedLegacyHost)]
        legacyServerHost = ""
        saveHosts(migratedHosts)
        return migratedHosts
    }

    private func formatTime(_ value: Double) -> String {
        let totalSeconds = max(Int(value.rounded(.down)), 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
        }

        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}

#Preview {
    ContentView()
}

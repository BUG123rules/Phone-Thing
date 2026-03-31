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
                    ZStack(alignment: .topLeading) {
                        elementFrame("volumeBar", in: geometry.size).map { rect in
                            AnyView(volumeBar(baseRect: rect))
                        }

                        elementFrame("settingsButton", in: geometry.size).map { rect in
                            AnyView(settingsButton(in: rect))
                        }

                        elementFrame("previousButton", in: geometry.size).map { rect in
                            AnyView(skipButton(icon: "backward.fill", command: .previousTrack, in: rect))
                        }

                        elementFrame("albumArt", in: geometry.size).map { rect in
                            AnyView(coverArt(in: rect))
                        }

                        elementFrame("nextButton", in: geometry.size).map { rect in
                            AnyView(skipButton(icon: "forward.fill", command: .nextTrack, in: rect))
                        }

                        elementFrame("title", in: geometry.size).map { rect in
                            AnyView(titleView(in: rect))
                        }

                        elementFrame("artist", in: geometry.size).map { rect in
                            AnyView(artistView(in: rect))
                        }

                        elementFrame("progressBar", in: geometry.size).map { rect in
                            AnyView(progressSection(at: context.date, in: rect))
                        }

                        elementFrame("statusFooter", in: geometry.size).map { rect in
                            AnyView(statusFooter(in: rect))
                        }
                    }
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
        .task(id: savedHosts.map { $0.address }.joined(separator: "|")) {
            saveHosts(savedHosts)
            await sender.startListening(hosts: savedHosts.map { $0.address })
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

    private func coverArt(in rect: CGRect) -> some View {
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
                            .frame(width: rect.width * 0.26, height: rect.width * 0.26)

                        Image(systemName: "pause.fill")
                            .font(.system(size: rect.width * 0.09, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .frame(width: rect.width, height: rect.height)
        .clipShape(RoundedRectangle(cornerRadius: min(rect.width, rect.height) * 0.10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: min(rect.width, rect.height) * 0.10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .buttonStyle(.plain)
        .position(x: rect.midX, y: rect.midY)
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

    private func skipButton(icon: String, command: RemoteCommand, in rect: CGRect) -> some View {
        let size = min(rect.width, rect.height)

        return Button {
            Task {
                await sender.send(command: command)
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: size * 0.34, weight: .semibold))
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
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
    }

    private func titleView(in rect: CGRect) -> some View {
        Text(sender.trackTitle)
            .font(.system(size: min(rect.height * 0.48, 34), weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }

    private func artistView(in rect: CGRect) -> some View {
        Text(sender.trackArtist)
            .font(.system(size: min(rect.height * 0.52, 20), weight: .medium, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.58))
            .lineLimit(1)
            .multilineTextAlignment(.center)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }

    private func progressSection(at now: Date, in rect: CGRect) -> some View {
        let duration = sender.durationSeconds
        let currentPosition = sender.currentPosition(at: now)
        let fraction = duration > 0 ? min(max(currentPosition / duration, 0), 1) : 0

        return VStack(spacing: max(rect.height * 0.16, 8)) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: max(rect.height * 0.12, 4))

                    Capsule()
                        .fill(Color.white)
                        .frame(width: max(proxy.size.width * fraction, fraction > 0 ? 8 : 0), height: max(rect.height * 0.12, 4))
                }
            }
            .frame(height: max(rect.height * 0.18, 6))

            HStack {
                Text(formatTime(currentPosition))
                Spacer()
                Text(formatTime(duration))
            }
            .font(.system(size: min(rect.height * 0.24, 14), weight: .medium, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.46))
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
    }

    private func volumeBar(baseRect: CGRect) -> some View {
        let expandedWidth = isVolumeExpanded ? max(baseRect.width * 1.9, 180) : baseRect.width
        let expandedHeight = isVolumeExpanded ? max(baseRect.height * 1.35, 34) : max(baseRect.height, 24)
        let displayRect = CGRect(x: baseRect.minX, y: baseRect.minY, width: expandedWidth, height: expandedHeight)

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
            .frame(height: isVolumeExpanded ? max(displayRect.height * 0.34, 14) : max(displayRect.height * 0.22, 8))

            if isVolumeExpanded {
                Text("\(Int(sender.volumePercent.rounded()))")
                    .font(.system(size: min(displayRect.height * 0.34, 12), weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.68))
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, isVolumeExpanded ? 14 : 12)
        .frame(width: displayRect.width, height: displayRect.height, alignment: .leading)
        .background(Color.white.opacity(0.045))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: isVolumeExpanded)
        .position(x: displayRect.midX, y: displayRect.midY)
    }

    private func settingsButton(in rect: CGRect) -> some View {
        let size = min(rect.width, rect.height)

        return Button {
            isShowingSettings = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Color.white.opacity(0.06))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
    }

    private func statusFooter(in rect: CGRect) -> some View {
        HStack {
            if sender.activeHost.isEmpty {
                Text(sender.statusMessage)
            } else {
                Text("\(sender.activeHost)  |  \(sender.statusMessage)")
            }

            Spacer()

            Text(AppVersion.current)
        }
        .font(.system(size: min(rect.height * 0.58, 11), weight: .medium, design: .rounded))
        .foregroundStyle(Color.white.opacity(0.28))
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
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

    private func elementFrame(_ key: String, in size: CGSize) -> CGRect? {
        guard let element = sender.layout.element(for: key), element.isVisible else {
            return nil
        }

        return CGRect(
            x: size.width * element.x,
            y: size.height * element.y,
            width: size.width * element.width,
            height: size.height * element.height
        )
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

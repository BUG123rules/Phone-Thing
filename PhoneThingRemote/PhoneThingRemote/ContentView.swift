import SwiftUI

struct ContentView: View {
    @AppStorage("serverHost") private var serverHost = ""
    @StateObject private var sender = CommandSender()

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
                        geometry.size.height * 0.40,
                        320
                    )

                    VStack(spacing: 0) {
                        Spacer(minLength: 24)

                        artworkRow(size: coverSize, buttonSize: sideButtonSize, spacing: sideSpacing)

                        VStack(spacing: 10) {
                            Text(currentTitle)
                                .font(.system(size: 28, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)

                            Text(currentArtist)
                                .font(.system(size: 17, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.58))
                                .lineLimit(1)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 28)

                        progressSection(at: context.date)
                            .padding(.top, 24)

                        Spacer(minLength: 18)

                        connectionSection
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task(id: serverHost) {
            sender.stopPolling()
            await sender.startPolling(host: serverHost)
        }
    }

    private func artworkRow(size: CGFloat, buttonSize: CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            transportButton(icon: "backward.fill", size: buttonSize) {
                await sender.send(command: .previousTrack, to: serverHost)
            }

            coverArt(size: size)

            transportButton(icon: "forward.fill", size: buttonSize) {
                await sender.send(command: .nextTrack, to: serverHost)
            }
        }
    }

    private func coverArt(size: CGFloat) -> some View {
        Button {
            Task {
                await sender.send(command: .playPause, to: serverHost)
            }
        } label: {
            Group {
                if let url = sender.artworkURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure(_):
                            placeholderCover
                        case .empty:
                            placeholderCover
                        @unknown default:
                            placeholderCover
                        }
                    }
                } else {
                    placeholderCover
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
        let fraction = progressFraction(at: now)

        VStack(spacing: 10) {
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
                Text(formattedElapsed(at: now))
                Spacer()
                Text(formattedRemaining(at: now))
            }
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.46))
        }
    }

    private var connectionSection: some View {
        VStack(spacing: 10) {
            TextField("PC IP", text: $serverHost)
                .textInputAutocapitalization(.never)
                .keyboardType(.decimalPad)
                .submitLabel(.done)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.72))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            HStack {
                Text(sender.statusMessage)
                Spacer()
                Text(AppVersion.current)
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.28))
        }
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

    private var currentTitle: String {
        guard let status = sender.nowPlaying, status.isAvailable else {
            return "Nothing Playing"
        }

        return status.title
    }

    private var currentArtist: String {
        guard let status = sender.nowPlaying, status.isAvailable else {
            return "Play media on your PC"
        }

        return status.artist.isEmpty ? "Unknown Artist" : status.artist
    }

    private func progressFraction(at now: Date) -> CGFloat {
        guard let status = sender.nowPlaying, status.durationSeconds > 0 else {
            return 0
        }

        return min(max(CGFloat(currentPositionSeconds(at: now) / status.durationSeconds), 0), 1)
    }

    private func formattedElapsed(at now: Date) -> String {
        formatTime(currentPositionSeconds(at: now))
    }

    private func formattedRemaining(at now: Date) -> String {
        let duration = sender.nowPlaying?.durationSeconds ?? 0
        let remaining = max(duration - currentPositionSeconds(at: now), 0)
        return "-\(formatTime(remaining))"
    }

    private func currentPositionSeconds(at now: Date) -> Double {
        guard let status = sender.nowPlaying else {
            return 0
        }

        if !status.isPlaying {
            return min(max(status.positionSeconds, 0), status.durationSeconds)
        }

        let elapsedSinceSync = now.timeIntervalSince1970 - (Double(status.syncUnixMilliseconds) / 1000.0)
        return min(max(status.positionSeconds + elapsedSinceSync, 0), status.durationSeconds)
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

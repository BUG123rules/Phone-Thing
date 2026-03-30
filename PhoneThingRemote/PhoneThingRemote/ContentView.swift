import SwiftUI

struct ContentView: View {
    @AppStorage("serverHost") private var serverHost = ""
    @StateObject private var sender = CommandSender()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                GeometryReader { geometry in
                    let horizontalPadding = max(24, geometry.size.width * 0.08)
                    let coverSize = min(geometry.size.width - (horizontalPadding * 2), geometry.size.height * 0.42, 360)

                    VStack(spacing: 0) {
                        Spacer(minLength: 24)

                        coverArt(size: coverSize)

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

                        progressSection
                            .padding(.top, 24)

                        controlsSection
                            .padding(.top, 34)

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

    private func coverArt(size: CGFloat) -> some View {
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
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
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

    private var progressSection: some View {
        VStack(spacing: 10) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 4)

                    Capsule()
                        .fill(Color.white)
                        .frame(width: max(proxy.size.width * progressFraction, progressFraction > 0 ? 8 : 0), height: 4)
                }
            }
            .frame(height: 4)

            HStack {
                Text(formattedElapsed)
                Spacer()
                Text(formattedRemaining)
            }
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.46))
        }
    }

    private var controlsSection: some View {
        HStack(spacing: 24) {
            transportButton(icon: "backward.fill", size: 58) {
                await sender.send(command: .previousTrack, to: serverHost)
            }

            transportButton(icon: playPauseIcon, size: 84, filled: true) {
                await sender.send(command: .playPause, to: serverHost)
            }

            transportButton(icon: "forward.fill", size: 58) {
                await sender.send(command: .nextTrack, to: serverHost)
            }
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

    private func transportButton(icon: String, size: CGFloat, filled: Bool = false, action: @escaping () async -> Void) -> some View {
        Button {
            Task {
                await action()
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: size * 0.32, weight: .semibold))
                .foregroundStyle(filled ? .black : .white)
                .frame(width: size, height: size)
                .background(filled ? Color.white : Color.white.opacity(0.07))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(filled ? 0.0 : 0.10), lineWidth: 1)
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

    private var playPauseIcon: String {
        guard let status = sender.nowPlaying else {
            return "play.fill"
        }

        return status.isPlaying ? "pause.fill" : "play.fill"
    }

    private var progressFraction: CGFloat {
        guard let status = sender.nowPlaying, status.durationSeconds > 0 else {
            return 0
        }

        return min(max(CGFloat(currentPositionSeconds / status.durationSeconds), 0), 1)
    }

    private var formattedElapsed: String {
        formatTime(currentPositionSeconds)
    }

    private var formattedRemaining: String {
        let duration = sender.nowPlaying?.durationSeconds ?? 0
        let remaining = max(duration - currentPositionSeconds, 0)
        return "-\(formatTime(remaining))"
    }

    private var currentPositionSeconds: Double {
        guard let status = sender.nowPlaying else {
            return 0
        }

        if !status.isPlaying {
            return min(max(status.positionSeconds, 0), status.durationSeconds)
        }

        let elapsedSinceSync = Date().timeIntervalSince1970 - (Double(status.syncUnixMilliseconds) / 1000.0)
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

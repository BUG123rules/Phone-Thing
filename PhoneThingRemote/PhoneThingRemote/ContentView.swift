import SwiftUI

struct ContentView: View {
    @AppStorage("serverHost") private var serverHost = ""
    @AppStorage("volumePercent") private var volumePercent = 50.0
    @StateObject private var sender = CommandSender()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                GeometryReader { geometry in
                    let coverSize = min(geometry.size.height * 0.62, geometry.size.width * 0.34, 300)

                    HStack(spacing: 28) {
                        Spacer(minLength: 0)

                        sideInfo
                            .frame(width: min(geometry.size.width * 0.22, 220))

                        coverArt(size: coverSize)

                        controlsPane
                            .frame(width: min(geometry.size.width * 0.32, 340))

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 20)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task(id: serverHost) {
            sender.stopPolling()
            await sender.startPolling(host: serverHost)
        }
    }

    private var sideInfo: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(currentTitle)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(3)

            Text(currentArtist)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.62))
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 5)

                    GeometryReader { proxy in
                        Capsule()
                            .fill(Color.white)
                            .frame(width: max(progressFraction, 0.015) * proxy.size.width, height: 5)
                    }
                }
                .frame(height: 5)

                Text("\(formattedElapsed)/\(formattedDuration)")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.54))
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                TextField("PC IP", text: $serverHost)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.72))

                Text(sender.statusMessage)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.30))
                    .lineLimit(2)

                Text(AppVersion.current)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.24))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var placeholderCover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.04))

            Image(systemName: "music.note")
                .font(.system(size: 56, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.28))
        }
    }

    private var controlsPane: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)

            transportButton(icon: "backward.fill", size: 78) {
                await sender.send(command: .previousTrack, to: serverHost)
            }

            transportButton(icon: "playpause.fill", size: 96) {
                await sender.send(command: .playPause, to: serverHost)
            }

            transportButton(icon: "forward.fill", size: 78) {
                await sender.send(command: .nextTrack, to: serverHost)
            }

            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "speaker.fill")
                        .foregroundStyle(Color.white.opacity(0.54))

                    Slider(value: $volumePercent, in: 0...100, step: 1)
                        .tint(.white)
                        .rotationEffect(.degrees(-90))
                        .frame(width: 140)

                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundStyle(Color.white.opacity(0.76))
                }
                .frame(height: 150)

                Button {
                    Task {
                        await sender.send(command: .setVolume, value: Int(volumePercent), to: serverHost)
                    }
                } label: {
                    Text("\(Int(volumePercent))%")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.white)
                        .clipShape(Capsule())
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }

    private func transportButton(icon: String, size: CGFloat, action: @escaping () async -> Void) -> some View {
        Button {
            Task {
                await action()
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: size * 0.34, weight: .bold))
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

    private var progressFraction: CGFloat {
        guard let status = sender.nowPlaying, status.durationSeconds > 0 else {
            return 0
        }

        return min(max(CGFloat(currentPositionSeconds / status.durationSeconds), 0), 1)
    }

    private var formattedElapsed: String {
        formatTime(currentPositionSeconds)
    }

    private var formattedDuration: String {
        formatTime(sender.nowPlaying?.durationSeconds ?? 0)
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

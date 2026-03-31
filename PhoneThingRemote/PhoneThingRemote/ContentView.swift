import SwiftUI
import UIKit

struct ContentView: View {
    @AppStorage("serverHost") private var serverHost = ""
    @StateObject private var sender = CommandSender()
    @State private var haptics = UISelectionFeedbackGenerator()
    @State private var lastHapticVolume = -1
    @State private var volumeSendTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                GeometryReader { geometry in
                    let horizontalPadding = max(24, geometry.size.width * 0.08)
                    let sideButtonSize = min(max(geometry.size.width * 0.14, 50), 62)
                    let sideSpacing = max(14, geometry.size.width * 0.035)
                    let coverSize = min(
                        max(geometry.size.width - (horizontalPadding * 2) - (sideButtonSize * 2) - (sideSpacing * 2), 140),
                        geometry.size.height * 0.38,
                        320
                    )

                    VStack(spacing: 0) {
                        Spacer(minLength: 42)

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

                        connectionSection
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            volumeBar
                .padding(.top, 18)
                .padding(.trailing, 16)
        }
        .preferredColorScheme(.dark)
        .task(id: serverHost) {
            await sender.startListening(host: serverHost)
        }
        .onAppear {
            haptics.prepare()
        }
        .onDisappear {
            sender.stopListening()
            volumeSendTask?.cancel()
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

    private var volumeBar: some View {
        GeometryReader { geometry in
            let barHeight = min(max(geometry.size.height * 0.22, 148), 188)
            let pillHeight = max(barHeight * CGFloat(sender.volumePercent / 100.0), 18)

            VStack(spacing: 12) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.82))

                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.08))

                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white)
                        .frame(height: pillHeight)
                }
                .frame(width: 38, height: barHeight)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let clampedY = min(max(value.location.y, 0), barHeight)
                            let percent = (1 - (clampedY / barHeight)) * 100
                            updateVolume(to: percent)
                        }
                )

                Text("\(Int(sender.volumePercent.rounded()))")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.44))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .frame(width: 72, height: 240)
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
            await sender.send(command: .setVolume, value: roundedValue, to: serverHost)
        }
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

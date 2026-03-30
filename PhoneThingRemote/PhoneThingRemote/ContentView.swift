import SwiftUI

struct ContentView: View {
    @AppStorage("serverHost") private var serverHost = ""
    @AppStorage("volumePercent") private var volumePercent = 50.0
    @StateObject private var sender = CommandSender()

    var body: some View {
        ZStack {
            backgroundView
                .ignoresSafeArea()

            GeometryReader { geometry in
                let artSize = min(max(geometry.size.height - 76, 220), 320)

                VStack(spacing: 18) {
                    headerBar

                    HStack(spacing: 22) {
                        albumPane(size: artSize)
                        controlPane
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 18)
            }
        }
        .preferredColorScheme(.dark)
        .task(id: serverHost) {
            await startPolling()
        }
    }

    private var backgroundView: some View {
        ZStack {
            Color.black

            LinearGradient(
                colors: [Color(red: 0.03, green: 0.03, blue: 0.04), Color(red: 0.09, green: 0.12, blue: 0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color(red: 0.15, green: 0.2, blue: 0.26).opacity(0.38))
                .frame(width: 420, height: 420)
                .blur(radius: 90)
                .offset(x: -220, y: -140)

            Circle()
                .fill(Color(red: 0.35, green: 0.53, blue: 0.68).opacity(0.22))
                .frame(width: 300, height: 300)
                .blur(radius: 100)
                .offset(x: 260, y: 140)
        }
    }

    private var headerBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("PhoneThing Remote")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(AppVersion.current)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.62))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }

                Text(sender.statusMessage)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 10) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(Color(red: 0.48, green: 0.83, blue: 1.0))

                TextField("PC IP", text: $serverHost)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(width: 180)

                Button("Ping") {
                    Task {
                        await sender.healthCheck(to: serverHost)
                    }
                }
                .buttonStyle(.bordered)
                .tint(Color.white.opacity(0.9))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func albumPane(size: CGFloat) -> some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.white.opacity(0.05))

                if let snapshot = sender.nowPlaying,
                   let image = albumImage(from: snapshot.albumArtDataUrl) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "music.note")
                            .font(.system(size: 56, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.5))
                        Text("No Artwork")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                }
            }
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )

            if let sourceAppId = sender.nowPlaying?.sourceAppId, !sourceAppId.isEmpty {
                Text(sourceAppId)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .lineLimit(1)
            }
        }
        .frame(width: size)
    }

    private var controlPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            metadataCard
            progressCard
            playbackControls
            volumeCard
            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(currentTitle)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)

            Text(currentArtist)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.72))
                .lineLimit(1)
        }
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.10))
                        .frame(height: 10)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.55, green: 0.85, blue: 1.0), Color(red: 0.29, green: 0.56, blue: 0.96)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(progressFraction, 0.02) * geometry.size.width, height: 10)
                }
            }
            .frame(height: 10)

            HStack {
                Text(currentElapsed)
                Spacer()
                Text(currentDuration)
            }
            .font(.system(size: 16, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.74))
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 16) {
            controlCapsule(systemImage: "backward.fill", title: "Prev") {
                await sender.send(command: .previousTrack, to: serverHost)
            }

            controlCapsule(systemImage: "playpause.fill", title: "Play") {
                await sender.send(command: .playPause, to: serverHost)
            }

            controlCapsule(systemImage: "forward.fill", title: "Next") {
                await sender.send(command: .nextTrack, to: serverHost)
            }
        }
    }

    private var volumeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Volume")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(Int(volumePercent))%")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.55, green: 0.85, blue: 1.0))
            }

            HStack(spacing: 14) {
                Image(systemName: "speaker.fill")
                    .foregroundStyle(Color.white.opacity(0.5))

                Slider(value: $volumePercent, in: 0...100, step: 1)
                    .tint(Color(red: 0.55, green: 0.85, blue: 1.0))

                Image(systemName: "speaker.wave.3.fill")
                    .foregroundStyle(Color.white.opacity(0.7))
            }

            Button {
                Task {
                    await sender.send(command: .setVolume, value: Int(volumePercent), to: serverHost)
                }
            } label: {
                HStack {
                    Image(systemName: "speaker.wave.2.circle.fill")
                    Text("Apply Volume")
                }
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(red: 0.55, green: 0.85, blue: 1.0))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var currentTitle: String {
        guard let snapshot = sender.nowPlaying, snapshot.isAvailable else {
            return "Waiting For Audio"
        }

        return snapshot.title
    }

    private var currentArtist: String {
        guard let snapshot = sender.nowPlaying, snapshot.isAvailable else {
            return "Play something on your PC to populate the remote."
        }

        return snapshot.artist.isEmpty ? "Unknown Artist" : snapshot.artist
    }

    private var currentElapsed: String {
        parseTimeline().elapsed
    }

    private var currentDuration: String {
        parseTimeline().duration
    }

    private var progressFraction: CGFloat {
        let timeline = parseTimeline()
        guard timeline.durationSeconds > 0 else {
            return 0
        }

        return min(max(CGFloat(timeline.elapsedSeconds / timeline.durationSeconds), 0), 1)
    }

    private func parseTimeline() -> (elapsed: String, duration: String, elapsedSeconds: Double, durationSeconds: Double) {
        guard let timeline = sender.nowPlaying?.timeline else {
            return ("0:00", "0:00", 0, 0)
        }

        let parts = timeline.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            return ("0:00", "0:00", 0, 0)
        }

        return (parts[0], parts[1], seconds(from: parts[0]), seconds(from: parts[1]))
    }

    private func seconds(from text: String) -> Double {
        let segments = text.split(separator: ":").compactMap { Double($0) }

        if segments.count == 3 {
            return segments[0] * 3600 + segments[1] * 60 + segments[2]
        }

        if segments.count == 2 {
            return segments[0] * 60 + segments[1]
        }

        return 0
    }

    private func startPolling() async {
        let trimmedHost = serverHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            return
        }

        await sender.fetchNowPlaying(from: trimmedHost, silent: true)

        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await sender.fetchNowPlaying(from: trimmedHost, silent: true)
        }
    }

    private func albumImage(from dataUrl: String) -> UIImage? {
        guard let commaIndex = dataUrl.firstIndex(of: ",") else {
            return nil
        }

        let base64 = String(dataUrl[dataUrl.index(after: commaIndex)...])
        guard let data = Data(base64Encoded: base64) else {
            return nil
        }

        return UIImage(data: data)
    }

    private func controlCapsule(systemImage: String, title: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task {
                await action()
            }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .bold))
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .disabled(sender.isSending)
    }
}

#Preview {
    ContentView()
}

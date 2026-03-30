import SwiftUI

struct ContentView: View {
    @AppStorage("serverHost") private var serverHost = ""
    @AppStorage("volumePercent") private var volumePercent = 50.0
    @StateObject private var sender = CommandSender()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.1, blue: 0.18), Color(red: 0.13, green: 0.2, blue: 0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("PhoneThing Remote")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("Simple media controls for your PC. This version just sends commands and lets the PC app show what arrived.")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.78))
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("PC Address")
                            .font(.headline)
                            .foregroundStyle(.white)

                        TextField("192.168.1.25", text: $serverHost)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.decimalPad)
                            .padding()
                            .background(Color.white.opacity(0.1))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                        Text("Use your PC's local Wi-Fi IP address shown in the desktop app.")
                            .font(.footnote)
                            .foregroundStyle(Color.white.opacity(0.68))
                    }

                    HStack(spacing: 14) {
                        controlButton(title: "Prev", systemImage: "backward.fill") {
                            await sender.send(command: .previousTrack, to: serverHost)
                        }

                        controlButton(title: "Play / Pause", systemImage: "playpause.fill") {
                            await sender.send(command: .playPause, to: serverHost)
                        }

                        controlButton(title: "Next", systemImage: "forward.fill") {
                            await sender.send(command: .nextTrack, to: serverHost)
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Volume")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Spacer()
                            Text("\(Int(volumePercent))%")
                                .font(.headline)
                                .foregroundStyle(Color.white.opacity(0.78))
                        }

                        Slider(value: $volumePercent, in: 0...100, step: 1) {
                            Text("Volume")
                        } minimumValueLabel: {
                            Image(systemName: "speaker.fill")
                                .foregroundStyle(Color.white.opacity(0.68))
                        } maximumValueLabel: {
                            Image(systemName: "speaker.wave.3.fill")
                                .foregroundStyle(Color.white.opacity(0.68))
                        }
                        .tint(Color(red: 0.49, green: 0.8, blue: 1.0))

                        Button {
                            Task {
                                await sender.send(command: .setVolume, value: Int(volumePercent), to: serverHost)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "slider.horizontal.3")
                                Text("Send Volume")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.49, green: 0.8, blue: 1.0))
                    }
                    .padding(20)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                    Text(sender.statusMessage)
                        .font(.callout)
                        .foregroundStyle(Color.white.opacity(0.84))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .padding(24)
            }
        }
    }

    private func controlButton(title: String, systemImage: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task {
                await action()
            }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .bold))
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(Color.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .disabled(sender.isSending)
    }
}

#Preview {
    ContentView()
}

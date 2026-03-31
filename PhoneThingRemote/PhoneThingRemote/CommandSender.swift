import Foundation
import UIKit

enum RemoteCommand: String {
    case previousTrack
    case playPause
    case nextTrack
    case setVolume
}

struct CommandPayload: Encodable {
    let command: String
    let value: Int?
}

private struct RemoteEventPacket: Decodable {
    let type: String
    let title: String?
    let artist: String?
    let artworkBase64: String?
    let artworkContentType: String?
    let changedAtUnixMilliseconds: Int64?
    let totalRuntimeSeconds: Double?
    let isPlaying: Bool?
    let positionSeconds: Double?
    let volumePercent: Int?
}

@MainActor
final class CommandSender: ObservableObject {
    @Published var statusMessage: String = "Ready"
    @Published var trackTitle: String = "Nothing Playing"
    @Published var trackArtist: String = "Play media on your PC"
    @Published var artworkImage: UIImage?
    @Published var isPlaying: Bool = false
    @Published var durationSeconds: Double = 0
    @Published var volumePercent: Double = 50

    private var progressAnchorSeconds: Double = 0
    private var progressAnchorDate: Date = .now
    private var listeningTask: Task<Void, Never>?
    private var reconnectDelayNanoseconds: UInt64 = 750_000_000

    func send(command: RemoteCommand, value: Int? = nil, to host: String) async {
        guard let url = commandURL(from: host) else {
            statusMessage = "Enter your PC IP."
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 2

        do {
            request.httpBody = try JSONEncoder().encode(CommandPayload(command: command.rawValue, value: value))
            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                statusMessage = "Connected"
            } else {
                statusMessage = "PC command failed"
            }
        } catch {
            statusMessage = "Connection failed"
        }
    }

    func startListening(host: String) async {
        stopListening()

        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            statusMessage = "Enter your PC IP."
            return
        }

        let reconnectDelayNanoseconds = reconnectDelayNanoseconds
        listeningTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                do {
                    try await self.listenToEvents(host: trimmedHost)
                } catch {
                    await MainActor.run {
                        self.statusMessage = "Reconnecting..."
                    }
                }

                if Task.isCancelled {
                    break
                }

                try? await Task.sleep(nanoseconds: reconnectDelayNanoseconds)
            }
        }
    }

    func stopListening() {
        listeningTask?.cancel()
        listeningTask = nil
    }

    func currentPosition(at now: Date) -> Double {
        if !isPlaying {
            return min(max(progressAnchorSeconds, 0), durationSeconds)
        }

        let elapsed = now.timeIntervalSince(progressAnchorDate)
        return min(max(progressAnchorSeconds + elapsed, 0), durationSeconds)
    }

    private func listenToEvents(host: String) async throws {
        guard let url = eventsURL(from: host) else {
            await MainActor.run {
                statusMessage = "Enter your PC IP."
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 60 * 60 * 24
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        await MainActor.run {
            statusMessage = "Connected"
        }

        for try await line in bytes.lines {
            if Task.isCancelled {
                break
            }

            guard line.hasPrefix("data: ") else {
                continue
            }

            let payload = String(line.dropFirst(6))
            guard let data = payload.data(using: .utf8) else {
                continue
            }

            let packet = try JSONDecoder().decode(RemoteEventPacket.self, from: data)
            await MainActor.run {
                self.apply(packet: packet)
            }
        }
    }

    private func apply(packet: RemoteEventPacket) {
        switch packet.type {
        case "songChanged":
            applySongChanged(packet)
        case "playbackChanged":
            applyPlaybackChanged(packet)
        case "volumeChanged":
            if let volume = packet.volumePercent {
                volumePercent = Double(volume)
            }
        default:
            break
        }
    }

    private func applySongChanged(_ packet: RemoteEventPacket) {
        if let title = packet.title, !title.isEmpty {
            trackTitle = title
        } else {
            trackTitle = "Nothing Playing"
        }

        if let artist = packet.artist, !artist.isEmpty {
            trackArtist = artist
        } else {
            trackArtist = "Play media on your PC"
        }
        durationSeconds = max(packet.totalRuntimeSeconds ?? 0, 0)
        isPlaying = packet.isPlaying ?? false

        if
            let base64 = packet.artworkBase64,
            !base64.isEmpty,
            let data = Data(base64Encoded: base64),
            let image = UIImage(data: data)
        {
            artworkImage = image
        } else {
            artworkImage = nil
        }

        let changedAt = packet.changedAtUnixMilliseconds.map {
            Date(timeIntervalSince1970: Double($0) / 1000.0)
        } ?? .now

        let positionFromClock = max(Date().timeIntervalSince(changedAt), 0)
        let packetPosition = max(packet.positionSeconds ?? 0, 0)
        let resolvedPosition = isPlaying ? max(positionFromClock, packetPosition) : packetPosition
        syncProgress(isPlaying: isPlaying, positionSeconds: resolvedPosition, changedAt: .now)
    }

    private func applyPlaybackChanged(_ packet: RemoteEventPacket) {
        let playing = packet.isPlaying ?? false
        let position = max(packet.positionSeconds ?? 0, 0)
        let changedAt = packet.changedAtUnixMilliseconds.map {
            Date(timeIntervalSince1970: Double($0) / 1000.0)
        } ?? .now

        syncProgress(isPlaying: playing, positionSeconds: position, changedAt: changedAt)
    }

    private func syncProgress(isPlaying: Bool, positionSeconds: Double, changedAt: Date) {
        let now = Date()
        let resolvedPosition = isPlaying
            ? positionSeconds + max(now.timeIntervalSince(changedAt), 0)
            : positionSeconds

        self.isPlaying = isPlaying
        progressAnchorSeconds = min(max(resolvedPosition, 0), durationSeconds)
        progressAnchorDate = now
    }

    private func commandURL(from input: String) -> URL? {
        normalizedBaseURL(from: input)?.appendingPathComponent("api/commands")
    }

    private func eventsURL(from input: String) -> URL? {
        normalizedBaseURL(from: input)?.appendingPathComponent("api/events")
    }

    private func normalizedBaseURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return nil
        }

        if let explicitURL = URL(string: trimmed), explicitURL.scheme != nil {
            guard var components = URLComponents(url: explicitURL, resolvingAgainstBaseURL: false) else {
                return nil
            }

            components.scheme = components.scheme ?? "http"
            components.port = components.port ?? 5050
            components.path = ""
            return components.url
        }

        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":", maxSplits: 1).map(String.init)
            guard let host = parts.first, !host.isEmpty else {
                return nil
            }

            var components = URLComponents()
            components.scheme = "http"
            components.host = host
            components.port = (parts.count > 1 ? Int(parts[1]) : nil) ?? 5050
            return components.url
        }

        var components = URLComponents()
        components.scheme = "http"
        components.host = trimmed
        components.port = 5050
        return components.url
    }
}

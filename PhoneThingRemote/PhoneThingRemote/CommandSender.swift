import Foundation

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

struct NowPlayingStatus: Decodable, Equatable {
    let isAvailable: Bool
    let title: String
    let artist: String
    let sourceAppId: String
    let isPlaying: Bool
    let positionSeconds: Double
    let durationSeconds: Double
    let syncUnixMilliseconds: Int64
    let artworkRevision: String
}

@MainActor
final class CommandSender: ObservableObject {
    @Published var statusMessage: String = "Ready"
    @Published var nowPlaying: NowPlayingStatus?
    @Published var artworkURL: URL?

    private var isPolling = false

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
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                statusMessage = "Connected"
                await refreshStatus(from: host, silent: true)
            } else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                let body = String(data: data, encoding: .utf8) ?? "No response body"
                statusMessage = "PC error \(code): \(body)"
            }
        } catch {
            statusMessage = "Connection failed"
        }
    }

    func startPolling(host: String) async {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            return
        }

        isPolling = true
        await refreshStatus(from: trimmedHost, silent: true)

        while isPolling && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 500_000_000)
            await refreshStatus(from: trimmedHost, silent: true)
        }
    }

    func stopPolling() {
        isPolling = false
    }

    private func refreshStatus(from host: String, silent: Bool) async {
        guard let url = statusURL(from: host) else {
            if !silent {
                statusMessage = "Enter your PC IP."
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 1.5

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                if !silent {
                    statusMessage = "Status update failed"
                }
                return
            }

            let status = try JSONDecoder().decode(NowPlayingStatus.self, from: data)
            let previousRevision = nowPlaying?.artworkRevision ?? ""
            nowPlaying = status

            if status.artworkRevision != previousRevision {
                artworkURL = artworkURL(from: host, revision: status.artworkRevision)
            }

            if !silent {
                statusMessage = "Connected"
            }
        } catch {
            if !silent {
                statusMessage = "Status update failed"
            }
        }
    }

    private func commandURL(from input: String) -> URL? {
        normalizedBaseURL(from: input)?.appendingPathComponent("api/commands")
    }

    private func statusURL(from input: String) -> URL? {
        normalizedBaseURL(from: input)?.appendingPathComponent("api/now-playing/status")
    }

    private func artworkURL(from input: String, revision: String) -> URL? {
        guard !revision.isEmpty else {
            return nil
        }

        return normalizedBaseURL(from: input)?
            .appendingPathComponent("api")
            .appendingPathComponent("now-playing")
            .appendingPathComponent("artwork")
            .appendingPathComponent(revision)
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

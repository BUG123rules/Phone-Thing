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

@MainActor
final class CommandSender: ObservableObject {
    @Published var statusMessage: String = "Ready to send commands."
    @Published var isSending = false

    func send(command: RemoteCommand, value: Int? = nil, to host: String) async {
        guard let url = commandURL(from: host) else {
            statusMessage = "Enter your PC's IP address first."
            return
        }

        isSending = true
        defer { isSending = false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 5

        do {
            request.httpBody = try JSONEncoder().encode(CommandPayload(command: command.rawValue, value: value))
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                statusMessage = "Sent \(label(for: command, value: value))."
            } else {
                let body = String(data: data, encoding: .utf8) ?? "No response body"
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                statusMessage = "PC error \(code): \(body)"
            }
        } catch {
            statusMessage = "Couldn't reach the PC app. Check the IP, Wi-Fi, and firewall."
        }
    }

    func healthCheck(to host: String) async {
        guard let url = healthURL(from: host) else {
            statusMessage = "Enter a valid IP or URL first."
            return
        }

        isSending = true
        defer { isSending = false }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? "No response body"
            statusMessage = "Health \(code): \(body)"
        } catch {
            statusMessage = "Health check failed: \(error.localizedDescription)"
        }
    }

    func label(for command: RemoteCommand, value: Int?) -> String {
        switch command {
        case .previousTrack:
            return "Previous Track"
        case .playPause:
            return "Play / Pause"
        case .nextTrack:
            return "Next Track"
        case .setVolume:
            return "Volume \(value ?? 0)%"
        }
    }

    private func commandURL(from input: String) -> URL? {
        normalizedBaseURL(from: input)?.appendingPathComponent("api/commands")
    }

    private func healthURL(from input: String) -> URL? {
        normalizedBaseURL(from: input)?.appendingPathComponent("api/health")
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
            if parts.count > 1, let port = Int(parts[1]) {
                components.port = port
            } else {
                components.port = 5050
            }
            return components.url
        }

        var components = URLComponents()
        components.scheme = "http"
        components.host = trimmed
        components.port = 5050
        return components.url
    }
}

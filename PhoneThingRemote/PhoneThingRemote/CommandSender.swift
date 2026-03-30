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
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedHost.isEmpty else {
            statusMessage = "Enter your PC's IP address first."
            return
        }

        guard let url = URL(string: "http://\(trimmedHost):5050/api/commands") else {
            statusMessage = "The server address looks invalid."
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
            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                statusMessage = "Sent \(label(for: command, value: value))."
            } else {
                statusMessage = "The PC app responded with an error."
            }
        } catch {
            statusMessage = "Couldn't reach the PC app. Check the IP, Wi-Fi, and firewall."
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
}

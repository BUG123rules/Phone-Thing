import Foundation
import UIKit
import Darwin

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
    let layout: PhoneLayout?
}

private struct HealthResponse: Decodable {
    let ok: Bool
    let port: Int
}

struct PhoneLayout: Decodable {
    let elements: [PhoneLayoutElement]

    static let `default` = PhoneLayout(elements: [
        PhoneLayoutElement(key: "volumeBar", x: 0.06, y: 0.05, width: 0.34, height: 0.04, isVisible: true),
        PhoneLayoutElement(key: "settingsButton", x: 0.87, y: 0.05, width: 0.09, height: 0.05, isVisible: true),
        PhoneLayoutElement(key: "previousButton", x: 0.08, y: 0.32, width: 0.12, height: 0.08, isVisible: true),
        PhoneLayoutElement(key: "albumArt", x: 0.24, y: 0.22, width: 0.52, height: 0.27, isVisible: true),
        PhoneLayoutElement(key: "nextButton", x: 0.80, y: 0.32, width: 0.12, height: 0.08, isVisible: true),
        PhoneLayoutElement(key: "title", x: 0.12, y: 0.55, width: 0.76, height: 0.07, isVisible: true),
        PhoneLayoutElement(key: "artist", x: 0.18, y: 0.62, width: 0.64, height: 0.04, isVisible: true),
        PhoneLayoutElement(key: "progressBar", x: 0.12, y: 0.71, width: 0.76, height: 0.06, isVisible: true),
        PhoneLayoutElement(key: "statusFooter", x: 0.08, y: 0.93, width: 0.84, height: 0.03, isVisible: true)
    ])

    func element(for key: String) -> PhoneLayoutElement? {
        elements.first { $0.key == key }
    }
}

struct PhoneLayoutElement: Decodable {
    let key: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let isVisible: Bool
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
    @Published var activeHost: String = ""
    @Published var layout: PhoneLayout = .default

    private var progressAnchorSeconds: Double = 0
    private var progressAnchorDate: Date = .now
    private var listeningTask: Task<Void, Never>?
    private let reconnectDelayNanoseconds: UInt64 = 900_000_000

    func send(command: RemoteCommand, value: Int? = nil, to host: String? = nil) async {
        let resolvedHost = (host ?? activeHost).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = commandURL(from: resolvedHost) else {
            statusMessage = "No connected PC"
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
                statusMessage = activeHost.isEmpty ? "Connected" : "Connected to \(activeHost)"
            } else {
                statusMessage = "PC command failed"
            }
        } catch {
            statusMessage = "Connection failed"
        }
    }

    func startListening(hosts: [String]) async {
        stopListening()

        let candidates = sanitizeHosts(hosts)
        guard !candidates.isEmpty else {
            activeHost = ""
            statusMessage = "Add a PC in Settings"
            return
        }

        let reconnectDelayNanoseconds = reconnectDelayNanoseconds
        listeningTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                guard let host = await HostDiscovery.firstReachableHost(in: candidates) else {
                    await MainActor.run {
                        self.activeHost = ""
                        self.statusMessage = "No saved PCs are reachable"
                    }

                    try? await Task.sleep(nanoseconds: reconnectDelayNanoseconds)
                    continue
                }

                await MainActor.run {
                    self.activeHost = host
                    self.statusMessage = "Connected to \(host)"
                }

                do {
                    try await self.listenToEvents(host: host)
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

    func scanForServers() async -> [String] {
        await HostDiscovery.scanForServers()
    }

    private func listenToEvents(host: String) async throws {
        guard let url = eventsURL(from: host) else {
            await MainActor.run {
                statusMessage = "No connected PC"
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
            self.statusMessage = "Connected to \(host)"
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
        case "layoutChanged":
            if let layout = packet.layout {
                self.layout = layout
            }
        default:
            break
        }
    }

    private func applySongChanged(_ packet: RemoteEventPacket) {
        trackTitle = (packet.title?.isEmpty == false ? packet.title : nil) ?? "Nothing Playing"
        trackArtist = (packet.artist?.isEmpty == false ? packet.artist : nil) ?? "Play media on your PC"
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

    private func sanitizeHosts(_ hosts: [String]) -> [String] {
        var seen = Set<String>()

        return hosts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0.lowercased()).inserted }
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

private enum HostDiscovery {
    static func firstReachableHost(in hosts: [String]) async -> String? {
        for host in hosts {
            if await isReachable(host: host) {
                return host
            }
        }

        return nil
    }

    static func scanForServers() async -> [String] {
        guard let subnetPrefix = localIPv4Address()?.split(separator: ".").dropLast().joined(separator: ".") else {
            return []
        }

        return await withTaskGroup(of: String?.self) { group in
            for suffix in 1...254 {
                let host = "\(subnetPrefix).\(suffix)"
                group.addTask {
                    await isReachable(host: host) ? host : nil
                }
            }

            var foundHosts: [String] = []
            for await host in group {
                if let host {
                    foundHosts.append(host)
                }
            }

            return foundHosts.sorted { lhs, rhs in
                let leftParts = lhs.split(separator: ".").compactMap { Int($0) }
                let rightParts = rhs.split(separator: ".").compactMap { Int($0) }
                return leftParts.lexicographicallyPrecedes(rightParts)
            }
        }
    }

    static func isReachable(host: String) async -> Bool {
        guard let url = normalizedBaseURL(from: host)?.appendingPathComponent("api/health") else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 0.45

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return false
            }

            let health = try JSONDecoder().decode(HealthResponse.self, from: data)
            return health.ok && health.port == 5050
        } catch {
            return false
        }
    }

    private static func normalizedBaseURL(from input: String) -> URL? {
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

    private static func localIPv4Address() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddress = ifaddr else {
            return nil
        }

        defer { freeifaddrs(ifaddr) }

        for pointer in sequence(first: firstAddress, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let addressPointer = interface.ifa_addr else {
                continue
            }

            let family = addressPointer.pointee.sa_family

            guard family == UInt8(AF_INET) else {
                continue
            }

            let name = String(cString: interface.ifa_name)
            guard name == "en0" || name == "en1" || name == "bridge100" else {
                continue
            }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                addressPointer,
                socklen_t(addressPointer.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                socklen_t(0),
                NI_NUMERICHOST
            )

            if result == 0 {
                address = String(cString: hostname)
                break
            }
        }

        return address
    }
}

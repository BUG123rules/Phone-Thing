import SwiftUI

struct SavedHost: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var address: String
}

struct ConnectionSettingsView: View {
    @Binding var hosts: [SavedHost]
    let activeHost: String
    let statusMessage: String
    let onScan: () async -> [String]

    @Environment(\.dismiss) private var dismiss
    @State private var newHost = ""
    @State private var isScanning = false
    @State private var scanMessage = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Connection") {
                    if activeHost.isEmpty {
                        Text(statusMessage)
                            .foregroundStyle(.secondary)
                    } else {
                        LabeledContent("Connected", value: activeHost)
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Saved PCs") {
                    if hosts.isEmpty {
                        Text("No PCs saved yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(hosts) { host in
                            Text(host.address)
                        }
                        .onDelete { offsets in
                            hosts.remove(atOffsets: offsets)
                        }
                        .onMove { source, destination in
                            hosts.move(fromOffsets: source, toOffset: destination)
                        }
                    }
                }

                Section("Add PC") {
                    TextField("192.168.1.20", text: $newHost)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)

                    Button("Add Address") {
                        addHost(newHost)
                    }
                    .disabled(newHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("Network Scan") {
                    Button(isScanning ? "Scanning..." : "Scan for PhoneThing PCs") {
                        Task {
                            await scan()
                        }
                    }
                    .disabled(isScanning)

                    if !scanMessage.isEmpty {
                        Text(scanMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func addHost(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        guard !hosts.contains(where: { $0.address.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            newHost = ""
            return
        }

        hosts.append(SavedHost(address: trimmed))
        newHost = ""
    }

    private func scan() async {
        isScanning = true
        scanMessage = ""

        let discoveredHosts = await onScan()

        for host in discoveredHosts where !hosts.contains(where: { $0.address.caseInsensitiveCompare(host) == .orderedSame }) {
            hosts.append(SavedHost(address: host))
        }

        if discoveredHosts.isEmpty {
            scanMessage = "No PhoneThing PCs were found on this network."
        } else {
            scanMessage = "Found \(discoveredHosts.count) PhoneThing PC\(discoveredHosts.count == 1 ? "" : "s")."
        }

        isScanning = false
    }
}

import SwiftUI
import Network
import UIKit

struct ContentView: View {
    @State private var engine = SpikeEngine()
    @State private var roomLabel = "spike"
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Group {
                switch engine.role {
                case nil:
                    homeView
                case .host:
                    HostView(engine: engine)
                case .join:
                    JoinView(engine: engine)
                }
            }
            .navigationTitle("Connectivity Spike")
        }
        .onChange(of: scenePhase) { _, phase in
            engine.addLog("App lifecycle: \(String(describing: phase))")
        }
    }

    private var homeView: some View {
        Form {
            Section("Your name") {
                TextField("Nickname", text: $engine.nickname)
            }
            Section("Room") {
                TextField("Room label", text: $roomLabel)
            }
            Section {
                Button("Host a room") {
                    engine.startHosting(label: roomLabel)
                }
                Button("Join a room") {
                    engine.startBrowsing()
                }
            }
            Section("Log") {
                LogView(entries: engine.log)
            }
        }
    }
}

private struct HostView: View {
    @Bindable var engine: SpikeEngine
    @State private var message = ""

    var body: some View {
        Form {
            Section("Waiting to be admitted") {
                if engine.pendingRequests.isEmpty {
                    Text("No one waiting.").foregroundStyle(.secondary)
                }
                ForEach(engine.pendingRequests) { peer in
                    HStack {
                        Text(peer.nickname)
                        Spacer()
                        Button("Admit") { engine.admit(peer) }
                            .buttonStyle(.borderedProminent)
                        Button("Decline") { engine.decline(peer) }
                            .buttonStyle(.bordered)
                    }
                }
            }
            Section("In the room (\(engine.admittedPeers.count))") {
                if engine.admittedPeers.isEmpty {
                    Text("Just you so far.").foregroundStyle(.secondary)
                }
                ForEach(engine.admittedPeers) { peer in
                    Text(peer.nickname)
                }
            }
            Section("Send a test message to everyone") {
                HStack {
                    TextField("Type something", text: $message)
                    Button("Send") {
                        engine.hostBroadcast(text: message)
                        message = ""
                    }
                }
            }
            Section("Log") {
                LogView(entries: engine.log)
            }
        }
    }
}

private struct JoinView: View {
    @Bindable var engine: SpikeEngine
    @State private var message = ""

    var body: some View {
        Form {
            if !engine.connectedAndAdmitted {
                Section("Rooms nearby") {
                    if engine.discoveredHosts.isEmpty {
                        Text("Looking...").foregroundStyle(.secondary)
                    }
                    ForEach(engine.discoveredHosts) { endpoint in
                        Button {
                            engine.requestJoin(endpoint)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(endpoint.txtRecord["host"] ?? endpoint.name)
                                Text(endpoint.txtRecord["label"].map { "Room: \($0)" } ?? endpoint.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if engine.declined {
                    Section {
                        Text("The host declined your request.").foregroundStyle(.red)
                    }
                }
            } else {
                Section("You're in the room") {
                    HStack {
                        TextField("Type something", text: $message)
                        Button("Send") {
                            engine.sendChat(text: message)
                            message = ""
                        }
                    }
                }
            }
            Section("Log") {
                LogView(entries: engine.log)
            }
        }
    }
}

private struct LogView: View {
    let entries: [LogEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(entries) { entry in
                            Text(entry.formatted)
                                .font(.system(size: 11, design: .monospaced))
                                .id(entry.id)
                        }
                    }
                }
                .frame(height: 220)
                .onChange(of: entries.count) { _, _ in
                    if let last = entries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            Button("Copy log") {
                UIPasteboard.general.string = entries.map(\.formatted).joined(separator: "\n")
            }
            .font(.caption)
        }
    }
}

#Preview {
    ContentView()
}

import SwiftUI

struct ContentView: View {
    @Bindable var monitor: ConnectionMonitor

    // Theme Switcher State
    @State private var selectedTheme: Theme = .system
    
    enum Theme: String, CaseIterable, Identifiable {
        case system = "System"
        case light = "Light"
        case dark = "Dark"
        
        var id: String { self.rawValue }
        
        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
        
        var icon: String {
            switch self {
            case .system: return "laptopcomputer"
            case .light: return "sun.max.fill"
            case .dark: return "moon.fill"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            DetailView(monitor: monitor)
                .navigationTitle("TCP Port Monitor")
                .preferredColorScheme(selectedTheme.colorScheme)
                .toolbar {
                    ToolbarItemGroup(placement: .principal) {
                        HStack(spacing: 12) {
                            ControlGroup {
                                Toggle("IPv4", isOn: $monitor.filterIPv4)
                                Toggle("IPv6", isOn: $monitor.filterIPv6)
                            }
                            .help("Filter IP Version")
                            
                            Divider()
                                .frame(height: 16)
                            
                            ControlGroup {
                                Toggle("LISTEN", isOn: $monitor.filterListen)
                                Toggle("ESTABLISHED", isOn: $monitor.filterEstablished)
                                Toggle("CLOSE", isOn: $monitor.filterCloseWait)
                                Toggle("TIME", isOn: $monitor.filterTimeWait)
                                Toggle("Other", isOn: $monitor.filterOthers)
                            }
                            .help("Filter TCP State")
                        }
                    }
                    
                    ToolbarItemGroup(placement: .primaryAction) {
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Toggle(isOn: $monitor.isAutoRefreshEnabled) {
                                    Image(systemName: "clock")
                                }
                                .toggleStyle(.button)
                                .help("Auto Refresh")
                                
                                Picker("Interval", selection: $monitor.refreshInterval) {
                                    Text("1s").tag(1.0)
                                    Text("2s").tag(2.0)
                                    Text("5s").tag(5.0)
                                    Text("10s").tag(10.0)
                                    Text("30s").tag(30.0)
                                    Text("60s").tag(60.0)
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .disabled(!monitor.isAutoRefreshEnabled)
                                .frame(width: 65)
                                .help("Refresh Interval")
                                
                                Button(action: {
                                    monitor.refresh()
                                }) {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .buttonStyle(.borderless)
                                .disabled(monitor.isRefreshing)
                                .help("Refresh Now")
                            }
                            
                            Divider()
                                .frame(height: 16)
                            
                            Picker("Theme Selection", selection: $selectedTheme) {
                                ForEach(Theme.allCases) { theme in
                                    Image(systemName: theme.icon)
                                        .tag(theme)
                                }
                            }
                            .pickerStyle(.segmented)
                            .help("Select Theme (System / Light / Dark)")
                        }
                    }
                }
        }
    }
}

// Detail subview containing search bars, resizable native Table, and actions
struct DetailView: View {
    @Bindable var monitor: ConnectionMonitor
    
    // Selection state for native Table
    @State private var selectedConnectionID: Connection.ID? = nil
    
    // Process Kill States
    @State private var processToKill: Connection? = nil
    @State private var showingKillConfirmation = false
    @State private var killingStatusMessage: String? = nil
    @State private var showingStatusAlert = false

    // Opens the resizable "Launch Command" window for a process.
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        // Pre-declare each table column as a local variable.
        // This isolates type checking and speeds up compilation by a factor of 100.
        let col1 = TableColumn("TYPE", value: \Connection.typeSortValue) { (conn: Connection) in
            TypeCell(type: conn.type)
        }
        .width(min: 60, ideal: 70, max: 90)
        
        let col2 = TableColumn("LOCAL ADDRESS", value: \Connection.localAddress) { (conn: Connection) in
            AddressCell(address: conn.localAddress)
        }
        .width(min: 100, ideal: 170, max: 300)
        
        let col3 = TableColumn("PORT", value: \Connection.localPortSortValue) { (conn: Connection) in
            PortCell(port: conn.localPort, fallback: "*")
        }
        .width(min: 45, ideal: 55, max: 80)
        
        let col4 = TableColumn("REMOTE ADDRESS", value: \Connection.remoteAddressSortValue) { (conn: Connection) in
            AddressCell(address: conn.remoteAddress)
        }
        .width(min: 100, ideal: 170, max: 300)
        
        let col5 = TableColumn("PORT", value: \Connection.remotePortSortValue) { (conn: Connection) in
            PortCell(port: conn.remotePort, fallback: "-")
        }
        .width(min: 45, ideal: 55, max: 80)
        
        let col6 = TableColumn("STATE", value: \Connection.stateSortValue) { (conn: Connection) in
            StateBadge(state: conn.state)
        }
        .width(min: 80, ideal: 110, max: 150)
        
        let col7 = TableColumn("PROCESS / PID", value: \Connection.command) { (conn: Connection) in
            ProcessCell(command: conn.command, pid: conn.pid) {
                showInfo(for: conn)
            }
        }
        .width(min: 120, ideal: 170, max: 250)
        
        let col8 = TableColumn("USER", value: \Connection.user) { (conn: Connection) in
            UserCell(user: conn.user, username: conn.username)
        }
        .width(min: 50, ideal: 60, max: 120)
        
        let col9 = TableColumn("ACTIONS") { (conn: Connection) in
            ActionsCell(connection: conn, processToKill: $processToKill, showingKillConfirmation: $showingKillConfirmation)
        }
        .width(min: 60, ideal: 70, max: 80)
        
        return VStack(spacing: 0) {
            // Top Search and Monitor Port Filters
            HStack(spacing: 15) {
                // Search box
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search PID, process name, IP...", text: $monitor.searchText)
                        .textFieldStyle(.plain)
                    if !monitor.searchText.isEmpty {
                        Button(action: { monitor.searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                
                // Port filter text field
                HStack {
                    Image(systemName: "number")
                        .foregroundStyle(.secondary)
                    TextField("Monitor ports (e.g. 80, 443, 8080)", text: $monitor.portFilterInput)
                        .textFieldStyle(.plain)
                    if !monitor.portFilterInput.isEmpty {
                        Button(action: { monitor.portFilterInput = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .frame(width: 320)
            }
            .padding()
            .background(.thinMaterial)
            
            // Connection Native Resizable Table
            let connections = monitor.filteredConnections
            if connections.isEmpty {
                VStack(spacing: 15) {
                    Spacer()
                    Image(systemName: "network.slash")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text(monitor.isRefreshing ? "Fetching connections..." : "No active TCP connections match the filters.")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(connections, selection: $selectedConnectionID, sortOrder: $monitor.sortOrder) {
                    col1
                    col2
                    col3
                    col4
                    col5
                    col6
                    col7
                    col8
                    col9
                }
                .tableStyle(.inset)
                .contextMenu(forSelectionType: Connection.ID.self) { selection in
                    if let id = selection.first, let conn = connections.first(where: { $0.id == id }) {
                        Button("Kill Process (Normal)") {
                            killProcess(conn, useSudo: false)
                        }
                        Button("Kill Process with Sudo") {
                            killProcess(conn, useSudo: true)
                        }
                    }
                }
            }
            
            // Bottom Status Bar
            HStack {
                HStack(spacing: 8) {
                    if let lastError = monitor.lastError {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(lastError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text("Service running")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Text("Showing \(connections.count) of \(monitor.connections.count) connections")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if let lastRefreshed = monitor.lastRefreshedDate {
                    Text("Last updated: \(lastRefreshedString(lastRefreshed))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(.thinMaterial)
        }
        .frame(minWidth: 960)
        .alert("Terminate Process?", isPresented: $showingKillConfirmation, presenting: processToKill) { conn in
            Button("Cancel", role: .cancel) { }
            Button("Normal Kill") {
                killProcess(conn, useSudo: false)
            }
            Button("Sudo Kill (requires password)", role: .destructive) {
                killProcess(conn, useSudo: true)
            }
        } message: { conn in
            Text("Are you sure you want to terminate process '\(conn.command)' (PID \(conn.pid)) using port \(conn.localPort ?? 0)?\n\nIf it belongs to system or another user, Sudo Kill will request administrator privileges.")
        }
        .alert("Process Management", isPresented: $showingStatusAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(killingStatusMessage ?? "")
        }
        .onChange(of: monitor.connections) { _, newConnections in
            if let selectedID = selectedConnectionID, !newConnections.contains(where: { $0.id == selectedID }) {
                selectedConnectionID = nil
            }
        }
    }

    private func showInfo(for conn: Connection) {
        openWindow(id: "command-info", value: conn)
    }

    private func killProcess(_ conn: Connection, useSudo: Bool) {
        Task {
            do {
                try await monitor.killProcess(pid: conn.pid, useSudo: useSudo)
                killingStatusMessage = "Successfully sent termination signal to process '\(conn.command)' (PID \(conn.pid))."
            } catch {
                killingStatusMessage = "Failed to terminate process:\n\(error.localizedDescription)"
            }
            showingStatusAlert = true
        }
    }
    
    private func lastRefreshedString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

// Custom Cell Views to assist Swift compiler type-checking speed
struct TypeCell: View {
    let type: Connection.ProtocolType

    private var badgeColor: Color {
        switch type {
        case .ipv4: return .blue
        case .ipv6: return .purple
        case .dualStack: return .green
        case .unknown: return .gray
        }
    }

    var body: some View {
        Text(type.rawValue)
            .font(.caption)
            .fontWeight(.bold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.15))
            .foregroundStyle(badgeColor)
            .cornerRadius(4)
    }
}

struct AddressCell: View {
    let address: String?
    
    var body: some View {
        Text(address ?? "-")
            .font(.system(.subheadline, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

struct PortCell: View {
    let port: Int?
    let fallback: String
    
    var body: some View {
        let portStr = port != nil ? String(port!) : fallback
        Text(portStr)
            .font(.system(.subheadline, design: .monospaced))
            .fontWeight(.semibold)
    }
}

struct ProcessCell: View {
    let command: String
    let pid: Int
    let onInfo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(command)
                .fontWeight(.semibold)
                .lineLimit(1)
            HStack(spacing: 5) {
                Text("PID: \(String(pid))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(action: onInfo) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .help("Show the full command that launched this process")
            }
        }
    }
}

// A real, freely-resizable window showing the full launch command for a
// process. Fetches its own data via `.task` (reliable here since it is a
// top-level window, not a Table-cell popover/sheet).
struct CommandWindow: View {
    let connection: Connection
    let monitor: ConnectionMonitor

    @Environment(\.dismiss) private var dismiss

    enum DetailTab: String, CaseIterable, Identifiable {
        case command = "Command"
        case environment = "Environment"
        var id: String { rawValue }
    }

    @State private var fullCommand: String = ""
    @State private var workingDirectory: String? = nil
    @State private var environment: [String] = []
    @State private var isLoading = true
    @State private var selectedTab: DetailTab = .command
    @State private var showingKillConfirmation = false
    @State private var killError: String? = nil
    @State private var showingKillError = false

    private var localPortText: String {
        connection.localPort.map(String.init) ?? "*"
    }

    // Text currently shown / copied, based on the selected tab.
    private var shownText: String {
        switch selectedTab {
        case .command:
            return fullCommand
        case .environment:
            return environment.isEmpty
                ? "Environment unavailable — the process may have exited, or it belongs to another user (requires privileges)."
                : environment.joined(separator: "\n")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .foregroundStyle(.secondary)
                Text("\(connection.command)  ·  PID \(String(connection.pid))")
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }

            // Which connection row this command was opened from.
            HStack(spacing: 8) {
                StateBadge(state: connection.state)
                Text("\(connection.localAddress):\(localPortText)")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
                if let remote = connection.remoteAddress, let rport = connection.remotePort {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(remote):\(String(rport))")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            // Working directory of the process.
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(workingDirectory ?? (isLoading ? "…" : "Working directory unavailable"))
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Divider()

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading process details…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                Picker("", selection: $selectedTab) {
                    ForEach(DetailTab.allCases) { tab in
                        Text(tab == .environment && !environment.isEmpty ? "Environment (\(environment.count))" : tab.rawValue)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                ScrollView(.vertical) {
                    Text(shownText)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                HStack {
                    Button(role: .destructive) {
                        showingKillConfirmation = true
                    } label: {
                        Label("Kill Process", systemImage: "xmark.octagon.fill")
                    }
                    .tint(.red)

                    Spacer()

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(shownText, forType: .string)
                    } label: {
                        Label("Copy \(selectedTab.rawValue)", systemImage: "doc.on.doc")
                    }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 600, minHeight: 360)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Launch Command — \(connection.command) (PID \(connection.pid))")
        .task(id: connection.pid) {
            isLoading = true
            async let command = ConnectionMonitor.fetchFullCommand(pid: connection.pid)
            async let cwd = ConnectionMonitor.fetchWorkingDirectory(pid: connection.pid)
            async let env = ConnectionMonitor.fetchEnvironment(pid: connection.pid)
            fullCommand = await command
            workingDirectory = await cwd
            environment = await env
            isLoading = false
        }
        .alert("Terminate Process?", isPresented: $showingKillConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Normal Kill") { kill(useSudo: false) }
            Button("Sudo Kill (requires password)", role: .destructive) { kill(useSudo: true) }
        } message: {
            Text("Terminate '\(connection.command)' (PID \(connection.pid)) on port \(localPortText)?\n\nIf it belongs to the system or another user, Sudo Kill will request administrator privileges.")
        }
        .alert("Could Not Terminate Process", isPresented: $showingKillError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(killError ?? "")
        }
    }

    private func kill(useSudo: Bool) {
        Task {
            do {
                try await ConnectionMonitor.performKill(pid: connection.pid, useSudo: useSudo)
                monitor.refresh() // update the main table so the row disappears
                dismiss()         // process is gone; close this window
            } catch {
                killError = error.localizedDescription
                showingKillError = true
            }
        }
    }
}

struct UserCell: View {
    let user: String
    let username: String?
    
    var body: some View {
        let displayName = username ?? user
        VStack(alignment: .leading, spacing: 1) {
            Text(displayName)
                .font(.subheadline)
                .lineLimit(1)
            Text("ID: \(user)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct ActionsCell: View {
    let connection: Connection
    @Binding var processToKill: Connection?
    @Binding var showingKillConfirmation: Bool
    
    var body: some View {
        Button(action: {
            processToKill = connection
            showingKillConfirmation = true
        }) {
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .font(.title3)
        }
        .buttonStyle(.plain)
        .help("Terminate process \(connection.command) (PID \(connection.pid))")
    }
}

// State Badge helper
struct StateBadge: View {
    let state: Connection.ConnectionState
    
    var body: some View {
        Text(state.rawValue)
            .font(.caption)
            .fontWeight(.bold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(backgroundColor.opacity(0.15))
            .foregroundStyle(backgroundColor)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(backgroundColor.opacity(0.3), lineWidth: 1)
            )
    }
    
    var backgroundColor: Color {
        switch state {
        case .listen:
            return .blue
        case .established:
            return .green
        case .closeWait, .timeWait:
            return .orange
        case .synSent, .synReceived:
            return .teal
        case .finWait1, .finWait2, .closing, .lastAck:
            return .red
        case .closed:
            return .gray
        case .unknown:
            return .secondary
        }
    }
}

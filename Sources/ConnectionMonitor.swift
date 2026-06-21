import Foundation
import Combine
import Observation

@Observable @MainActor
class ConnectionMonitor {
    // Observable states
    var connections: [Connection] = []
    var isRefreshing = false
    var lastError: String? = nil
    var lastRefreshedDate: Date? = Date()
    
    // Refresh configuration
    var isAutoRefreshEnabled = false {
        didSet {
            setupTimer()
        }
    }
    
    var refreshInterval: Double = 5.0 {
        didSet {
            setupTimer()
        }
    }
    
    // Port filter input (comma/space separated list of ports, e.g. "80, 443")
    var portFilterInput: String = "" {
        didSet {
            refresh()
        }
    }
    
    // Filter States (Initially show IPv4 and Listening ports only)
    var searchText = ""
    var filterIPv4 = true
    var filterIPv6 = false
    var filterListen = true
    var filterEstablished = false
    var filterCloseWait = false
    var filterTimeWait = false
    var filterOthers = false
    
    // Sorting order state
    var sortOrder = [KeyPathComparator(\Connection.localPortSortValue, order: .forward)]
    
    private var refreshTask: Task<Void, Never>? = nil
    
    init() {
        setupTimer()
        refresh()
    }
    
    func setupTimer() {
        refreshTask?.cancel()
        refreshTask = nil
        
        guard isAutoRefreshEnabled else { return }
        
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }
                let interval = self.refreshInterval
                
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    break
                }
                
                if Task.isCancelled { break }
                self.refresh()
            }
        }
    }
    
    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        
        let portsToMonitor = parsePorts(from: portFilterInput)
        
        Task {
            do {
                let parsed = try await ConnectionMonitor.fetchAndParse(ports: portsToMonitor)
                self.connections = parsed
                self.lastRefreshedDate = Date()
                self.isRefreshing = false
                self.lastError = nil
            } catch {
                self.isRefreshing = false
                self.lastError = error.localizedDescription
            }
        }
    }
    
    // Filtered and Sorted Connections
    var filteredConnections: [Connection] {
        var result = connections
        
        // Single-pass combined filtering for optimal performance
        if !searchText.isEmpty || !filterIPv4 || !filterIPv6 || !filterListen || !filterEstablished || !filterCloseWait || !filterTimeWait || !filterOthers {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            
            result = result.filter { conn in
                // 1. IP Protocol Filter
                switch conn.type {
                case .ipv4:
                    if !filterIPv4 { return false }
                case .ipv6:
                    if !filterIPv6 { return false }
                case .dualStack:
                    // Dual-stack listeners are reachable over both protocols, so
                    // show them whenever either IPv4 or IPv6 is enabled.
                    if !filterIPv4 && !filterIPv6 { return false }
                case .unknown:
                    break
                }
                
                // 2. TCP State Filter
                if !shouldShowState(conn.state) { return false }
                
                // 3. Search query filter
                if !query.isEmpty {
                    let matchesSearch = conn.command.lowercased().contains(query) ||
                                       String(conn.pid).contains(query) ||
                                       conn.user.lowercased().contains(query) ||
                                       (conn.username?.lowercased().contains(query) ?? false) ||
                                       conn.localAddress.lowercased().contains(query) ||
                                       (conn.remoteAddress?.lowercased().contains(query) ?? false) ||
                                       String(conn.localPort ?? 0).contains(query) ||
                                       String(conn.remotePort ?? 0).contains(query)
                    if !matchesSearch { return false }
                }
                
                return true
            }
        }
        
        // Native Sorting
        result.sort(using: sortOrder)
        
        return result
    }
    
    private func shouldShowState(_ state: Connection.ConnectionState) -> Bool {
        if state == .listen && filterListen { return true }
        if state == .established && filterEstablished { return true }
        if state == .closeWait && filterCloseWait { return true }
        if state == .timeWait && filterTimeWait { return true }
        
        let common: [Connection.ConnectionState] = [.listen, .established, .closeWait, .timeWait]
        if !common.contains(state) && filterOthers { return true }
        
        return false
    }
    
    private func parsePorts(from input: String) -> [Int] {
        let components = input.components(separatedBy: CharacterSet(charactersIn: ", \t\n"))
        return components.compactMap {
            let trimmed = $0.trimmingCharacters(in: .whitespaces)
            return Int(trimmed)
        }
    }
    
    nonisolated private static func fetchAndParse(ports: [Int]) async throws -> [Connection] {
        return try await Task.detached(priority: .userInitiated) {
            let output = try runLsof(ports: ports)
            return parseLsofOutput(output)
        }.value
    }
    
    nonisolated private static func runLsof(ports: [Int]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        
        var arguments = ["-iTCP", "-P", "-n", "-F", "pcuftTsnL"]
        if !ports.isEmpty {
            let portStr = ports.map { String($0) }.joined(separator: ",")
            arguments[0] = "-iTCP:\(portStr)"
        }
        
        process.arguments = arguments
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe() // Silence stderr
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        
        if process.terminationStatus != 0 && data.isEmpty {
            if process.terminationStatus == 1 {
                return ""
            }
            throw NSError(domain: "LsofError", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "lsof exited with code \(process.terminationStatus)"])
        }
        
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    nonisolated private static func parseLsofOutput(_ output: String) -> [Connection] {
        var parsed: [Connection] = []
        let lines = output.components(separatedBy: .newlines)
        
        var currentPid: Int? = nil
        var currentCommand: String? = nil
        var currentUid: String? = nil
        var currentUsername: String? = nil
        
        var currentFd: String? = nil
        var currentType: Connection.ProtocolType = .unknown
        var currentName: String? = nil
        var currentState: Connection.ConnectionState = .unknown
        
        func commitSocket() {
            guard let pid = currentPid,
                  let command = currentCommand,
                  let user = currentUid,
                  let fd = currentFd,
                  let name = currentName else {
                return
            }
            
            let (localAddress, localPort, remoteAddress, remotePort) = parseNameField(name)
            
            var connectionType = currentType
            if connectionType == .ipv6 {
                if localAddress.contains(".") && !localAddress.contains(":") {
                    connectionType = .ipv4
                } else if localAddress == "*" {
                    // A wildcard IPv6 listener on macOS is dual-stack by default
                    // (IPV6_V6ONLY off), so it accepts IPv4 connections too. lsof
                    // reports it as IPv6; netstat shows it as tcp46. Common for
                    // Java/Tomcat/Spring Boot servers.
                    connectionType = .dualStack
                }
            }
            
            let connection = Connection(
                pid: pid,
                command: command,
                user: user,
                username: currentUsername,
                fd: fd,
                type: connectionType,
                localAddress: localAddress,
                localPort: localPort,
                remoteAddress: remoteAddress,
                remotePort: remotePort,
                state: currentState
            )
            parsed.append(connection)
        }
        
        for line in lines {
            if line.isEmpty { continue }
            
            let prefix = line.prefix(1)
            let value = String(line.dropFirst())
            
            switch prefix {
            case "p":
                if currentFd != nil {
                    commitSocket()
                    currentFd = nil
                }
                currentPid = Int(value)
                currentCommand = nil
                currentUid = nil
                currentUsername = nil
                
            case "c":
                currentCommand = value
                
            case "u":
                currentUid = value
                
            case "L":
                currentUsername = value
                
            case "f":
                if currentFd != nil {
                    commitSocket()
                }
                currentFd = value
                currentType = .unknown
                currentName = nil
                currentState = .unknown
                
            case "t":
                currentType = Connection.ProtocolType.from(string: value)
                
            case "n":
                currentName = value
                
            case "T":
                if value.hasPrefix("ST=") {
                    let stateStr = String(value.dropFirst(3))
                    currentState = Connection.ConnectionState.from(string: stateStr)
                }
                
            default:
                break
            }
        }
        
        if currentFd != nil {
            commitSocket()
        }
        
        return parsed
    }
    
    nonisolated private static func parseNameField(_ name: String) -> (localAddress: String, localPort: Int?, remoteAddress: String?, remotePort: Int?) {
        let components = name.components(separatedBy: "->")
        if components.count == 2 {
            let (localAddr, localP) = parseAddressAndPort(components[0])
            let (remoteAddr, remoteP) = parseAddressAndPort(components[1])
            return (localAddr, localP, remoteAddr, remoteP)
        } else {
            let (localAddr, localP) = parseAddressAndPort(name)
            return (localAddr, localP, nil, nil)
        }
    }
    
    nonisolated private static func parseAddressAndPort(_ s: String) -> (address: String, port: Int?) {
        if s.hasPrefix("[") {
            if let closingBracketIndex = s.firstIndex(of: "]") {
                let addrStart = s.index(after: s.startIndex)
                let address = String(s[addrStart..<closingBracketIndex])
                let remaining = s[s.index(after: closingBracketIndex)...]
                if remaining.hasPrefix(":") {
                    let portStr = String(remaining.dropFirst())
                    return (address, Int(portStr))
                }
                return (address, nil)
            }
        }
        
        if let lastColonIndex = s.lastIndex(of: ":") {
            let address = String(s[..<lastColonIndex])
            let portStr = String(s[s.index(after: lastColonIndex)...])
            return (address, Int(portStr))
        }
        
        return (s, nil)
    }
    
    // Kill Process
    func killProcess(pid: Int, useSudo: Bool) async throws {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            
            if useSudo {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", "do shell script \"kill -9 \(pid)\" with administrator privileges"]
            } else {
                process.executableURL = URL(fileURLWithPath: "/bin/kill")
                process.arguments = ["-9", String(pid)]
            }
            
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus != 0 {
                let errorMsg = useSudo ? "Sudo authentication cancelled or failed." : "Failed to kill process (requires sudo?)."
                throw NSError(domain: "KillError", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errorMsg])
            }
        }.value
        
        refresh()
    }
}

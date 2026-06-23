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
    var isAutoRefreshEnabled = true {
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
    
    // Filter States (Initially show IPv4 and Listening ports only).
    // Changing any of these re-renders the table, so we restamp the
    // "last updated" time to reflect that the displayed set just changed.
    var searchText = "" { didSet { markDisplayUpdated() } }
    var filterIPv4 = true { didSet { markDisplayUpdated() } }
    var filterIPv6 = false { didSet { markDisplayUpdated() } }
    var filterListen = true { didSet { markDisplayUpdated() } }
    var filterEstablished = false { didSet { markDisplayUpdated() } }
    var filterCloseWait = false { didSet { markDisplayUpdated() } }
    var filterTimeWait = false { didSet { markDisplayUpdated() } }
    var filterOthers = false { didSet { markDisplayUpdated() } }

    /// Restamp the displayed-data timestamp without refetching.
    private func markDisplayUpdated() {
        lastRefreshedDate = Date()
    }
    
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
            // Run `jps` concurrently with `lsof` so Java detection adds no latency.
            async let javaTask = fetchJavaPIDs()
            let output = try runLsof(ports: ports)
            var parsed = parseLsofOutput(output)
            let javaPIDs = await javaTask
            for i in parsed.indices {
                parsed[i].isJava = javaPIDs.contains(parsed[i].pid) || parsed[i].commandSuggestsJava
            }
            return parsed
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
    
    // Fetch the full command line that launched a process via `ps`.
    // Always returns a non-empty string: the command on success, or a short
    // diagnostic (exit code / stderr / launch error) on failure so the UI is
    // never silently blank.
    nonisolated static func fetchFullCommand(pid: Int) async -> String {
        return await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/ps")
            // -ww: do not truncate the output; -o command=: print full argv with no header.
            process.arguments = ["-ww", "-o", "command=", "-p", String(pid)]

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            do {
                try process.run()
            } catch {
                return "Unable to launch /bin/ps: \(error.localizedDescription)"
            }

            // Read before waiting to avoid any pipe-buffer stall, then wait.
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            let out = (String(data: outData, encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !out.isEmpty { return out }

            let err = (String(data: errData, encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if process.terminationStatus != 0 || !err.isEmpty {
                return "ps exited \(process.terminationStatus)\(err.isEmpty ? "" : ": \(err)")"
            }
            return "No command reported for PID \(pid) (process may have exited)."
        }.value
    }

    // Fetch the current working directory of a process via `lsof` (the `cwd`
    // file descriptor). Returns nil if unavailable (e.g. owned by another user
    // and not readable without privileges).
    nonisolated static func fetchWorkingDirectory(pid: Int) async -> String? {
        return await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            // -a AND-combines filters; -d cwd selects the cwd descriptor;
            // -Fn emits a machine-readable "n<path>" line.
            process.arguments = ["-a", "-d", "cwd", "-p", String(pid), "-Fn", "-P", "-n"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            do { try process.run() } catch { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard let out = String(data: data, encoding: .utf8) else { return nil }
            for line in out.split(separator: "\n") where line.hasPrefix("n") {
                let path = String(line.dropFirst())
                return path.isEmpty ? nil : path
            }
            return nil
        }.value
    }

    // Fetch a process's environment via the KERN_PROCARGS2 sysctl — the same
    // mechanism `ps` uses. The returned buffer is laid out as:
    //   [Int32 argc][exec_path\0][padding\0...][argv[0]\0]...[argv[argc-1]\0][env\0]...
    // Returns sorted "KEY=value" strings, or [] if not readable (e.g. another
    // user's process without privileges).
    nonisolated static func fetchEnvironment(pid: Int) async -> [String] {
        return await Task.detached(priority: .userInitiated) {
            var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, Int32(pid)]
            var size = 0
            if sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) != 0 || size == 0 {
                return []
            }
            var buffer = [CChar](repeating: 0, count: size)
            if sysctl(&mib, UInt32(mib.count), &buffer, &size, nil, 0) != 0 {
                return []
            }

            return buffer.withUnsafeBufferPointer { ptr -> [String] in
                guard let base = ptr.baseAddress, size >= MemoryLayout<Int32>.size else { return [] }
                let total = size
                var offset = 0

                var argc: Int32 = 0
                memcpy(&argc, base, MemoryLayout<Int32>.size)
                offset = MemoryLayout<Int32>.size

                // Reads a NUL-terminated string at `offset`, advancing past the NUL.
                func nextString() -> String? {
                    guard offset < total else { return nil }
                    let start = offset
                    while offset < total && base[offset] != 0 { offset += 1 }
                    guard offset < total else { return nil }
                    let s = String(cString: base + start)
                    offset += 1
                    return s
                }

                _ = nextString()                                  // exec_path
                while offset < total && base[offset] == 0 { offset += 1 } // alignment padding

                var consumed: Int32 = 0                           // skip argv
                while consumed < argc, nextString() != nil { consumed += 1 }

                var env: [String] = []                            // remaining = environment
                while offset < total {
                    while offset < total && base[offset] == 0 { offset += 1 }
                    guard let s = nextString(), !s.isEmpty else { break }
                    env.append(s)
                }
                return env.sorted()
            }
        }.value
    }

    // MARK: - Java / JVM detection and inspection

    // PIDs of all JVM processes, via `jps` (authoritative for the current user).
    // Output is "<pid> <name>" lines; the leading token is the PID. Returns an
    // empty set if no jps is found, in which case detection falls back to the
    // command-name heuristic (`commandSuggestsJava`).
    nonisolated private static func fetchJavaPIDs() async -> Set<Int> {
        await Task.detached(priority: .utility) {
            guard let jps = jpsPath() else { return [] }
            let out = runCapture(jps, [])
            var pids = Set<Int>()
            for line in out.split(separator: "\n") {
                if let tok = line.split(separator: " ").first, let pid = Int(tok) {
                    pids.insert(pid)
                }
            }
            return pids
        }.value
    }

    // Finds a usable jps: the system stub, else the default JDK's bin/jps.
    nonisolated private static func jpsPath() -> String? {
        let fm = FileManager.default
        if fm.isExecutableFile(atPath: "/usr/bin/jps") { return "/usr/bin/jps" }
        let home = runCapture("/usr/libexec/java_home", [])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !home.isEmpty {
            let candidate = (home as NSString).appendingPathComponent("bin/jps")
            if fm.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    // JVM system properties via `jcmd <pid> VM.system_properties`. Uses the jcmd
    // shipped alongside the process's own `java` binary (so the attach protocol
    // matches the target's Java version), falling back to a system jcmd.
    nonisolated static func fetchSystemProperties(pid: Int) async -> [String] {
        await Task.detached(priority: .userInitiated) {
            let jcmd = jcmdPath(forPid: pid)
            let out = runCapture(jcmd, [String(pid), "VM.system_properties"])
            return parseSystemProperties(out)
        }.value
    }

    // Locates the jcmd matching the target process's Java install: the executable
    // path comes from `ps -o comm=`, and jcmd lives next to it in the same bin/.
    nonisolated private static func jcmdPath(forPid pid: Int) -> String {
        let comm = runCapture("/bin/ps", ["-o", "comm=", "-p", String(pid)])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !comm.isEmpty {
            let dir = (comm as NSString).deletingLastPathComponent
            let candidate = (dir as NSString).appendingPathComponent("jcmd")
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return "/usr/bin/jcmd"  // PATH/system fallback
    }

    // Parses `jcmd … VM.system_properties` (Java .properties format): drops the
    // "<pid>:" header and "#"-comments, splits each "key=value" on the first
    // unescaped '=', and unescapes Java property escapes. Returns sorted entries.
    nonisolated static func parseSystemProperties(_ output: String) -> [String] {
        var props: [String] = []
        for raw in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(raw)
            if line.hasPrefix("#") { continue }
            if line.hasSuffix(":"), Int(line.dropLast()) != nil { continue }  // "<pid>:" header
            guard let eq = firstUnescapedEquals(line) else { continue }
            let key = unescapeProperty(String(line[line.startIndex..<eq]))
            let value = unescapeProperty(String(line[line.index(after: eq)...]))
            props.append("\(key)=\(value)")
        }
        return props.sorted()
    }

    nonisolated private static func firstUnescapedEquals(_ s: String) -> String.Index? {
        var idx = s.startIndex
        var escaped = false
        while idx < s.endIndex {
            let c = s[idx]
            if escaped { escaped = false }
            else if c == "\\" { escaped = true }
            else if c == "=" { return idx }
            idx = s.index(after: idx)
        }
        return nil
    }

    // Unescapes \\, \=, \:, \ , \#, \uXXXX etc. Keeps \n/\r/\t/\f as their literal
    // two-character form so each property stays on a single display line.
    nonisolated private static func unescapeProperty(_ s: String) -> String {
        let chars = Array(s)
        var out = ""
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\\", i + 1 < chars.count {
                let n = chars[i + 1]
                switch n {
                case "n", "r", "t", "f":
                    out.append("\\"); out.append(n)  // keep readable, single-line
                case "u" where i + 5 < chars.count:
                    if let code = UInt32(String(chars[(i + 2)...(i + 5)]), radix: 16),
                       let scalar = Unicode.Scalar(code) {
                        out.append(Character(scalar)); i += 6; continue
                    }
                    out.append(n)
                default:
                    out.append(n)  // \: \= \\ \space \# … -> literal
                }
                i += 2
            } else {
                out.append(c); i += 1
            }
        }
        return out
    }

    // Small synchronous capture helper for the short-lived JVM tools above.
    nonisolated private static func runCapture(_ path: String, _ args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    // Performs the actual SIGKILL (optionally via sudo). Standalone so it can
    // be invoked from any view, including the separate Launch Command window.
    nonisolated static func performKill(pid: Int, useSudo: Bool) async throws {
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
    }

    // Kill Process
    func killProcess(pid: Int, useSudo: Bool) async throws {
        try await ConnectionMonitor.performKill(pid: pid, useSudo: useSudo)
        refresh()
    }
}

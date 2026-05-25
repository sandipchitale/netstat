import Foundation

struct Connection: Identifiable, Hashable, Sendable {
    var id: String {
        return "\(pid)-\(fd)-\(type.rawValue)-\(localAddress)-\(localPort ?? 0)-\(remoteAddress ?? "")-\(remotePort ?? 0)-\(state.rawValue)"
    }
    
    let pid: Int
    let command: String
    let user: String // Store user ID (UID)
    let username: String? // Store login name
    let fd: String
    let type: ProtocolType
    let localAddress: String
    let localPort: Int?
    let remoteAddress: String?
    let remotePort: Int?
    let state: ConnectionState
    
    // Sort helper computed properties (non-optional and Comparable)
    var localPortSortValue: Int { localPort ?? -1 }
    var remotePortSortValue: Int { remotePort ?? -1 }
    var remoteAddressSortValue: String { remoteAddress ?? "" }
    var typeSortValue: String { type.rawValue }
    var stateSortValue: String { state.rawValue }
    
    enum ProtocolType: String, Codable, CaseIterable, Sendable {
        case ipv4 = "IPv4"
        case ipv6 = "IPv6"
        case unknown = "Unknown"
        
        static func from(string: String) -> ProtocolType {
            let s = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if s.contains("ipv4") || s == "4" {
                return .ipv4
            } else if s.contains("ipv6") || s == "6" {
                return .ipv6
            }
            return .unknown
        }
    }
    
    enum ConnectionState: String, Codable, CaseIterable, Sendable {
        case listen = "LISTEN"
        case established = "ESTABLISHED"
        case closeWait = "CLOSE_WAIT"
        case timeWait = "TIME_WAIT"
        case synSent = "SYN_SENT"
        case synReceived = "SYN_RECEIVED"
        case finWait1 = "FIN_WAIT_1"
        case finWait2 = "FIN_WAIT_2"
        case lastAck = "LAST_ACK"
        case closing = "CLOSING"
        case closed = "CLOSED"
        case unknown = "UNKNOWN"
        
        static func from(string: String) -> ConnectionState {
            let normalized = string.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            for state in ConnectionState.allCases {
                if state.rawValue == normalized {
                    return state
                }
            }
            if normalized.contains("LISTEN") { return .listen }
            if normalized.contains("ESTABLISHED") { return .established }
            if normalized.contains("CLOSE_WAIT") { return .closeWait }
            if normalized.contains("TIME_WAIT") { return .timeWait }
            if normalized.contains("SYN_SENT") { return .synSent }
            if normalized.contains("SYN_RCVD") || normalized.contains("SYN_RECEIVED") { return .synReceived }
            if normalized.contains("FIN_WAIT_1") || normalized.contains("FIN_WAIT1") { return .finWait1 }
            if normalized.contains("FIN_WAIT_2") || normalized.contains("FIN_WAIT2") { return .finWait2 }
            if normalized.contains("LAST_ACK") { return .lastAck }
            if normalized.contains("CLOSING") { return .closing }
            if normalized.contains("CLOSED") { return .closed }
            return .unknown
        }
    }
}

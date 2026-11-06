import Darwin
import Foundation

public enum MihomoError: LocalizedError {
    case socketUnavailable
    case connectionFailed(String)
    case invalidResponse
    case httpStatus(Int, String)
    case invalidJSON

    public var errorDescription: String? {
        switch self {
        case .socketUnavailable: "找不到 Mihomo 控制接口"
        case let .connectionFailed(message): "连接 Mihomo 失败：\(message)"
        case .invalidResponse: "Mihomo 返回了无效响应"
        case let .httpStatus(status, message): "Mihomo API \(status)：\(message)"
        case .invalidJSON: "Mihomo 返回了无效 JSON"
        }
    }
}

public struct MihomoRuntime: Equatable, Sendable {
    public var mode: String
    public var tunEnabled: Bool
    public var mixedPort: Int
    public var selectedProxy: String
    public var uploadTotal: Int64
    public var downloadTotal: Int64
    public var connections: Int

    public init(
        mode: String,
        tunEnabled: Bool,
        mixedPort: Int,
        selectedProxy: String,
        uploadTotal: Int64,
        downloadTotal: Int64,
        connections: Int
    ) {
        self.mode = mode
        self.tunEnabled = tunEnabled
        self.mixedPort = mixedPort
        self.selectedProxy = selectedProxy
        self.uploadTotal = uploadTotal
        self.downloadTotal = downloadTotal
        self.connections = connections
    }
}

public final class MihomoClient: @unchecked Sendable {
    public let socketPath: String

    public init(socketPath: String? = nil) throws {
        if let socketPath {
            self.socketPath = socketPath
        } else if let discovered = Self.discoverSocketPath() {
            self.socketPath = discovered
        } else {
            throw MihomoError.socketUnavailable
        }
    }

    public static func discoverSocketPath(fileManager: FileManager = .default) -> String? {
        let service = "/var/run/clash-verge-service/users/\(geteuid())/verge-mihomo.sock"
        if fileManager.fileExists(atPath: service) { return service }

        var capacity = confstr(_CS_DARWIN_USER_TEMP_DIR, nil, 0)
        if capacity > 1 {
            var bytes = [CChar](repeating: 0, count: capacity)
            capacity = confstr(_CS_DARWIN_USER_TEMP_DIR, &bytes, capacity)
            if capacity > 1 {
                let end = bytes.firstIndex(of: 0) ?? bytes.endIndex
                let directory = String(
                    decoding: bytes[..<end].map { UInt8(bitPattern: $0) },
                    as: UTF8.self
                )
                let sidecar = URL(fileURLWithPath: directory)
                    .appendingPathComponent("verge-mihomo.sock").path
                if fileManager.fileExists(atPath: sidecar) { return sidecar }
            }
        }
        return nil
    }

    public func fetchRuntime() throws -> MihomoRuntime {
        let configs = try jsonObject(path: "/configs")
        let connections = try jsonObject(path: "/connections")
        let proxies = (try? jsonObject(path: "/proxies")) ?? [:]
        let mode = configs["mode"] as? String ?? "rule"

        let tun = configs["tun"] as? [String: Any]
        return MihomoRuntime(
            mode: mode,
            tunEnabled: tun?["enable"] as? Bool ?? false,
            mixedPort: Self.int(configs["mixed-port"]),
            selectedProxy: Self.selectedProxy(from: proxies, mode: mode),
            uploadTotal: Self.int64(connections["uploadTotal"]),
            downloadTotal: Self.int64(connections["downloadTotal"]),
            connections: (connections["connections"] as? [Any])?.count ?? 0
        )
    }

    static func selectedProxy(from response: [String: Any], mode: String) -> String {
        if mode.caseInsensitiveCompare("direct") == .orderedSame { return "DIRECT" }
        guard let proxies = response["proxies"] as? [String: Any] else { return "—" }

        func rank(_ name: String, object: [String: Any]) -> Int {
            let lowered = name.lowercased()
            if mode.caseInsensitiveCompare("global") == .orderedSame, lowered == "global" { return 0 }
            if lowered == "proxy" { return 0 }
            if lowered.contains("proxy") || name.contains("节点") || name.contains("选择") || name.contains("代理") {
                return 1
            }
            if (object["type"] as? String)?.caseInsensitiveCompare("selector") == .orderedSame {
                return 2
            }
            if lowered == "global" { return 3 }
            return 4
        }

        let candidates = proxies.compactMap { name, value -> (String, [String: Any])? in
            guard let object = value as? [String: Any], object["now"] as? String != nil else { return nil }
            return (name, object)
        }.sorted {
            let left = rank($0.0, object: $0.1)
            let right = rank($1.0, object: $1.1)
            return left == right ? $0.0.localizedStandardCompare($1.0) == .orderedAscending : left < right
        }

        for (name, _) in candidates {
            var current = name
            var visited = Set<String>()
            while visited.insert(current).inserted,
                  let object = proxies[current] as? [String: Any],
                  let next = object["now"] as? String,
                  !next.isEmpty,
                  next != current
            {
                current = next
            }
            if current != name { return current }
        }
        return "—"
    }

    public func fetchConnectionTotals() throws -> (upload: Int64, download: Int64, count: Int) {
        let object = try jsonObject(path: "/connections")
        return (
            Self.int64(object["uploadTotal"]),
            Self.int64(object["downloadTotal"]),
            (object["connections"] as? [Any])?.count ?? 0
        )
    }

    @discardableResult
    public func request(
        method: String,
        path: String,
        json: [String: Any]? = nil
    ) throws -> Data {
        let body = try json.map { try JSONSerialization.data(withJSONObject: $0) } ?? Data()
        var request = "\(method) \(path) HTTP/1.1\r\n"
        request += "Host: localhost\r\n"
        request += "Accept: application/json\r\n"
        request += "Connection: close\r\n"
        if !body.isEmpty {
            request += "Content-Type: application/json\r\n"
            request += "Content-Length: \(body.count)\r\n"
        }
        request += "\r\n"

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw MihomoError.connectionFailed(String(cString: strerror(errno)))
        }
        defer { Darwin.close(fd) }

        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw MihomoError.connectionFailed("Unix socket 路径过长")
        }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { destination in
                for index in pathBytes.indices { destination[index] = pathBytes[index] }
            }
        }

        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            throw MihomoError.connectionFailed(String(cString: strerror(errno)))
        }

        var outbound = Data(request.utf8)
        outbound.append(body)
        try outbound.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var sent = 0
            while sent < rawBuffer.count {
                let count = Darwin.send(fd, base.advanced(by: sent), rawBuffer.count - sent, 0)
                guard count > 0 else {
                    throw MihomoError.connectionFailed(String(cString: strerror(errno)))
                }
                sent += count
            }
        }

        var incoming = Data()
        var buffer = [UInt8](repeating: 0, count: 32 * 1_024)
        while incoming.count < 16 * 1_024 * 1_024 {
            let count = Darwin.recv(fd, &buffer, buffer.count, 0)
            if count == 0 { break }
            if count < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK { break }
                throw MihomoError.connectionFailed(String(cString: strerror(errno)))
            }
            incoming.append(buffer, count: count)
        }
        return try Self.parseHTTPResponse(incoming)
    }

    private func jsonObject(path: String) throws -> [String: Any] {
        let data = try request(method: "GET", path: path)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MihomoError.invalidJSON
        }
        return object
    }

    static func parseHTTPResponse(_ data: Data) throws -> Data {
        let separator = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: separator),
              let header = String(data: data[..<range.lowerBound], encoding: .utf8)
        else { throw MihomoError.invalidResponse }
        let firstLine = header.split(separator: "\r\n", maxSplits: 1).first ?? ""
        let components = firstLine.split(separator: " ")
        guard components.count >= 2, let status = Int(components[1]) else {
            throw MihomoError.invalidResponse
        }
        var body = Data(data[range.upperBound...])
        if header.range(of: "(?im)^Transfer-Encoding:\\s*chunked\\s*$", options: .regularExpression) != nil {
            body = try decodeChunked(body)
        }
        guard (200..<300).contains(status) else {
            throw MihomoError.httpStatus(
                status,
                String(data: body, encoding: .utf8) ?? "未知错误"
            )
        }
        return body
    }

    static func decodeChunked(_ data: Data) throws -> Data {
        let crlf = Data("\r\n".utf8)
        var cursor = data.startIndex
        var output = Data()
        while cursor < data.endIndex {
            guard let lineRange = data.range(of: crlf, in: cursor..<data.endIndex),
                  let line = String(data: data[cursor..<lineRange.lowerBound], encoding: .utf8),
                  let sizeToken = line.split(separator: ";", maxSplits: 1).first,
                  let size = Int(sizeToken, radix: 16)
            else { throw MihomoError.invalidResponse }
            cursor = lineRange.upperBound
            if size == 0 { return output }
            guard size >= 0,
                  let end = data.index(cursor, offsetBy: size, limitedBy: data.endIndex),
                  end <= data.endIndex
            else { throw MihomoError.invalidResponse }
            output.append(data[cursor..<end])
            cursor = end
            guard cursor <= data.endIndex,
                  data.distance(from: cursor, to: data.endIndex) >= 2,
                  data[cursor..<data.index(cursor, offsetBy: 2)] == crlf
            else { throw MihomoError.invalidResponse }
            cursor = data.index(cursor, offsetBy: 2)
        }
        throw MihomoError.invalidResponse
    }

    private static func int(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return 0
    }

    private static func int64(_ value: Any?) -> Int64 {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        return 0
    }
}

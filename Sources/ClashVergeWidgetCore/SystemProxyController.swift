import Foundation

public struct SystemProxyEndpoint: Equatable, Sendable {
    public let host: String
    public let port: Int

    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }
}

public struct SystemProxySnapshot: Equatable, Sendable {
    public var enabled: Bool
    public var host: String
    public var port: Int
    public var enabledEndpoints: [SystemProxyEndpoint]
    public var pacEnabled: Bool
    public var pacURL: String

    public init(
        enabled: Bool,
        host: String = "",
        port: Int = 0,
        enabledEndpoints: [SystemProxyEndpoint]? = nil,
        pacEnabled: Bool = false,
        pacURL: String = ""
    ) {
        self.enabled = enabled
        self.host = host
        self.port = port
        self.enabledEndpoints = enabledEndpoints ?? (enabled && !host.isEmpty
            ? [SystemProxyEndpoint(host: host, port: port)]
            : [])
        self.pacEnabled = pacEnabled
        self.pacURL = pacURL
    }

    public func matches(host expectedHost: String, port expectedPort: Int) -> Bool {
        enabled && !pacEnabled && !enabledEndpoints.isEmpty && enabledEndpoints.allSatisfy {
            $0.host.caseInsensitiveCompare(expectedHost) == .orderedSame && $0.port == expectedPort
        }
    }

    public func matchesClashPAC() -> Bool {
        guard pacEnabled,
              let components = URLComponents(string: pacURL),
              let host = components.host?.lowercased(),
              ["127.0.0.1", "localhost", "::1"].contains(host)
        else { return false }
        return components.path == "/commands/pac"
    }
}

public final class SystemProxyController: @unchecked Sendable {
    public init() {}

    public func snapshot() -> SystemProxySnapshot {
        guard let result = try? ProcessRunner.run("/usr/sbin/scutil", ["--proxy"]),
              result.succeeded
        else { return SystemProxySnapshot(enabled: false) }

        return Self.snapshot(fromScutilOutput: result.stdout)
    }

    static func snapshot(fromScutilOutput text: String) -> SystemProxySnapshot {
        let fields = dictionary(fromScutilOutput: text)
        let mappings = [
            ("HTTPEnable", "HTTPProxy", "HTTPPort"),
            ("HTTPSEnable", "HTTPSProxy", "HTTPSPort"),
            ("SOCKSEnable", "SOCKSProxy", "SOCKSPort"),
        ]
        let endpoints = mappings.compactMap { enableKey, hostKey, portKey -> SystemProxyEndpoint? in
            guard fields[enableKey] == "1",
                  let host = fields[hostKey],
                  let port = Int(fields[portKey] ?? "")
            else { return nil }
            return SystemProxyEndpoint(host: host, port: port)
        }
        let pacEnabled = fields["ProxyAutoConfigEnable"] == "1"
        let pacURL = fields["ProxyAutoConfigURLString"] ?? ""
        let first = endpoints.first
        return SystemProxySnapshot(
            enabled: !endpoints.isEmpty || pacEnabled,
            host: first?.host ?? "",
            port: first?.port ?? 0,
            enabledEndpoints: endpoints,
            pacEnabled: pacEnabled,
            pacURL: pacURL
        )
    }

    static func dictionary(fromScutilOutput text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            result[parts[0].trimmingCharacters(in: .whitespaces)] =
                parts[1].trimmingCharacters(in: .whitespaces)
        }
        return result
    }

}

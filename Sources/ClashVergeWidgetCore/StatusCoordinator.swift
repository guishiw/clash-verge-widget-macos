import Foundation

public final class StatusCoordinator: @unchecked Sendable {
    public let configDirectory: URL
    private let profilesURL: URL
    private let vergeURL: URL
    private let proxyController: SystemProxyController
    private let hotkeyController: any ClashVergeHotkeyDispatching
    private let statusProvider: (() -> WidgetStatus)?
    private let controlPollInterval: TimeInterval
    private let controlPollAttempts: Int

    public init(
        configDirectory: URL? = nil,
        proxyController: SystemProxyController = SystemProxyController()
    ) {
        let directory = configDirectory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/io.github.clash-verge-rev.clash-verge-rev")
        self.configDirectory = directory
        profilesURL = directory.appendingPathComponent("profiles.yaml")
        vergeURL = directory.appendingPathComponent("verge.yaml")
        self.proxyController = proxyController
        hotkeyController = ClashVergeHotkeyController(configDirectory: directory)
        statusProvider = nil
        controlPollInterval = 0.1
        controlPollAttempts = 16
    }

    init(
        configDirectory: URL,
        proxyController: SystemProxyController = SystemProxyController(),
        hotkeyController: any ClashVergeHotkeyDispatching,
        statusProvider: @escaping () -> WidgetStatus,
        controlPollInterval: TimeInterval = 0,
        controlPollAttempts: Int = 8
    ) {
        self.configDirectory = configDirectory
        profilesURL = configDirectory.appendingPathComponent("profiles.yaml")
        vergeURL = configDirectory.appendingPathComponent("verge.yaml")
        self.proxyController = proxyController
        self.hotkeyController = hotkeyController
        self.statusProvider = statusProvider
        self.controlPollInterval = controlPollInterval
        self.controlPollAttempts = controlPollAttempts
    }

    public func currentStatus() -> WidgetStatus {
        if let statusProvider { return statusProvider() }
        do {
            let client = try MihomoClient()
            let runtime = try client.fetchRuntime()
            let sampleStart = Date()
            Thread.sleep(forTimeInterval: 0.25)
            let latest = try? client.fetchConnectionTotals()
            let sampleEnd = Date()
            let elapsed = max(sampleEnd.timeIntervalSince(sampleStart), 0.001)
            let uploadTotal = latest?.upload ?? runtime.uploadTotal
            let downloadTotal = latest?.download ?? runtime.downloadTotal
            let connections = latest?.count ?? runtime.connections
            let uploadRate = Int64(Double(max(0, uploadTotal - runtime.uploadTotal)) / elapsed)
            let downloadRate = Int64(Double(max(0, downloadTotal - runtime.downloadTotal)) / elapsed)
            let profile = readProfileName()
            let systemProxy = proxyController.snapshot()
            let vergeText = try? String(contentsOf: vergeURL, encoding: .utf8)
            let proxyHost = vergeText.flatMap {
                VergeConfigParser.scalarValue(for: "proxy_host", in: $0)
            }.flatMap { $0.isEmpty ? nil : $0 } ?? "127.0.0.1"
            let usesPAC = vergeText.flatMap {
                VergeConfigParser.scalarValue(for: "proxy_auto_config", in: $0)
            }.map(Self.boolValue) ?? false
            let systemProxyEnabled = usesPAC
                ? systemProxy.matchesClashPAC()
                : systemProxy.matches(host: proxyHost, port: runtime.mixedPort)
            return WidgetStatus(
                online: true,
                tunEnabled: runtime.tunEnabled,
                systemProxyEnabled: systemProxyEnabled,
                mode: runtime.mode,
                selectedProxy: Self.cleanProxyName(runtime.selectedProxy),
                profileName: profile,
                uploadRate: uploadRate,
                downloadRate: downloadRate,
                uploadTotal: uploadTotal,
                downloadTotal: downloadTotal,
                activeConnections: connections,
                mixedPort: runtime.mixedPort,
                timestamp: sampleEnd.timeIntervalSince1970
            )
        } catch {
            return .offline(error.localizedDescription)
        }
    }

    public func setMode(_ mode: String) throws -> WidgetStatus {
        let normalized = mode.lowercased()
        let action: ClashVergeHotkeyAction
        switch normalized {
        case "rule": action = .rule
        case "global": action = .global
        case "direct": action = .direct
        default: throw ClashVergeControlError.invalidMode(mode)
        }

        let current = try requireOnlineStatus()
        if current.mode.caseInsensitiveCompare(normalized) == .orderedSame { return current }
        try hotkeyController.trigger(action)
        return try waitForStatus("\(Self.modeLabel(normalized))模式") {
            $0.mode.caseInsensitiveCompare(normalized) == .orderedSame
        }
    }

    public func toggleSystemProxy() throws -> WidgetStatus {
        let current = try requireOnlineStatus()
        let expected = !(readVergeBool("enable_system_proxy") ?? current.systemProxyEnabled)
        try hotkeyController.trigger(.systemProxy)
        return try waitForStatus(expected ? "开启系统代理" : "关闭系统代理") {
            $0.systemProxyEnabled == expected && (self.readVergeBool("enable_system_proxy") ?? expected) == expected
        }
    }

    public func toggleTun() throws -> WidgetStatus {
        let current = try requireOnlineStatus()
        let expected = !current.tunEnabled
        try hotkeyController.trigger(.tun)
        return try waitForStatus(expected ? "开启 TUN" : "关闭 TUN") {
            $0.tunEnabled == expected
        }
    }

    public func openClashVerge() throws {
        let result = try ProcessRunner.run(
            "/usr/bin/open",
            ["-b", "io.github.clash-verge-rev.clash-verge-rev"]
        )
        guard result.succeeded else {
            throw ProcessRunnerError.failed(
                command: "open Clash Verge",
                status: result.status,
                message: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private func readProfileName() -> String {
        guard let text = try? String(contentsOf: profilesURL, encoding: .utf8) else {
            return "Clash Verge"
        }
        return VergeConfigParser.currentProfileName(in: text)
            .flatMap { $0.isEmpty ? nil : $0 } ?? "Clash Verge"
    }

    private func readVergeBool(_ key: String) -> Bool? {
        guard let text = try? String(contentsOf: vergeURL, encoding: .utf8),
              let value = VergeConfigParser.scalarValue(for: key, in: text)
        else { return nil }
        return Self.boolValue(value)
    }

    private static func boolValue(_ value: String) -> Bool {
        ["true", "yes", "on", "1"].contains(value.lowercased())
    }

    private func requireOnlineStatus() throws -> WidgetStatus {
        let status = currentStatus()
        guard status.online else {
            throw ClashVergeControlError.clashUnavailable(status.message ?? "Clash Verge 未运行")
        }
        return status
    }

    private func waitForStatus(
        _ expectedDescription: String,
        predicate: (WidgetStatus) -> Bool
    ) throws -> WidgetStatus {
        for _ in 0..<max(1, controlPollAttempts) {
            if controlPollInterval > 0 {
                Thread.sleep(forTimeInterval: controlPollInterval)
            }
            let status = currentStatus()
            if status.online, predicate(status) { return status }
        }
        throw ClashVergeControlError.stateDidNotChange(expectedDescription)
    }

    private static func modeLabel(_ mode: String) -> String {
        switch mode {
        case "rule": "规则"
        case "global": "全局"
        case "direct": "直连"
        default: mode
        }
    }

    static func cleanProxyName(_ name: String) -> String {
        name
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " · ")
    }
}

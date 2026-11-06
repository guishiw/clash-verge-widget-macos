import Darwin
import Foundation

public enum BridgeConfig {
    public static let host = "127.0.0.1"
    public static let token = GeneratedBridgeSecret.token
    public static let widgetKind = "com.local.ClashVergeWidget.Status"

    // Keep simultaneous login sessions on distinct loopback ports.
    public static var port: UInt16 {
        let offset = (UInt64(geteuid()) * 7_919) % 20_000
        return UInt16(40_000 + offset)
    }

    public static var baseURL: URL {
        URL(string: "http://\(host):\(port)")!
    }
}

public struct WidgetStatus: Codable, Equatable, Sendable {
    public var online: Bool
    public var tunEnabled: Bool
    public var systemProxyEnabled: Bool
    public var mode: String
    public var selectedProxy: String
    public var profileName: String
    public var uploadRate: Int64
    public var downloadRate: Int64
    public var uploadTotal: Int64
    public var downloadTotal: Int64
    public var activeConnections: Int
    public var mixedPort: Int
    public var timestamp: Double
    public var message: String?

    public init(
        online: Bool,
        tunEnabled: Bool,
        systemProxyEnabled: Bool,
        mode: String,
        selectedProxy: String,
        profileName: String,
        uploadRate: Int64,
        downloadRate: Int64,
        uploadTotal: Int64,
        downloadTotal: Int64,
        activeConnections: Int,
        mixedPort: Int,
        timestamp: Double = Date().timeIntervalSince1970,
        message: String? = nil
    ) {
        self.online = online
        self.tunEnabled = tunEnabled
        self.systemProxyEnabled = systemProxyEnabled
        self.mode = mode
        self.selectedProxy = selectedProxy
        self.profileName = profileName
        self.uploadRate = uploadRate
        self.downloadRate = downloadRate
        self.uploadTotal = uploadTotal
        self.downloadTotal = downloadTotal
        self.activeConnections = activeConnections
        self.mixedPort = mixedPort
        self.timestamp = timestamp
        self.message = message
    }

    public static let placeholder = WidgetStatus(
        online: true,
        tunEnabled: true,
        systemProxyEnabled: false,
        mode: "rule",
        selectedProxy: "新加坡 · Lightsail",
        profileName: "Clash Verge",
        uploadRate: 128 * 1_024,
        downloadRate: 3 * 1_024 * 1_024,
        uploadTotal: 1_024 * 1_024 * 1_024,
        downloadTotal: 8 * 1_024 * 1_024 * 1_024,
        activeConnections: 18,
        mixedPort: 7_897
    )

    public static func offline(_ message: String = "Clash Verge 未运行") -> WidgetStatus {
        WidgetStatus(
            online: false,
            tunEnabled: false,
            systemProxyEnabled: false,
            mode: "rule",
            selectedProxy: "—",
            profileName: "Clash Verge",
            uploadRate: 0,
            downloadRate: 0,
            uploadTotal: 0,
            downloadTotal: 0,
            activeConnections: 0,
            mixedPort: 0,
            message: message
        )
    }
}

public struct ActionResponse: Codable, Sendable {
    public let ok: Bool
    public let message: String
    public let status: WidgetStatus?

    public init(ok: Bool, message: String, status: WidgetStatus? = nil) {
        self.ok = ok
        self.message = message
        self.status = status
    }
}

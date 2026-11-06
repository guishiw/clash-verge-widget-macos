import Foundation

enum WidgetBridgeError: LocalizedError {
    case invalidResponse
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "小组件辅助服务响应无效"
        case let .rejected(message): message
        }
    }
}

struct WidgetBridgeClient: Sendable {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 4
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    func status() async throws -> WidgetStatus {
        let data = try await request(path: "/v1/status", method: "GET", body: nil)
        return try JSONDecoder().decode(WidgetStatus.self, from: data)
    }

    private func request(path: String, method: String, body: Data?) async throws -> Data {
        var request = URLRequest(url: BridgeConfig.baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.httpBody = body
        request.setValue(BridgeConfig.token, forHTTPHeaderField: "X-Widget-Token")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WidgetBridgeError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ActionResponse.self, from: data).message)
                ?? "操作失败（\(http.statusCode)）"
            throw WidgetBridgeError.rejected(message)
        }
        return data
    }
}

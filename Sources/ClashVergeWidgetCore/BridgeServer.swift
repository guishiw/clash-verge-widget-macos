import Foundation
@preconcurrency import Network

public struct BridgeHTTPRequest: Equatable, Sendable {
    public let method: String
    public let path: String
    public let headers: [String: String]
    public let body: Data

    public init(method: String, path: String, headers: [String: String], body: Data) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }

    public static func parse(_ data: Data) -> BridgeHTTPRequest? {
        let separator = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: separator),
              let headerText = String(data: data[..<range.lowerBound], encoding: .utf8)
        else { return nil }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let pair = line.split(separator: ":", maxSplits: 1)
            guard pair.count == 2 else { continue }
            headers[String(pair[0]).lowercased()] =
                String(pair[1]).trimmingCharacters(in: .whitespaces)
        }
        guard let expected = Int(headers["content-length"] ?? "0"),
              expected >= 0,
              expected <= 1_048_576
        else { return nil }
        let body = Data(data[range.upperBound...])
        guard body.count >= expected else { return nil }
        return BridgeHTTPRequest(
            method: String(parts[0]).uppercased(),
            path: String(parts[1]),
            headers: headers,
            body: Data(body.prefix(expected))
        )
    }
}

public struct BridgeHTTPResponse: Equatable, Sendable {
    public let status: Int
    public let reason: String
    public let contentType: String
    public let body: Data

    public init(status: Int, reason: String, contentType: String = "application/json", body: Data) {
        self.status = status
        self.reason = reason
        self.contentType = contentType
        self.body = body
    }

    public var serialized: Data {
        var header = "HTTP/1.1 \(status) \(reason)\r\n"
        header += "Content-Type: \(contentType); charset=utf-8\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Cache-Control: no-store\r\n"
        header += "Connection: close\r\n\r\n"
        var data = Data(header.utf8)
        data.append(body)
        return data
    }
}

public final class BridgeRouter: @unchecked Sendable {
    private let coordinator: StatusCoordinator
    private let encoder = JSONEncoder()

    public init(coordinator: StatusCoordinator) {
        self.coordinator = coordinator
        encoder.outputFormatting = [.sortedKeys]
    }

    public func route(_ request: BridgeHTTPRequest) -> BridgeHTTPResponse {
        guard request.headers["x-widget-token"] == BridgeConfig.token else {
            return response(status: 403, reason: "Forbidden", action: .init(ok: false, message: "未授权"))
        }
        guard request.method != "OPTIONS" else {
            return response(status: 405, reason: "Method Not Allowed", action: .init(ok: false, message: "不支持浏览器跨域请求"))
        }

        switch (request.method, request.path) {
        case ("GET", "/v1/health"):
            return response(status: 200, reason: "OK", action: .init(ok: true, message: "ok"))
        case ("GET", "/v1/status"):
            return json(status: 200, reason: "OK", value: coordinator.currentStatus())
        default:
            return response(status: 404, reason: "Not Found", action: .init(ok: false, message: "接口不存在"))
        }
    }

    private func response(status: Int, reason: String, action: ActionResponse) -> BridgeHTTPResponse {
        json(status: status, reason: reason, value: action)
    }

    private func json<T: Encodable>(status: Int, reason: String, value: T) -> BridgeHTTPResponse {
        let body = (try? encoder.encode(value)) ?? Data("{\"ok\":false}".utf8)
        return BridgeHTTPResponse(status: status, reason: reason, body: body)
    }
}

public final class BridgeServer: @unchecked Sendable {
    private let listener: NWListener
    private let router: BridgeRouter
    private let queue = DispatchQueue(label: "com.local.ClashVergeWidget.bridge", qos: .userInitiated)

    public init(router: BridgeRouter) throws {
        self.router = router
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(
            host: NWEndpoint.Host(BridgeConfig.host),
            port: NWEndpoint.Port(rawValue: BridgeConfig.port)!
        )
        listener = try NWListener(using: parameters)
    }

    public func start() {
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.stateUpdateHandler = { state in
            if case let .failed(error) = state {
                FileHandle.standardError.write(Data("Bridge listener failed: \(error)\n".utf8))
                exit(1)
            }
        }
        listener.start(queue: queue)
    }

    public func cancel() {
        listener.cancel()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, accumulated: Data())
    }

    private func receive(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1_024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var combined = accumulated
            if let data { combined.append(data) }
            if let request = BridgeHTTPRequest.parse(combined) {
                let response = router.route(request).serialized
                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }
            if error != nil || isComplete || combined.count > 1_048_576 {
                connection.cancel()
                return
            }
            receive(on: connection, accumulated: combined)
        }
    }
}

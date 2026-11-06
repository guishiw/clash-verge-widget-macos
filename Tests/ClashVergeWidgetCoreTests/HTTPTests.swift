import Foundation
import Testing
@testable import ClashVergeWidgetCore

@Suite("Local bridge HTTP")
struct HTTPTests {
    @Test("Parses an authenticated JSON request")
    func parsesRequest() throws {
        let body = Data("{\"enabled\":true}".utf8)
        let raw = Data(
            "POST /v1/test HTTP/1.1\r\nX-Widget-Token: \(BridgeConfig.token)\r\nContent-Length: \(body.count)\r\n\r\n".utf8
        ) + body
        let request = try #require(BridgeHTTPRequest.parse(raw))
        #expect(request.method == "POST")
        #expect(request.path == "/v1/test")
        #expect(request.headers["x-widget-token"] == BridgeConfig.token)
        #expect(request.body == body)
    }

    @Test("Rejects incomplete request bodies")
    func rejectsIncompleteBody() {
        let raw = Data("POST / HTTP/1.1\r\nContent-Length: 9\r\n\r\n{}".utf8)
        #expect(BridgeHTTPRequest.parse(raw) == nil)
    }

    @Test("Rejects negative or oversized content lengths")
    func rejectsInvalidLengths() {
        let negative = Data("POST / HTTP/1.1\r\nContent-Length: -1\r\n\r\n".utf8)
        let oversized = Data("POST / HTTP/1.1\r\nContent-Length: 1048577\r\n\r\n".utf8)
        #expect(BridgeHTTPRequest.parse(negative) == nil)
        #expect(BridgeHTTPRequest.parse(oversized) == nil)
    }

    @Test("Parses a Mihomo response")
    func parsesMihomoResponse() throws {
        let body = Data("{\"mode\":\"rule\"}".utf8)
        let raw = Data("HTTP/1.1 200 OK\r\nContent-Length: \(body.count)\r\n\r\n".utf8) + body
        #expect(try MihomoClient.parseHTTPResponse(raw) == body)
    }

    @Test("Decodes chunked Mihomo responses")
    func parsesChunkedResponse() throws {
        let chunks = Data("4\r\n{\"ok\r\n7\r\n\":true}\r\n0\r\n\r\n".utf8)
        let raw = Data("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n".utf8) + chunks
        #expect(try MihomoClient.parseHTTPResponse(raw) == Data("{\"ok\":true}".utf8))
    }

    @Test("Rejects malformed chunk headers without trapping")
    func rejectsMalformedChunks() {
        let raw = Data("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n\r\n".utf8)
        #expect(throws: MihomoError.self) {
            try MihomoClient.parseHTTPResponse(raw)
        }
    }

    @Test("Resolves custom selector group names to the active node")
    func resolvesCustomProxyGroup() {
        let response: [String: Any] = [
            "proxies": [
                "GLOBAL": ["type": "Selector", "now": "🚀 节点选择"],
                "🚀 节点选择": ["type": "Selector", "now": "Singapore-A"],
                "Singapore-A": ["type": "VLESS"],
            ] as [String: Any],
        ]
        #expect(MihomoClient.selectedProxy(from: response, mode: "rule") == "Singapore-A")
        #expect(MihomoClient.selectedProxy(from: response, mode: "global") == "Singapore-A")
        #expect(MihomoClient.selectedProxy(from: response, mode: "direct") == "DIRECT")
    }
}

import Testing
@testable import ClashVergeWidgetCore

@Suite("System proxy state parsing")
struct SystemProxyTests {
    @Test("Parses scutil dictionary output")
    func parsesScutil() {
        let text = """
        <dictionary> {
          HTTPEnable : 1
          HTTPPort : 7897
          HTTPProxy : 127.0.0.1
          SOCKSEnable : 0
        }
        """
        let parsed = SystemProxyController.dictionary(fromScutilOutput: text)
        #expect(parsed["HTTPEnable"] == "1")
        #expect(parsed["HTTPPort"] == "7897")
        #expect(parsed["HTTPProxy"] == "127.0.0.1")
    }

    @Test("Only treats the configured endpoint as Clash-owned")
    func matchesOwnedEndpoint() {
        let live = SystemProxySnapshot(enabled: true, host: "127.0.0.1", port: 7_897)
        #expect(live.matches(host: "127.0.0.1", port: 7_897))
        #expect(!live.matches(host: "127.0.0.1", port: 1_080))
        #expect(!SystemProxySnapshot(enabled: false).matches(host: "127.0.0.1", port: 7_897))
    }

    @Test("Ignores stale disabled endpoints and protects PAC")
    func handlesProtocolFlags() {
        let snapshot = SystemProxyController.snapshot(fromScutilOutput: """
          HTTPEnable : 1
          HTTPProxy : 10.0.0.2
          HTTPPort : 8080
          SOCKSEnable : 0
          SOCKSProxy : 127.0.0.1
          SOCKSPort : 7897
          ProxyAutoConfigEnable : 0
        """)
        #expect(snapshot.host == "10.0.0.2")
        #expect(snapshot.port == 8_080)
        #expect(!snapshot.matches(host: "127.0.0.1", port: 7_897))
        let pac = SystemProxyController.snapshot(fromScutilOutput: """
          HTTPEnable : 0
          ProxyAutoConfigEnable : 1
          ProxyAutoConfigURLString : http://127.0.0.1:62991/commands/pac
        """)
        #expect(!pac.matches(host: "127.0.0.1", port: 7_897))
        #expect(pac.matchesClashPAC())
        let foreignPAC = SystemProxySnapshot(
            enabled: true,
            pacEnabled: true,
            pacURL: "http://example.test/proxy.pac"
        )
        #expect(!foreignPAC.matchesClashPAC())
    }
}

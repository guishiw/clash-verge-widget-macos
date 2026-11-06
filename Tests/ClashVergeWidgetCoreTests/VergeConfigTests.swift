import Foundation
import Testing
@testable import ClashVergeWidgetCore

@Suite("Verge configuration parsing")
struct VergeConfigTests {
    @Test("Parses and unquotes top-level scalar values")
    func parsesScalarValues() {
        let text = """
        proxy_host: '127.0.0.1'
        optional_value: null
        """
        #expect(VergeConfigParser.scalarValue(for: "proxy_host", in: text) == "127.0.0.1")
        #expect(VergeConfigParser.scalarValue(for: "optional_value", in: text) == "")
    }

    @Test("Extracts the current profile name")
    func profileName() {
        let text = """
        current: selected-id
        items:
        - uid: first
          name: First
        - uid: selected-id
          type: local
          name: Home Profile.yaml
          selected:
          - name: PROXY
            now: Singapore
        """
        #expect(VergeConfigParser.currentProfileName(in: text) == "Home Profile.yaml")
    }
}

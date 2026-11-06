import CoreGraphics
import Foundation
import Testing
@testable import ClashVergeWidgetCore

@Suite("Clash Verge hotkey control")
struct HotkeyControlTests {
    @Test("Parses configured function keys, modifiers and ordinary keys")
    func parsesHotkeys() throws {
        let yaml = """
        hotkeys:
        - clash_mode_rule,F13
        - 'clash_mode_global,CMD+OPTION+7'
        - toggle_system_proxy,CTRL+SHIFT+P
        enable_global_hotkey: true
        """

        let parsed = try ClashVergeHotkeyParser.hotkeys(in: yaml)
        #expect(parsed[.rule] == ParsedHotkey(keyCode: 105, modifierFlags: 0))
        #expect(parsed[.global] == ParsedHotkey(
            keyCode: 26,
            modifierFlags: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskAlternate.rawValue
        ))
        #expect(parsed[.systemProxy] == ParsedHotkey(
            keyCode: 35,
            modifierFlags: CGEventFlags.maskControl.rawValue | CGEventFlags.maskShift.rawValue
        ))
    }

    @Test("Maps the reserved F13 through F17 controls")
    func mapsReservedFunctionKeys() throws {
        let parsed = try ClashVergeHotkeyParser.hotkeys(in: """
        hotkeys:
        - clash_mode_rule,F13
        - clash_mode_global,F14
        - clash_mode_direct,F15
        - toggle_system_proxy,F16
        - toggle_tun_mode,F17
        """)
        #expect(parsed[.rule]?.keyCode == 105)
        #expect(parsed[.global]?.keyCode == 107)
        #expect(parsed[.direct]?.keyCode == 113)
        #expect(parsed[.systemProxy]?.keyCode == 106)
        #expect(parsed[.tun]?.keyCode == 64)
    }

    @Test("Rejects disabled, duplicate and unsupported hotkeys")
    func rejectsInvalidConfigurations() {
        #expect(throws: ClashVergeControlError.globalHotkeysDisabled) {
            try ClashVergeHotkeyParser.hotkeys(in: """
            hotkeys:
            - clash_mode_rule,F13
            enable_global_hotkey: false
            """)
        }
        #expect(throws: ClashVergeControlError.duplicateHotkey("clash_mode_rule")) {
            try ClashVergeHotkeyParser.hotkeys(in: """
            hotkeys:
            - clash_mode_rule,F13
            - clash_mode_rule,F14
            """)
        }
        #expect(throws: ClashVergeControlError.hotkeyConflict("F13")) {
            try ClashVergeHotkeyParser.hotkeys(in: """
            hotkeys:
            - clash_mode_rule,F13
            - clash_mode_global,F13
            """)
        }
        #expect(throws: ClashVergeControlError.hotkeyConflict("F13")) {
            try ClashVergeHotkeyParser.hotkeys(in: """
            hotkeys:
            - open_or_close_dashboard,F13
            - clash_mode_rule,F13
            """)
        }
        #expect(throws: ClashVergeControlError.unsupportedHotkey("HYPER+MEDIA_PLAY")) {
            try ClashVergeHotkeyParser.parseChord("HYPER+MEDIA_PLAY")
        }
        #expect(throws: ClashVergeControlError.malformedHotkey("F13+F14")) {
            try ClashVergeHotkeyParser.parseChord("F13+F14")
        }
    }

    @Test("Dispatches only the hotkey assigned to the requested function")
    func dispatchesConfiguredHotkey() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClashVergeWidgetHotkeys-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try """
        hotkeys:
        - clash_mode_rule,F13
        - toggle_tun_mode,CTRL+F17
        enable_global_hotkey: true
        """.write(to: directory.appendingPathComponent("verge.yaml"), atomically: true, encoding: .utf8)

        let poster = RecordingHotkeyPoster()
        let controller = ClashVergeHotkeyController(configDirectory: directory, eventPoster: poster)
        try controller.trigger(.tun)
        #expect(poster.posted == [ParsedHotkey(
            keyCode: 64,
            modifierFlags: CGEventFlags.maskControl.rawValue
        )])
        #expect(throws: ClashVergeControlError.hotkeyMissing("toggle_system_proxy")) {
            try controller.trigger(.systemProxy)
        }
    }

    @Test("Coordinator dispatches actions and verifies their actual postconditions")
    func coordinatorVerifiesChanges() throws {
        let state = StatusBox(status: makeStatus())
        let dispatcher = MutatingHotkeyDispatcher { action in
            switch action {
            case .rule: state.status.mode = "rule"
            case .global: state.status.mode = "global"
            case .direct: state.status.mode = "direct"
            case .systemProxy: state.status.systemProxyEnabled.toggle()
            case .tun: state.status.tunEnabled.toggle()
            }
        }
        let coordinator = StatusCoordinator(
            configDirectory: FileManager.default.temporaryDirectory,
            hotkeyController: dispatcher,
            statusProvider: { state.status }
        )

        #expect(try coordinator.setMode("global").mode == "global")
        #expect(try coordinator.toggleSystemProxy().systemProxyEnabled)
        #expect(try coordinator.toggleTun().tunEnabled)
        #expect(dispatcher.actions == [.global, .systemProxy, .tun])

        // Selecting the active mode is idempotent and must not synthesize another key press.
        #expect(try coordinator.setMode("global").mode == "global")
        #expect(dispatcher.actions == [.global, .systemProxy, .tun])
    }

    @Test("Coordinator reports offline and unobserved transitions")
    func coordinatorReportsFailures() {
        let offlineDispatcher = MutatingHotkeyDispatcher { _ in }
        let offline = StatusCoordinator(
            configDirectory: FileManager.default.temporaryDirectory,
            hotkeyController: offlineDispatcher,
            statusProvider: { .offline("Clash Verge 未运行") }
        )
        #expect(throws: ClashVergeControlError.clashUnavailable("Clash Verge 未运行")) {
            try offline.toggleTun()
        }
        #expect(offlineDispatcher.actions.isEmpty)

        let unchanged = StatusCoordinator(
            configDirectory: FileManager.default.temporaryDirectory,
            hotkeyController: MutatingHotkeyDispatcher { _ in },
            statusProvider: { makeStatus() },
            controlPollAttempts: 2
        )
        #expect(throws: ClashVergeControlError.stateDidNotChange("全局模式")) {
            try unchanged.setMode("global")
        }
    }
}

private final class RecordingHotkeyPoster: HotkeyEventPosting {
    var posted: [ParsedHotkey] = []

    func post(_ hotkey: ParsedHotkey) {
        posted.append(hotkey)
    }
}

private final class MutatingHotkeyDispatcher: ClashVergeHotkeyDispatching {
    private let mutation: (ClashVergeHotkeyAction) -> Void
    private(set) var actions: [ClashVergeHotkeyAction] = []

    init(mutation: @escaping (ClashVergeHotkeyAction) -> Void) {
        self.mutation = mutation
    }

    func trigger(_ action: ClashVergeHotkeyAction) {
        actions.append(action)
        mutation(action)
    }
}

private final class StatusBox {
    var status: WidgetStatus

    init(status: WidgetStatus) {
        self.status = status
    }
}

private func makeStatus(
    online: Bool = true,
    tun: Bool = false,
    systemProxy: Bool = false,
    mode: String = "rule"
) -> WidgetStatus {
    WidgetStatus(
        online: online,
        tunEnabled: tun,
        systemProxyEnabled: systemProxy,
        mode: mode,
        selectedProxy: "Test",
        profileName: "Test",
        uploadRate: 0,
        downloadRate: 0,
        uploadTotal: 0,
        downloadTotal: 0,
        activeConnections: 0,
        mixedPort: 7_897
    )
}

import Foundation
import Testing
@testable import ClashVergeWidgetCore

@Suite("Clash Verge accessibility control")
struct AccessibilityControlTests {
    @Test("Matches localized Clash Verge UI titles")
    func matchesLocalizedUITitles() {
        #expect(ClashVergeUITitles.titles(for: .rule).contains("规则"))
        #expect(ClashVergeUITitles.titles(for: .rule).contains("規則"))
        #expect(ClashVergeUITitles.titles(for: .global).contains("Global"))
        #expect(ClashVergeUITitles.titles(for: .systemProxy).contains("系統代理"))
        #expect(ClashVergeUITitles.titles(for: .tun).contains("虛擬網路介面卡模式"))
        #expect(ClashVergeUITitles.normalized("虛 擬 網 路") == "虛擬網路")
    }

    @Test("Dispatches control actions to the accessibility driver")
    func dispatchesAccessibilityActions() throws {
        let driver = RecordingAccessibilityDriver()
        let controller = ClashVergeAccessibilityController(driver: driver)
        try controller.trigger(.global)
        #expect(driver.actions == [.global])
    }

    @Test("Coordinator dispatches actions and verifies their actual postconditions")
    func coordinatorVerifiesChanges() throws {
        let state = StatusBox(status: makeStatus())
        let dispatcher = MutatingControlDispatcher { action in
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
            controlController: dispatcher,
            statusProvider: { state.status }
        )

        #expect(try coordinator.setMode("global").mode == "global")
        #expect(try coordinator.toggleSystemProxy().systemProxyEnabled)
        #expect(try coordinator.toggleTun().tunEnabled)
        #expect(dispatcher.actions == [.global, .systemProxy, .tun])

        #expect(try coordinator.setMode("global").mode == "global")
        #expect(dispatcher.actions == [.global, .systemProxy, .tun])
    }

    @Test("Coordinator reports offline and unobserved transitions")
    func coordinatorReportsFailures() {
        let offlineDispatcher = MutatingControlDispatcher { _ in }
        let offline = StatusCoordinator(
            configDirectory: FileManager.default.temporaryDirectory,
            controlController: offlineDispatcher,
            statusProvider: { .offline("Clash Verge 未运行") }
        )
        #expect(throws: ClashVergeControlError.clashUnavailable("Clash Verge 未运行")) {
            try offline.toggleTun()
        }
        #expect(offlineDispatcher.actions.isEmpty)

        let unchanged = StatusCoordinator(
            configDirectory: FileManager.default.temporaryDirectory,
            controlController: MutatingControlDispatcher { _ in },
            statusProvider: { makeStatus() },
            controlPollAttempts: 2
        )
        #expect(throws: ClashVergeControlError.stateDidNotChange("全局模式")) {
            try unchanged.setMode("global")
        }
    }
}

private final class RecordingAccessibilityDriver: ClashVergeAccessibilityDriving {
    private(set) var actions: [ClashVergeControlAction] = []

    func trigger(_ action: ClashVergeControlAction) {
        actions.append(action)
    }
}

private final class MutatingControlDispatcher: ClashVergeControlDispatching {
    private let mutation: (ClashVergeControlAction) -> Void
    private(set) var actions: [ClashVergeControlAction] = []

    init(mutation: @escaping (ClashVergeControlAction) -> Void) {
        self.mutation = mutation
    }

    func trigger(_ action: ClashVergeControlAction) {
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

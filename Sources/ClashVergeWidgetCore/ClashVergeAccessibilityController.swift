import AppKit
import ApplicationServices
import Foundation

enum ClashVergeControlAction: String, CaseIterable, Sendable {
    case rule
    case global
    case direct
    case systemProxy
    case tun
}

enum ClashVergeControlError: LocalizedError, Equatable {
    case invalidMode(String)
    case clashUnavailable(String)
    case configUnreadable
    case trayMenuModeRequired
    case accessibilityDenied
    case statusItemUnavailable
    case menuItemUnavailable(String)
    case accessibilityActionFailed(String)
    case stateDidNotChange(String)

    var errorDescription: String? {
        switch self {
        case let .invalidMode(mode):
            "不支持的代理模式：\(mode)"
        case let .clashUnavailable(message):
            message.isEmpty ? "Clash Verge 未运行" : message
        case .configUnreadable:
            "无法读取 Clash Verge 配置"
        case .trayMenuModeRequired:
            "请在 Clash Verge 的“设置 > Verge 基础设置 > 系统匣点击事件”中选择“显示系统匣菜单”"
        case .accessibilityDenied:
            "请在“系统设置 > 隐私与安全性 > 辅助功能”中允许 Clash Verge Widget，关闭并重新打开小组件后再试"
        case .statusItemUnavailable:
            "找不到 Clash Verge 状态栏图标；请确认 Clash Verge 正在运行"
        case let .menuItemUnavailable(item):
            "在 Clash Verge 状态栏菜单中找不到“\(item)”"
        case let .accessibilityActionFailed(item):
            "无法按下 Clash Verge 状态栏菜单中的“\(item)”"
        case let .stateDidNotChange(expected):
            "Clash Verge 未切换到\(expected)，请稍后重试"
        }
    }
}

protocol ClashVergeControlDispatching: AnyObject {
    func trigger(_ action: ClashVergeControlAction) throws
}

protocol ClashVergeAccessibilityDriving: AnyObject {
    func trigger(_ action: ClashVergeControlAction) throws
}

enum ClashVergeMenuTitles {
    static func titles(for action: ClashVergeControlAction) -> Set<String> {
        switch action {
        case .rule:
            ["规则模式", "規則模式", "Rule Mode"]
        case .global:
            ["全局模式", "全域模式", "Global Mode"]
        case .direct:
            ["直连模式", "直連模式", "Direct Mode"]
        case .systemProxy:
            ["系统代理", "系統代理", "System Proxy"]
        case .tun:
            ["TUN 模式", "虛擬網路介面卡模式", "TUN Mode"]
        }
    }

    static let outboundModePrefixes: Set<String> = ["出站模式", "Outbound Modes"]

    static func displayName(for action: ClashVergeControlAction) -> String {
        switch action {
        case .rule: "规则"
        case .global: "全局"
        case .direct: "直连"
        case .systemProxy: "系统代理"
        case .tun: "TUN"
        }
    }
}

final class ClashVergeAccessibilityController: ClashVergeControlDispatching {
    private let configURL: URL
    private let driver: any ClashVergeAccessibilityDriving

    init(
        configDirectory: URL,
        driver: any ClashVergeAccessibilityDriving = SystemClashVergeAccessibilityDriver()
    ) {
        configURL = configDirectory.appendingPathComponent("verge.yaml")
        self.driver = driver
    }

    func trigger(_ action: ClashVergeControlAction) throws {
        guard let yaml = try? String(contentsOf: configURL, encoding: .utf8) else {
            throw ClashVergeControlError.configUnreadable
        }
        guard VergeConfigParser.scalarValue(for: "tray_event", in: yaml) == "tray_menu" else {
            throw ClashVergeControlError.trayMenuModeRequired
        }
        try driver.trigger(action)
    }
}

final class SystemClashVergeAccessibilityDriver: ClashVergeAccessibilityDriving {
    private let bundleIdentifier: String
    private let menuOpenDelay: TimeInterval
    private let submenuOpenDelay: TimeInterval

    init(
        bundleIdentifier: String = "io.github.clash-verge-rev.clash-verge-rev",
        menuOpenDelay: TimeInterval = 0.38,
        submenuOpenDelay: TimeInterval = 0.12
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.menuOpenDelay = menuOpenDelay
        self.submenuOpenDelay = submenuOpenDelay
    }

    func trigger(_ action: ClashVergeControlAction) throws {
        guard isAccessibilityTrusted() else {
            throw ClashVergeControlError.accessibilityDenied
        }
        guard let runningApplication = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { !$0.isTerminated })
        else {
            throw ClashVergeControlError.clashUnavailable("Clash Verge 未运行")
        }

        let application = AXUIElementCreateApplication(runningApplication.processIdentifier)
        guard let extrasMenuBar = elementAttribute("AXExtrasMenuBar", of: application),
              let statusItem = children(of: extrasMenuBar).first(where: {
                  stringAttribute(kAXRoleAttribute, of: $0) == kAXMenuBarItemRole as String
              }) ?? children(of: extrasMenuBar).first
        else {
            throw ClashVergeControlError.statusItemUnavailable
        }

        let showResult = AXUIElementPerformAction(statusItem, kAXShowMenuAction as CFString)
        if showResult != .success {
            let pressResult = AXUIElementPerformAction(statusItem, kAXPressAction as CFString)
            guard pressResult == .success else {
                throw ClashVergeControlError.accessibilityActionFailed("状态栏菜单")
            }
        }

        // Clash Verge debounces tray clicks for 300 ms. Waiting past that window
        // ensures the following native menu callback is accepted.
        Thread.sleep(forTimeInterval: menuOpenDelay)

        let roots = [statusItem, extrasMenuBar]
        var item = findMenuItem(for: action, roots: roots)
        if item == nil,
           action == .rule || action == .global || action == .direct,
           let outboundModes = findOutboundModesItem(roots: roots) {
            let expandResult = AXUIElementPerformAction(outboundModes, kAXShowMenuAction as CFString)
            if expandResult != .success {
                _ = AXUIElementPerformAction(outboundModes, kAXPressAction as CFString)
            }
            Thread.sleep(forTimeInterval: submenuOpenDelay)
            item = findMenuItem(for: action, roots: roots)
        }

        guard let item else {
            dismissMenu(statusItem)
            throw ClashVergeControlError.menuItemUnavailable(ClashVergeMenuTitles.displayName(for: action))
        }
        guard AXUIElementPerformAction(item, kAXPressAction as CFString) == .success else {
            dismissMenu(statusItem)
            throw ClashVergeControlError.accessibilityActionFailed(ClashVergeMenuTitles.displayName(for: action))
        }
    }

    private func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    private func findMenuItem(
        for action: ClashVergeControlAction,
        roots: [AXUIElement]
    ) -> AXUIElement? {
        let acceptedTitles = ClashVergeMenuTitles.titles(for: action)
        return descendants(of: roots).first { element in
            stringAttribute(kAXRoleAttribute, of: element) == kAXMenuItemRole as String &&
                stringAttribute(kAXTitleAttribute, of: element).map(acceptedTitles.contains) == true
        }
    }

    private func findOutboundModesItem(roots: [AXUIElement]) -> AXUIElement? {
        descendants(of: roots).first { element in
            guard stringAttribute(kAXRoleAttribute, of: element) == kAXMenuItemRole as String,
                  let title = stringAttribute(kAXTitleAttribute, of: element)
            else { return false }
            return ClashVergeMenuTitles.outboundModePrefixes.contains { title.hasPrefix($0) }
        }
    }

    private func descendants(of roots: [AXUIElement]) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var queue = roots.map { ($0, 0) }
        var seen = Set<CFHashCode>()

        while !queue.isEmpty, result.count < 512 {
            let (element, depth) = queue.removeFirst()
            let identity = CFHash(element)
            guard seen.insert(identity).inserted else { continue }
            result.append(element)
            guard depth < 12 else { continue }

            var next = children(of: element)
            next.append(contentsOf: elementArrayAttribute(kAXVisibleChildrenAttribute, of: element))
            queue.append(contentsOf: next.map { ($0, depth + 1) })
        }
        return result
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        elementArrayAttribute(kAXChildrenAttribute, of: element)
    }

    private func elementArrayAttribute(_ attribute: String, of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let elements = value as? [AXUIElement]
        else { return [] }
        return elements
    }

    private func elementAttribute(_ attribute: String, of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func dismissMenu(_ statusItem: AXUIElement) {
        _ = AXUIElementPerformAction(statusItem, kAXCancelAction as CFString)
    }
}

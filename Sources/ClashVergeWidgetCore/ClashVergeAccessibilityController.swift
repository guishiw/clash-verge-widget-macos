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
    case accessibilityDenied
    case mainWindowUnavailable
    case controlUnavailable(String)
    case accessibilityActionFailed(String)
    case stateDidNotChange(String)

    var errorDescription: String? {
        switch self {
        case let .invalidMode(mode):
            "不支持的代理模式：\(mode)"
        case let .clashUnavailable(message):
            message.isEmpty ? "Clash Verge 未运行" : message
        case .accessibilityDenied:
            "请在“系统设置 > 隐私与安全性 > 辅助功能”中允许 Clash Verge Widget，关闭并重新打开小组件后再试"
        case .mainWindowUnavailable:
            "尚未连接到 Clash Verge 控制界面；请打开一次 Clash Verge 主界面，连接完成后可继续关闭窗口使用"
        case let .controlUnavailable(control):
            "在 Clash Verge 中找不到“\(control)”控制项"
        case let .accessibilityActionFailed(control):
            "无法操作 Clash Verge 的“\(control)”控制项"
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

enum ClashVergeUITitles {
    static let homeNavigation: Set<String> = ["首页", "首頁", "Home"]
    static let settingsNavigation: Set<String> = ["设置", "設定", "Settings"]

    static func titles(for action: ClashVergeControlAction) -> Set<String> {
        switch action {
        case .rule:
            ["规则", "規則", "Rule"]
        case .global:
            ["全局", "全域", "Global"]
        case .direct:
            ["直连", "直連", "Direct"]
        case .systemProxy:
            ["系统代理", "系統代理", "System Proxy"]
        case .tun:
            ["虚拟网络接口模式", "虛擬網路介面卡模式", "TUN Mode", "Tun Mode"]
        }
    }

    static func displayName(for action: ClashVergeControlAction) -> String {
        switch action {
        case .rule: "规则"
        case .global: "全局"
        case .direct: "直连"
        case .systemProxy: "系统代理"
        case .tun: "TUN"
        }
    }

    static func normalized(_ value: String) -> String {
        value
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00a0}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class ClashVergeAccessibilityController: ClashVergeControlDispatching {
    private let driver: any ClashVergeAccessibilityDriving

    init(driver: any ClashVergeAccessibilityDriving = SystemClashVergeAccessibilityDriver()) {
        self.driver = driver
    }

    func trigger(_ action: ClashVergeControlAction) throws {
        try driver.trigger(action)
    }
}

final class SystemClashVergeAccessibilityDriver: ClashVergeAccessibilityDriving {
    private let bundleIdentifier: String
    private let navigationDelay: TimeInterval
    private let cacheLock = NSLock()
    private var cachedProcessIdentifier: pid_t?
    private var cachedWebArea: AXUIElement?
    private let cacheRefreshTimer: DispatchSourceTimer

    init(
        bundleIdentifier: String = "io.github.clash-verge-rev.clash-verge-rev",
        navigationDelay: TimeInterval = 0.18
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.navigationDelay = navigationDelay
        let timer = DispatchSource.makeTimerSource(
            queue: DispatchQueue(label: "com.local.ClashVergeWidget.accessibility-cache", qos: .utility)
        )
        cacheRefreshTimer = timer
        timer.schedule(deadline: .now(), repeating: .milliseconds(750), leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            self?.refreshWebAreaCacheIfVisible()
        }
        timer.resume()
    }

    deinit {
        cacheRefreshTimer.setEventHandler {}
        cacheRefreshTimer.cancel()
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

        guard let webArea = webArea(for: runningApplication.processIdentifier) else {
            throw ClashVergeControlError.mainWindowUnavailable
        }

        switch action {
        case .rule, .global, .direct:
            try switchMode(action, in: webArea, processIdentifier: runningApplication.processIdentifier)
        case .systemProxy, .tun:
            try toggleSetting(action, in: webArea, processIdentifier: runningApplication.processIdentifier)
        }
    }

    private func refreshWebAreaCacheIfVisible() {
        guard isAccessibilityTrusted(prompt: false),
              let runningApplication = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleIdentifier)
                .first(where: { !$0.isTerminated })
        else { return }
        _ = discoverVisibleWebArea(processIdentifier: runningApplication.processIdentifier)
    }

    private func webArea(for processIdentifier: pid_t) -> AXUIElement? {
        cacheLock.lock()
        let cached = cachedProcessIdentifier == processIdentifier ? cachedWebArea : nil
        cacheLock.unlock()

        if let cached, stringAttribute(kAXRoleAttribute, of: cached) == "AXWebArea" {
            return cached
        }
        clearWebAreaCache()
        return discoverVisibleWebArea(processIdentifier: processIdentifier)
    }

    @discardableResult
    private func discoverVisibleWebArea(processIdentifier: pid_t) -> AXUIElement? {
        let application = AXUIElementCreateApplication(processIdentifier)
        let windows = elementArrayAttribute(kAXWindowsAttribute, of: application)
        guard !windows.isEmpty,
              let webArea = descendants(of: windows).first(where: {
                  stringAttribute(kAXRoleAttribute, of: $0) == "AXWebArea"
              })
        else { return nil }

        cacheLock.lock()
        cachedProcessIdentifier = processIdentifier
        cachedWebArea = webArea
        cacheLock.unlock()
        return webArea
    }

    private func clearWebAreaCache() {
        cacheLock.lock()
        cachedProcessIdentifier = nil
        cachedWebArea = nil
        cacheLock.unlock()
    }

    private func switchMode(
        _ action: ClashVergeControlAction,
        in window: AXUIElement,
        processIdentifier: pid_t
    ) throws {
        try navigate(to: ClashVergeUITitles.homeNavigation, in: window, processIdentifier: processIdentifier)
        let accepted = normalizedTitles(ClashVergeUITitles.titles(for: action))
        guard let control = descendants(of: [window]).first(where: { element in
            guard stringAttribute(kAXRoleAttribute, of: element) != kAXButtonRole as String,
                  let text = elementText(element)
            else { return false }
            return accepted.contains(ClashVergeUITitles.normalized(text))
        }) else {
            throw ClashVergeControlError.controlUnavailable(ClashVergeUITitles.displayName(for: action))
        }
        guard pressOrClick(control, processIdentifier: processIdentifier) else {
            throw ClashVergeControlError.accessibilityActionFailed(ClashVergeUITitles.displayName(for: action))
        }
    }

    private func toggleSetting(
        _ action: ClashVergeControlAction,
        in window: AXUIElement,
        processIdentifier: pid_t
    ) throws {
        try navigate(to: ClashVergeUITitles.settingsNavigation, in: window, processIdentifier: processIdentifier)
        let elements = descendants(of: [window])
        let acceptedLabels = normalizedTitles(ClashVergeUITitles.titles(for: action))
        guard let labelIndex = elements.firstIndex(where: { element in
            guard let text = elementText(element) else { return false }
            return acceptedLabels.contains(ClashVergeUITitles.normalized(text))
        }),
        let control = elements.dropFirst(labelIndex + 1).prefix(12).first(where: isSwitch)
        else {
            throw ClashVergeControlError.controlUnavailable(ClashVergeUITitles.displayName(for: action))
        }
        guard pressOrClick(control, processIdentifier: processIdentifier) else {
            throw ClashVergeControlError.accessibilityActionFailed(ClashVergeUITitles.displayName(for: action))
        }
    }

    private func navigate(
        to titles: Set<String>,
        in window: AXUIElement,
        processIdentifier: pid_t
    ) throws {
        let accepted = normalizedTitles(titles)
        guard let button = descendants(of: [window]).first(where: { element in
            guard stringAttribute(kAXRoleAttribute, of: element) == kAXButtonRole as String,
                  let text = elementText(element)
            else { return false }
            return accepted.contains(ClashVergeUITitles.normalized(text))
        }) else {
            throw ClashVergeControlError.controlUnavailable(titles.first ?? "导航")
        }
        guard pressOrClick(button, processIdentifier: processIdentifier) else {
            throw ClashVergeControlError.accessibilityActionFailed(titles.first ?? "导航")
        }
        Thread.sleep(forTimeInterval: navigationDelay)
    }

    private func pressOrClick(_ element: AXUIElement, processIdentifier: pid_t) -> Bool {
        if AXUIElementPerformAction(element, kAXPressAction as CFString) == .success {
            return true
        }
        return postTargetedClick(element, processIdentifier: processIdentifier)
    }

    private func postTargetedClick(_ element: AXUIElement, processIdentifier: pid_t) -> Bool {
        guard let position = pointAttribute(kAXPositionAttribute, of: element),
              let size = sizeAttribute(kAXSizeAttribute, of: element),
              size.width > 0,
              size.height > 0,
              let source = CGEventSource(stateID: .hidSystemState),
              let mouseDown = CGEvent(
                  mouseEventSource: source,
                  mouseType: .leftMouseDown,
                  mouseCursorPosition: CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2),
                  mouseButton: .left
              ),
              let mouseUp = CGEvent(
                  mouseEventSource: source,
                  mouseType: .leftMouseUp,
                  mouseCursorPosition: CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2),
                  mouseButton: .left
              )
        else { return false }

        mouseDown.postToPid(processIdentifier)
        Thread.sleep(forTimeInterval: 0.025)
        mouseUp.postToPid(processIdentifier)
        return true
    }

    private func isSwitch(_ element: AXUIElement) -> Bool {
        let role = stringAttribute(kAXRoleAttribute, of: element)
        let subrole = stringAttribute(kAXSubroleAttribute, of: element)
        return role == kAXCheckBoxRole as String || role == "AXSwitch" || subrole == "AXSwitch"
    }

    private func normalizedTitles(_ titles: Set<String>) -> Set<String> {
        Set(titles.map(ClashVergeUITitles.normalized))
    }

    private func elementText(_ element: AXUIElement) -> String? {
        [
            stringAttribute(kAXTitleAttribute, of: element),
            stringAttribute(kAXValueAttribute, of: element),
            stringAttribute(kAXDescriptionAttribute, of: element),
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first(where: { !$0.isEmpty })
    }

    private func isAccessibilityTrusted(prompt: Bool = true) -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": prompt] as CFDictionary)
    }

    private func descendants(of roots: [AXUIElement]) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var queue = roots.map { ($0, 0) }
        var seen = Set<CFHashCode>()

        while !queue.isEmpty, result.count < 800 {
            let (element, depth) = queue.removeFirst()
            let identity = CFHash(element)
            guard seen.insert(identity).inserted else { continue }
            result.append(element)
            guard depth < 16 else { continue }
            queue.append(contentsOf: elementArrayAttribute(kAXChildrenAttribute, of: element).map {
                ($0, depth + 1)
            })
        }
        return result
    }

    private func elementArrayAttribute(_ attribute: String, of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let elements = value as? [AXUIElement]
        else { return [] }
        return elements
    }

    private func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func pointAttribute(_ attribute: String, of element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value
        else { return nil }
        let axValue = (value as! AXValue)
        guard AXValueGetType(axValue) == .cgPoint else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func sizeAttribute(_ attribute: String, of element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value
        else { return nil }
        let axValue = (value as! AXValue)
        guard AXValueGetType(axValue) == .cgSize else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }
}

import AppKit
import ClashVergeWidgetCore
import CoreGraphics
import SwiftUI

@MainActor
final class DesktopPanelController {
    private let panel: DesktopStatusPanel
    private let model: DesktopStatusModel

    init(coordinator: StatusCoordinator) {
        model = DesktopStatusModel(coordinator: coordinator)
        let size = NSSize(width: 344, height: 164)
        panel = DesktopStatusPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.title = "Clash Verge Widget"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        // Notification Center desktop widgets sit two levels above the desktop icon window.
        // Matching that level keeps Finder from intercepting clicks intended for this card.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 2)
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary,
        ]

        let hostingView = FirstMouseHostingView(rootView: DesktopStatusCard(model: model))
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 18
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true
        panel.contentView = hostingView
        panel.setFrameOrigin(Self.savedOrDefaultOrigin(for: size))
        panel.shouldPersistPosition = true
    }

    func show() {
        panel.orderFrontRegardless()
        model.start()
    }

    func close() {
        model.stop()
        panel.orderOut(nil)
    }

    private static func savedOrDefaultOrigin(for size: NSSize) -> NSPoint {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: DesktopStatusPanel.originXKey) != nil,
           defaults.object(forKey: DesktopStatusPanel.originYKey) != nil {
            let saved = NSPoint(
                x: defaults.double(forKey: DesktopStatusPanel.originXKey),
                y: defaults.double(forKey: DesktopStatusPanel.originYKey)
            )
            let savedFrame = NSRect(origin: saved, size: size)
            if NSScreen.screens.contains(where: { $0.frame.intersection(savedFrame).area >= size.width * size.height * 0.5 }) {
                return saved
            }
        }

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return NSPoint(x: 8, y: 568) }
        let rowGap: CGFloat = 8
        let thirdRow = screen.frame.maxY - 8 - size.height - (size.height + rowGap) * 2
        return NSPoint(
            x: screen.frame.minX + 8,
            y: max(screen.frame.minY + 8, thirdRow)
        )
    }
}

@MainActor
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
private final class DesktopStatusPanel: NSPanel {
    static let originXKey = "DesktopWidgetOriginX"
    static let originYKey = "DesktopWidgetOriginY"
    var shouldPersistPosition = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        let dragRegion = NSRect(x: 0, y: 108, width: 294, height: 56)
        if event.type == .leftMouseDown, dragRegion.contains(event.locationInWindow) {
            trackDrag()
            return
        }
        super.sendEvent(event)
    }

    private func trackDrag() {
        let startMouse = NSEvent.mouseLocation
        let startOrigin = frame.origin
        NSCursor.closedHand.push()
        defer { NSCursor.pop() }

        while let event = NSApplication.shared.nextEvent(
            matching: [.leftMouseDragged, .leftMouseUp],
            until: .distantFuture,
            inMode: .eventTracking,
            dequeue: true
        ) {
            if event.type == .leftMouseUp { return }
            let current = NSEvent.mouseLocation
            setFrameOrigin(NSPoint(
                x: startOrigin.x + current.x - startMouse.x,
                y: startOrigin.y + current.y - startMouse.y
            ))
        }
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var safeFrame = frameRect
        safeFrame.origin = Self.clampedOrigin(frameRect.origin, size: frameRect.size)
        super.setFrame(safeFrame, display: flag)
        persistOriginIfNeeded(safeFrame.origin)
    }

    override func setFrameOrigin(_ point: NSPoint) {
        let safePoint = Self.clampedOrigin(point, size: frame.size)
        super.setFrameOrigin(safePoint)
        persistOriginIfNeeded(safePoint)
    }

    private static func clampedOrigin(_ point: NSPoint, size: NSSize) -> NSPoint {
        let proposed = NSRect(origin: point, size: size)
        let screens = NSScreen.screens
        guard let screen = screens.max(by: {
            $0.frame.intersection(proposed).area < $1.frame.intersection(proposed).area
        }) ?? NSScreen.main else { return point }
        return NSPoint(
            x: min(max(point.x, screen.frame.minX), max(screen.frame.minX, screen.frame.maxX - size.width)),
            y: min(max(point.y, screen.frame.minY), max(screen.frame.minY, screen.frame.maxY - size.height))
        )
    }

    private func persistOriginIfNeeded(_ origin: NSPoint) {
        guard shouldPersistPosition else { return }
        UserDefaults.standard.set(origin.x, forKey: Self.originXKey)
        UserDefaults.standard.set(origin.y, forKey: Self.originYKey)
    }
}

private extension NSRect {
    var area: CGFloat { max(0, width) * max(0, height) }
}

private enum DesktopControl: Equatable, Sendable {
    case mode(String)
    case systemProxy
    case tun

    var progressMessage: String {
        switch self {
        case let .mode(mode): "正在切换到\(Self.modeTitle(mode))…"
        case .systemProxy: "正在切换系统代理…"
        case .tun: "正在切换 TUN…"
        }
    }

    func successMessage(status: WidgetStatus) -> String {
        switch self {
        case let .mode(mode): "已切换到\(Self.modeTitle(mode))"
        case .systemProxy: "系统代理已\(status.systemProxyEnabled ? "开启" : "关闭")"
        case .tun: "TUN 已\(status.tunEnabled ? "开启" : "关闭")"
        }
    }

    func execute(with coordinator: StatusCoordinator) throws -> WidgetStatus {
        switch self {
        case let .mode(mode): try coordinator.setMode(mode)
        case .systemProxy: try coordinator.toggleSystemProxy()
        case .tun: try coordinator.toggleTun()
        }
    }

    private static func modeTitle(_ mode: String) -> String {
        switch mode {
        case "global": "全局模式"
        case "direct": "直连模式"
        default: "规则模式"
        }
    }
}

private struct DesktopActionNotice: Sendable {
    let text: String
    let isError: Bool
}

private enum DesktopControlOutcome: Sendable {
    case success(WidgetStatus)
    case failure(status: WidgetStatus, message: String)
}

@MainActor
private final class DesktopStatusModel: ObservableObject {
    @Published private(set) var status = WidgetStatus.offline("正在连接 Clash Verge…")
    @Published private(set) var activeControl: DesktopControl?
    @Published private(set) var actionNotice: DesktopActionNotice?

    private let coordinator: StatusCoordinator
    private var refreshLoop: Task<Void, Never>?
    private var controlTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?

    init(coordinator: StatusCoordinator) {
        self.coordinator = coordinator
    }

    func start() {
        guard refreshLoop == nil else { return }
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let coordinator = self.coordinator
                let freshStatus = await Task.detached(priority: .utility) {
                    coordinator.currentStatus()
                }.value
                guard !Task.isCancelled else { return }
                self.status = freshStatus
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stop() {
        refreshLoop?.cancel()
        refreshLoop = nil
        controlTask?.cancel()
        controlTask = nil
        noticeTask?.cancel()
        noticeTask = nil
        activeControl = nil
    }

    func openClashVerge() {
        let coordinator = coordinator
        Task.detached(priority: .userInitiated) {
            do {
                try coordinator.openClashVerge()
            } catch {
                FileHandle.standardError.write(
                    Data("Desktop widget open failed: \(error.localizedDescription)\n".utf8)
                )
            }
        }
    }

    func refreshNow() {
        let coordinator = coordinator
        Task { [weak self] in
            let freshStatus = await Task.detached(priority: .userInitiated) {
                coordinator.currentStatus()
            }.value
            self?.status = freshStatus
        }
    }

    func setMode(_ mode: String) {
        guard status.mode != mode else { return }
        perform(.mode(mode))
    }

    func toggleSystemProxy() {
        perform(.systemProxy)
    }

    func toggleTun() {
        perform(.tun)
    }

    private func perform(_ control: DesktopControl) {
        guard status.online, activeControl == nil else { return }
        activeControl = control
        actionNotice = DesktopActionNotice(text: control.progressMessage, isError: false)
        noticeTask?.cancel()

        let coordinator = coordinator
        controlTask = Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) {
                do {
                    return DesktopControlOutcome.success(try control.execute(with: coordinator))
                } catch {
                    return DesktopControlOutcome.failure(
                        status: coordinator.currentStatus(),
                        message: error.localizedDescription
                    )
                }
            }.value

            guard let self, !Task.isCancelled else { return }
            self.activeControl = nil
            self.controlTask = nil

            switch outcome {
            case let .success(freshStatus):
                self.status = freshStatus
                self.showNotice(control.successMessage(status: freshStatus), isError: false)
            case let .failure(freshStatus, message):
                self.status = freshStatus
                let concise = message.replacingOccurrences(of: "\n", with: " ")
                self.showNotice("操作失败：\(concise)", isError: true)
                FileHandle.standardError.write(
                    Data("Desktop widget control failed: \(message)\n".utf8)
                )
            }
        }
    }

    private func showNotice(_ text: String, isError: Bool) {
        actionNotice = DesktopActionNotice(text: text, isError: isError)
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(isError ? 5 : 2))
            guard !Task.isCancelled else { return }
            self?.actionNotice = nil
        }
    }

}

private struct DesktopStatusCard: View {
    @ObservedObject var model: DesktopStatusModel

    var body: some View {
        let status = model.status
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                DesktopAppMark(online: status.online)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Clash Verge")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text(model.actionNotice?.text ?? (status.online ? status.profileName : (status.message ?? "未连接")))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(model.actionNotice?.isError == true ? Color.orange : .white.opacity(0.62))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                DesktopConnectionPill(status: status)
                Button(action: model.openClashVerge) {
                    Image(systemName: "arrow.up.forward.app.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .help("打开 Clash Verge")
                .accessibilityLabel("打开 Clash Verge")
            }

            HStack(spacing: 6) {
                Image(systemName: "location.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.cyan)
                Text(status.selectedProxy)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Text("\(status.activeConnections) 个连接")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.64))
            }

            HStack(spacing: 8) {
                DesktopTrafficValue(symbol: "arrow.up", value: desktopFormatRate(status.uploadRate), tint: .mint)
                DesktopTrafficValue(symbol: "arrow.down", value: desktopFormatRate(status.downloadRate), tint: .cyan)
                Spacer(minLength: 2)
                DesktopStatusChip(
                    title: "系统代理",
                    symbol: "network",
                    isOn: status.systemProxyEnabled,
                    isBusy: model.activeControl == .systemProxy,
                    isDisabled: !status.online || model.activeControl != nil,
                    action: model.toggleSystemProxy
                )
                DesktopStatusChip(
                    title: "TUN",
                    symbol: "shield.lefthalf.filled",
                    isOn: status.tunEnabled,
                    isBusy: model.activeControl == .tun,
                    isDisabled: !status.online || model.activeControl != nil,
                    action: model.toggleTun
                )
            }

            HStack(spacing: 5) {
                DesktopModeChip(
                    title: "规则",
                    option: "rule",
                    current: status.mode,
                    isBusy: model.activeControl == .mode("rule"),
                    isDisabled: !status.online || model.activeControl != nil,
                    action: { model.setMode("rule") }
                )
                DesktopModeChip(
                    title: "全局",
                    option: "global",
                    current: status.mode,
                    isBusy: model.activeControl == .mode("global"),
                    isDisabled: !status.online || model.activeControl != nil,
                    action: { model.setMode("global") }
                )
                DesktopModeChip(
                    title: "直连",
                    option: "direct",
                    current: status.mode,
                    isBusy: model.activeControl == .mode("direct"),
                    isDisabled: !status.online || model.activeControl != nil,
                    action: { model.setMode("direct") }
                )
                Spacer(minLength: 4)
                Text("\(desktopFormatTime(status.timestamp)) · ↑\(desktopFormatBytes(status.uploadTotal))  ↓\(desktopFormatBytes(status.downloadTotal))")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .padding(13)
        .frame(width: 344, height: 164)
        .background {
            ZStack {
                LinearGradient(
                    colors: status.online
                        ? [Color(red: 0.04, green: 0.12, blue: 0.22), Color(red: 0.04, green: 0.36, blue: 0.46)]
                        : [Color(red: 0.12, green: 0.13, blue: 0.16), Color(red: 0.22, green: 0.23, blue: 0.27)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(Color.cyan.opacity(status.online ? 0.18 : 0.05))
                    .frame(width: 180, height: 180)
                    .offset(x: 130, y: -70)
                    .blur(radius: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: model.openClashVerge)
        .contextMenu {
            Button("打开 Clash Verge", action: model.openClashVerge)
            Button("立即刷新", action: model.refreshNow)
        }
        .help("按住顶部标题区域拖动；右上角按钮打开 Clash Verge")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Clash Verge 状态")
    }
}

private struct DesktopAppMark: View {
    let online: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white.opacity(0.13))
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(online ? Color.cyan : Color.gray)
        }
        .frame(width: 28, height: 28)
    }
}

private struct DesktopConnectionPill: View {
    let status: WidgetStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.online ? Color.green : Color.gray)
                .frame(width: 6, height: 6)
            Text(status.online ? (status.tunEnabled ? "TUN" : "在线") : "离线")
                .font(.system(size: 9, weight: .bold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.black.opacity(0.18), in: Capsule())
    }
}

private struct DesktopTrafficValue: View {
    let symbol: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .lineLimit(1)
        }
    }
}

private struct DesktopStatusChip: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let isBusy: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isBusy {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 9, height: 9)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 9, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 9, weight: .bold))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(isOn ? Color.green.opacity(0.28) : Color.white.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(isOn ? Color.green.opacity(0.55) : .clear, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled && !isBusy ? 0.58 : 1)
        .help(isBusy ? "正在切换\(title)" : "点击切换\(title)")
    }
}

private struct DesktopModeChip: View {
    let title: String
    let option: String
    let current: String
    let isBusy: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if isBusy {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 8, height: 8)
                }
                Text(title)
                    .font(.system(size: 9, weight: .bold))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                current == option ? Color.cyan.opacity(0.32) : Color.white.opacity(0.08),
                in: Capsule()
            )
            .overlay(
                Capsule().stroke(current == option ? Color.cyan.opacity(0.65) : .clear, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || current == option)
        .opacity(isDisabled && !isBusy ? 0.58 : 1)
        .help(current == option ? "当前为\(title)模式" : (isBusy ? "正在切换到\(title)模式" : "点击切换到\(title)模式"))
    }
}

private func desktopFormatRate(_ bytes: Int64) -> String {
    "\(desktopFormatBytes(bytes))/s"
}

private func desktopFormatTime(_ timestamp: Double) -> String {
    Date(timeIntervalSince1970: timestamp).formatted(date: .omitted, time: .shortened)
}

private func desktopFormatBytes(_ bytes: Int64) -> String {
    let value = Double(max(0, bytes))
    if value >= 1_073_741_824 { return String(format: "%.1fG", value / 1_073_741_824) }
    if value >= 1_048_576 { return String(format: "%.1fM", value / 1_048_576) }
    if value >= 1_024 { return String(format: "%.0fK", value / 1_024) }
    return "\(Int(value))B"
}

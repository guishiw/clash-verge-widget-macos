import AppKit
import Carbon
import ClashVergeWidgetCore
import Foundation
import WidgetKit

@MainActor
final class WidgetHostDelegate: NSObject, NSApplicationDelegate {
    private let coordinator: StatusCoordinator
    private let server: BridgeServer
    private var desktopPanel: DesktopPanelController?

    init(coordinator: StatusCoordinator, server: BridgeServer) {
        self.coordinator = coordinator
        self.server = server
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        server.start()
        let desktopPanel = DesktopPanelController(coordinator: coordinator)
        desktopPanel.show()
        self.desktopPanel = desktopPanel
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSAppleEventManager.shared().removeEventHandler(
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        desktopPanel?.close()
        desktopPanel = nil
        server.cancel()
    }

    @objc
    private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let raw = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: raw),
              url.scheme == "clashvergewidget",
              url.host == "open"
        else { return }

        let coordinator = coordinator
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try coordinator.openClashVerge()
                WidgetCenter.shared.reloadAllTimelines()
                for _ in 0..<10 {
                    if (try? MihomoClient().fetchRuntime()) != nil {
                        WidgetCenter.shared.reloadAllTimelines()
                        break
                    }
                    Thread.sleep(forTimeInterval: 1)
                }
                FileHandle.standardOutput.write(Data("Widget action succeeded: open\n".utf8))
            } catch {
                FileHandle.standardError.write(Data("Widget action failed: \(error.localizedDescription)\n".utf8))
            }
        }
    }
}

@main
struct ClashVergeWidgetHost {
    @MainActor
    static func main() {
        do {
            let coordinator = StatusCoordinator()
            let router = BridgeRouter(coordinator: coordinator)
            let server = try BridgeServer(router: router)
            let delegate = WidgetHostDelegate(coordinator: coordinator, server: server)
            let application = NSApplication.shared
            application.setActivationPolicy(.accessory)
            application.delegate = delegate
            withExtendedLifetime(delegate) {
                application.run()
            }
        } catch {
            FileHandle.standardError.write(
                Data("Clash Verge Widget Host failed: \(error.localizedDescription)\n".utf8)
            )
            exit(1)
        }
    }
}

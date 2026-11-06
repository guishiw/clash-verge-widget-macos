import SwiftUI
@preconcurrency import WidgetKit

struct ClashStatusEntry: TimelineEntry {
    let date: Date
    let status: WidgetStatus
}

private final class WidgetCompletion<Value>: @unchecked Sendable {
    private let body: (Value) -> Void

    init(_ body: @escaping (Value) -> Void) {
        self.body = body
    }

    func callAsFunction(_ value: Value) {
        body(value)
    }
}

struct ClashStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClashStatusEntry {
        ClashStatusEntry(date: Date(), status: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (ClashStatusEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        let completion = WidgetCompletion(completion)
        Task {
            let status = (try? await WidgetBridgeClient().status()) ?? .offline("辅助服务未运行")
            completion(ClashStatusEntry(date: Date(), status: status))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ClashStatusEntry>) -> Void) {
        let completion = WidgetCompletion(completion)
        Task {
            let status = (try? await WidgetBridgeClient().status()) ?? .offline("辅助服务未运行")
            let entry = ClashStatusEntry(date: Date(), status: status)
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
        }
    }
}

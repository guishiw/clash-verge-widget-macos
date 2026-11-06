import SwiftUI
import WidgetKit

struct ClashVergeStatusWidget: Widget {
    let kind = BridgeConfig.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClashStatusProvider()) { entry in
            ClashVergeWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Clash Verge 状态")
        .description("查看连接、节点与最近流量，并一键打开 Clash Verge。")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

@main
struct ClashVergeWidgetBundle: WidgetBundle {
    var body: some Widget {
        ClashVergeStatusWidget()
    }
}

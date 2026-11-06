import SwiftUI
import WidgetKit

struct ClashVergeWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ClashStatusEntry

    var body: some View {
        Group {
            if family == .systemSmall {
                SmallStatusView(status: entry.status)
            } else {
                MediumStatusView(status: entry.status)
            }
        }
        .containerBackground(for: .widget) {
            WidgetBackground(online: entry.status.online)
        }
    }
}

struct WidgetBackground: View {
    let online: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: online
                    ? [Color(red: 0.04, green: 0.12, blue: 0.22), Color(red: 0.04, green: 0.36, blue: 0.46)]
                    : [Color(red: 0.12, green: 0.13, blue: 0.16), Color(red: 0.22, green: 0.23, blue: 0.27)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.cyan.opacity(online ? 0.18 : 0.05))
                .frame(width: 180, height: 180)
                .offset(x: 130, y: -70)
                .blur(radius: 2)
        }
    }
}

struct MediumStatusView: View {
    let status: WidgetStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AppMark(online: status.online)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Clash Verge")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text(status.online ? status.profileName : (status.message ?? "未连接"))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                ConnectionPill(status: status)
                Link(destination: widgetActionURL("open")) {
                    Image(systemName: "arrow.up.forward.app.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
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
                TrafficValue(symbol: "arrow.up", value: formatRate(status.uploadRate), tint: .mint)
                TrafficValue(symbol: "arrow.down", value: formatRate(status.downloadRate), tint: .cyan)
                Spacer(minLength: 2)
                ToggleChip(
                    title: "系统代理",
                    symbol: "network",
                    isOn: status.systemProxyEnabled,
                    destination: widgetActionURL("open")
                )
                ToggleChip(
                    title: "TUN",
                    symbol: "shield.lefthalf.filled",
                    isOn: status.tunEnabled,
                    destination: widgetActionURL("open")
                )
            }

            HStack(spacing: 5) {
                ModeButton(title: "规则", option: "rule", current: status.mode)
                ModeButton(title: "全局", option: "global", current: status.mode)
                ModeButton(title: "直连", option: "direct", current: status.mode)
                Spacer(minLength: 4)
                Text("\(formatSampleTime(status.timestamp)) · ↑\(formatBytes(status.uploadTotal))  ↓\(formatBytes(status.downloadTotal))")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .padding(13)
    }
}

struct SmallStatusView: View {
    let status: WidgetStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                AppMark(online: status.online)
                Text("Clash Verge")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Spacer()
                Circle()
                    .fill(status.online ? Color.green : Color.gray)
                    .frame(width: 7, height: 7)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(status.online ? (status.tunEnabled ? "TUN 已连接" : "核心运行中") : "未连接")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text(status.online ? status.selectedProxy : (status.message ?? "打开 Clash Verge"))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.66))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                TrafficValue(symbol: "arrow.up", value: formatRate(status.uploadRate), tint: .mint)
                TrafficValue(symbol: "arrow.down", value: formatRate(status.downloadRate), tint: .cyan)
            }

            HStack {
                Text(status.mode.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.66))
                Spacer()
                Link(
                    destination: widgetActionURL("open")
                ) {
                    Image(systemName: "arrow.up.forward.app.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(status.online ? .cyan : .white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开 Clash Verge")
            }
        }
        .foregroundStyle(.white)
        .padding(13)
    }
}

struct AppMark: View {
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

struct ConnectionPill: View {
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

struct TrafficValue: View {
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

struct ToggleChip: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .semibold))
                Text(title)
                    .font(.system(size: 9, weight: .bold))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(isOn ? Color.green.opacity(0.28) : Color.white.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(isOn ? Color.green.opacity(0.55) : .clear, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

struct ModeButton: View {
    let title: String
    let option: String
    let current: String

    var body: some View {
        Link(destination: widgetActionURL("open")) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
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
    }
}

func widgetActionURL(_ action: String) -> URL {
    var components = URLComponents()
    components.scheme = "clashvergewidget"
    components.host = action
    return components.url!
}

func formatRate(_ bytes: Int64) -> String {
    "\(formatBytes(bytes))/s"
}

func formatSampleTime(_ timestamp: Double) -> String {
    Date(timeIntervalSince1970: timestamp).formatted(date: .omitted, time: .shortened)
}

func formatBytes(_ bytes: Int64) -> String {
    let value = Double(max(0, bytes))
    if value >= 1_073_741_824 { return String(format: "%.1fG", value / 1_073_741_824) }
    if value >= 1_048_576 { return String(format: "%.1fM", value / 1_048_576) }
    if value >= 1_024 { return String(format: "%.0fK", value / 1_024) }
    return "\(Int(value))B"
}

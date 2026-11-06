import CoreGraphics
import Foundation

enum ClashVergeHotkeyAction: String, CaseIterable, Sendable {
    case rule = "clash_mode_rule"
    case global = "clash_mode_global"
    case direct = "clash_mode_direct"
    case systemProxy = "toggle_system_proxy"
    case tun = "toggle_tun_mode"
}

enum ClashVergeControlError: LocalizedError, Equatable {
    case invalidMode(String)
    case clashUnavailable(String)
    case configUnreadable
    case globalHotkeysDisabled
    case hotkeyMissing(String)
    case duplicateHotkey(String)
    case hotkeyConflict(String)
    case malformedHotkey(String)
    case unsupportedHotkey(String)
    case eventAccessDenied
    case eventCreationFailed
    case stateDidNotChange(String)

    var errorDescription: String? {
        switch self {
        case let .invalidMode(mode):
            "不支持的代理模式：\(mode)"
        case let .clashUnavailable(message):
            message.isEmpty ? "Clash Verge 未运行" : message
        case .configUnreadable:
            "无法读取 Clash Verge 的快捷键配置"
        case .globalHotkeysDisabled:
            "Clash Verge 的全局快捷键未启用"
        case let .hotkeyMissing(function):
            "Clash Verge 尚未配置 \(function) 快捷键"
        case let .duplicateHotkey(function):
            "Clash Verge 的 \(function) 快捷键配置重复"
        case let .hotkeyConflict(hotkey):
            "Clash Verge 的快捷键 \(hotkey) 被多个控制功能共用"
        case let .malformedHotkey(hotkey):
            "快捷键格式无效：\(hotkey)"
        case let .unsupportedHotkey(hotkey):
            "小组件暂不支持快捷键：\(hotkey)"
        case .eventAccessDenied:
            "请在“系统设置 > 隐私与安全性 > 辅助功能”中允许 Clash Verge Widget 控制键盘，授权后再点击一次；若仍无效请重启小组件"
        case .eventCreationFailed:
            "无法创建快捷键事件"
        case let .stateDidNotChange(expected):
            "Clash Verge 未切换到\(expected)，请确认程序正在运行且快捷键没有冲突"
        }
    }
}

struct ParsedHotkey: Hashable, Sendable {
    let keyCode: CGKeyCode
    let modifierFlags: UInt64
}

enum ClashVergeHotkeyParser {
    static func hotkeys(in yaml: String) throws -> [ClashVergeHotkeyAction: ParsedHotkey] {
        if let enabled = VergeConfigParser.scalarValue(for: "enable_global_hotkey", in: yaml),
           ["false", "no", "off", "0"].contains(enabled.lowercased()) {
            throw ClashVergeControlError.globalHotkeysDisabled
        }

        let lines = yaml.components(separatedBy: .newlines)
        guard let startIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "hotkeys:"
        }) else {
            throw ClashVergeControlError.hotkeyMissing("控制功能")
        }

        var result: [ClashVergeHotkeyAction: ParsedHotkey] = [:]
        var chordOwners: [ParsedHotkey: String] = [:]
        for line in lines.dropFirst(startIndex + 1) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard trimmed.hasPrefix("-") else { break }

            var entry = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
            if (entry.hasPrefix("\"") && entry.hasSuffix("\"")) ||
                (entry.hasPrefix("'") && entry.hasSuffix("'")) {
                entry = String(entry.dropFirst().dropLast())
            }

            let parts = entry.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let functionName = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            guard let action = ClashVergeHotkeyAction(rawValue: functionName) else {
                // Other built-in Clash Verge actions can still shadow a widget control.
                // Track every chord we understand without rejecting unrelated custom keys.
                if let chord = try? parseChord(value) {
                    if let owner = chordOwners[chord], owner != functionName {
                        throw ClashVergeControlError.hotkeyConflict(value)
                    }
                    chordOwners[chord] = functionName
                }
                continue
            }
            guard result[action] == nil else {
                throw ClashVergeControlError.duplicateHotkey(functionName)
            }
            let chord = try parseChord(value)
            if let owner = chordOwners[chord], owner != functionName {
                throw ClashVergeControlError.hotkeyConflict(value)
            }
            chordOwners[chord] = functionName
            result[action] = chord
        }
        return result
    }

    static func parseChord(_ value: String) throws -> ParsedHotkey {
        let original = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else {
            throw ClashVergeControlError.malformedHotkey(value)
        }

        let tokens = original.split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
        guard !tokens.contains(where: \.isEmpty) else {
            throw ClashVergeControlError.malformedHotkey(original)
        }

        var flags = CGEventFlags()
        var parsedKeyCode: CGKeyCode?
        for token in tokens {
            switch token {
            case "CMD", "COMMAND", "META":
                flags.insert(.maskCommand)
            case "CTRL", "CONTROL":
                flags.insert(.maskControl)
            case "OPTION", "ALT":
                flags.insert(.maskAlternate)
            case "SHIFT":
                flags.insert(.maskShift)
            default:
                guard parsedKeyCode == nil else {
                    throw ClashVergeControlError.malformedHotkey(original)
                }
                guard let parsed = keyCode(for: token) else {
                    throw ClashVergeControlError.unsupportedHotkey(original)
                }
                parsedKeyCode = parsed
            }
        }

        guard let parsedKeyCode else {
            throw ClashVergeControlError.malformedHotkey(original)
        }
        return ParsedHotkey(keyCode: parsedKeyCode, modifierFlags: flags.rawValue)
    }

    private static func keyCode(for token: String) -> CGKeyCode? {
        let functionKeys: [String: CGKeyCode] = [
            "F1": 122, "F2": 120, "F3": 99, "F4": 118, "F5": 96,
            "F6": 97, "F7": 98, "F8": 100, "F9": 101, "F10": 109,
            "F11": 103, "F12": 111, "F13": 105, "F14": 107, "F15": 113,
            "F16": 106, "F17": 64, "F18": 79, "F19": 80, "F20": 90,
        ]
        if let code = functionKeys[token] { return code }

        let commonKeys: [String: CGKeyCode] = [
            "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5,
            "Z": 6, "X": 7, "C": 8, "V": 9, "B": 11, "Q": 12,
            "W": 13, "E": 14, "R": 15, "Y": 16, "T": 17, "1": 18,
            "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25,
            "7": 26, "8": 28, "0": 29, "O": 31, "U": 32, "I": 34,
            "P": 35, "RETURN": 36, "ENTER": 36, "L": 37, "J": 38,
            "K": 40, "N": 45, "M": 46, "TAB": 48, "SPACE": 49,
            "DELETE": 51, "BACKSPACE": 51, "ESCAPE": 53, "ESC": 53,
            "LEFT": 123, "RIGHT": 124, "DOWN": 125, "UP": 126,
        ]
        return commonKeys[token]
    }
}

protocol HotkeyEventPosting: AnyObject {
    func post(_ hotkey: ParsedHotkey) throws
}

final class SystemHotkeyEventPoster: HotkeyEventPosting {
    func post(_ hotkey: ParsedHotkey) throws {
        guard CGPreflightPostEventAccess() || CGRequestPostEventAccess() else {
            throw ClashVergeControlError.eventAccessDenied
        }
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: hotkey.keyCode,
                  keyDown: true
              ),
              let keyUp = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: hotkey.keyCode,
                  keyDown: false
              )
        else {
            throw ClashVergeControlError.eventCreationFailed
        }

        let flags = CGEventFlags(rawValue: hotkey.modifierFlags)
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.025)
        keyUp.post(tap: .cghidEventTap)
    }
}

protocol ClashVergeHotkeyDispatching: AnyObject {
    func trigger(_ action: ClashVergeHotkeyAction) throws
}

final class ClashVergeHotkeyController: ClashVergeHotkeyDispatching {
    private let configURL: URL
    private let eventPoster: any HotkeyEventPosting

    init(configDirectory: URL, eventPoster: any HotkeyEventPosting = SystemHotkeyEventPoster()) {
        configURL = configDirectory.appendingPathComponent("verge.yaml")
        self.eventPoster = eventPoster
    }

    func trigger(_ action: ClashVergeHotkeyAction) throws {
        guard let yaml = try? String(contentsOf: configURL, encoding: .utf8) else {
            throw ClashVergeControlError.configUnreadable
        }
        let configured = try ClashVergeHotkeyParser.hotkeys(in: yaml)
        guard let hotkey = configured[action] else {
            throw ClashVergeControlError.hotkeyMissing(action.rawValue)
        }
        try eventPoster.post(hotkey)
    }
}

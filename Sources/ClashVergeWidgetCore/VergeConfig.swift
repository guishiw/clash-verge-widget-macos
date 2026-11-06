import Foundation

public enum VergeConfigParser {
    public static func scalarValue(for key: String, in text: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: key)
        guard let regex = try? NSRegularExpression(
            pattern: "(?m)^\(escaped):[ \\t]*(.*)$"
        ) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return unquote(String(text[valueRange]).trimmingCharacters(in: .whitespaces))
    }

    public static func currentProfileName(in text: String) -> String? {
        guard let current = scalarValue(for: "current", in: text), !current.isEmpty else {
            return nil
        }
        let escaped = NSRegularExpression.escapedPattern(for: current)
        guard let blockRegex = try? NSRegularExpression(
            pattern: "(?ms)^-[ \\t]+uid:[ \\t]*['\\\"]?\(escaped)['\\\"]?[ \\t]*$\\n(.*?)(?=^-|\\z)"
        ) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = blockRegex.firstMatch(in: text, range: range),
              let blockRange = Range(match.range(at: 1), in: text)
        else { return nil }
        let block = String(text[blockRange])
        return scalarValue(for: "  name", in: block)
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        if (value.hasPrefix("'") && value.hasSuffix("'")) ||
            (value.hasPrefix("\"") && value.hasSuffix("\"")) {
            return String(value.dropFirst().dropLast())
        }
        if value == "null" || value == "~" {
            return ""
        }
        return value
    }
}

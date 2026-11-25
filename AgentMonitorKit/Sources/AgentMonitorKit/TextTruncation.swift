import Foundation

public enum TextTruncation {
    public static func detail(_ text: String, limit: Int = 80) -> String {
        guard limit > 0 else { return "" }

        let collapsed = text
            .replacingOccurrences(of: #"[\r\n\t ]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard collapsed.count > limit else {
            return collapsed
        }

        if limit == 1 {
            return "…"
        }
        return String(collapsed.prefix(limit - 1)) + "…"
    }
}

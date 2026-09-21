import Foundation

public enum TodoParking: Equatable, Sendable {
    case until(Date)
    case indefinite

    internal var markdownValue: String {
        switch self {
        case .until(let date):
            let timestamp = TodoParking.timestampStyle.format(date)
            return timestamp.replacingOccurrences(of: ".000Z", with: "Z")
        case .indefinite:
            return "indefinite"
        }
    }

    internal static func parseMarkdownValue(_ value: String) -> TodoParking? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value == "indefinite" {
            return .indefinite
        }

        guard value.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$"#, options: .regularExpression) != nil else {
            return nil
        }

        return (try? Date(value, strategy: TodoParking.timestampStyle)).map(TodoParking.until)
    }

    private static let timestampStyle = Date.ISO8601FormatStyle(
        includingFractionalSeconds: true,
        timeZone: .gmt
    )
}

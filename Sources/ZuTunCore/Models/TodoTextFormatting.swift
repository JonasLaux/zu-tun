import Foundation

public enum TodoTextFormatting {
    public static func render(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: titleFromMarkdown(text),
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(titleFromMarkdown(text))
    }

    /// Keep editable line breaks while normalizing pasted platform line endings.
    public static func normalizedTitle(_ text: String) -> String {
        titleFromMarkdown(text).replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines).joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A todo stays on one physical line so tags and shared line references stay attached.
    public static func markdownTitle(_ text: String) -> String {
        normalizedTitle(text).replacingOccurrences(of: "\n", with: "<br>")
    }

    public static func titleFromMarkdown(_ text: String) -> String {
        text.replacingOccurrences(of: #"(?i)<br[\t ]*/?>"#, with: "\n", options: .regularExpression)
    }
}

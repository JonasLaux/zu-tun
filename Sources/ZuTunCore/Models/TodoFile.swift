import Foundation

public enum TodoFile {
    public static var defaultURL: URL {
        TodoLocation.currentTodoURL
    }

    public static var widgetURL: URL {
        TodoLocation.appGroupTodoURL
    }

    public static func ensureExists(at url: URL = defaultURL) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "# Todo\n\n".write(to: url, atomically: true, encoding: .utf8)
    }

    public static func loadDocument(from url: URL = defaultURL) throws -> TodoDocument {
        try ensureExists(at: url)
        let markdown = try String(contentsOf: url, encoding: .utf8)
        return TodoMarkdownParser.parse(markdown)
    }

    public static func save(_ document: TodoDocument, to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try document.renderedMarkdown().write(to: url, atomically: true, encoding: .utf8)
    }

    public static func loadWidgetDocument() throws -> TodoDocument {
        try loadDocument(from: widgetURL)
    }

    public static func saveWidgetDocument(_ document: TodoDocument) throws {
        try save(document, to: widgetURL)
    }
}

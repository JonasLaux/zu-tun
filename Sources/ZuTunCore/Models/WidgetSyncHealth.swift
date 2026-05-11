import Foundation

public enum WidgetSyncState: Equatable, Sendable {
    case synced
    case stale
    case missingTodo
    case missingCache
    case unreadable(String)
}

public struct WidgetSyncHealth: Equatable, Sendable {
    public var todoURL: URL
    public var widgetURL: URL
    public var state: WidgetSyncState
    public var widgetModifiedAt: Date?

    public init(
        todoURL: URL,
        widgetURL: URL,
        state: WidgetSyncState,
        widgetModifiedAt: Date? = nil
    ) {
        self.todoURL = todoURL
        self.widgetURL = widgetURL
        self.state = state
        self.widgetModifiedAt = widgetModifiedAt
    }

    public static func current(todoURL: URL = TodoFile.defaultURL, widgetURL: URL = TodoFile.widgetURL) -> WidgetSyncHealth {
        let fileManager = FileManager.default
        let todoExists = fileManager.fileExists(atPath: todoURL.path)
        let widgetExists = fileManager.fileExists(atPath: widgetURL.path)
        let widgetModifiedAt = modifiedAt(for: widgetURL)

        guard todoExists else {
            return WidgetSyncHealth(
                todoURL: todoURL,
                widgetURL: widgetURL,
                state: .missingTodo,
                widgetModifiedAt: widgetModifiedAt
            )
        }

        guard widgetExists else {
            return WidgetSyncHealth(
                todoURL: todoURL,
                widgetURL: widgetURL,
                state: .missingCache,
                widgetModifiedAt: nil
            )
        }

        do {
            let todoDocument = try TodoFile.loadDocument(from: todoURL)
            let widgetDocument = try TodoFile.loadDocument(from: widgetURL)
            let state: WidgetSyncState = todoDocument.widgetSnapshot == widgetDocument.widgetSnapshot ? .synced : .stale

            return WidgetSyncHealth(
                todoURL: todoURL,
                widgetURL: widgetURL,
                state: state,
                widgetModifiedAt: widgetModifiedAt
            )
        } catch {
            return WidgetSyncHealth(
                todoURL: todoURL,
                widgetURL: widgetURL,
                state: .unreadable(error.localizedDescription),
                widgetModifiedAt: widgetModifiedAt
            )
        }
    }

    private static func modifiedAt(for url: URL) -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.modificationDate] as? Date
    }
}

private struct WidgetTodoSnapshot: Equatable {
    var id: UUID
    var isCompleted: Bool
    var priority: TodoPriority?
    var title: String
}

private extension TodoDocument {
    var widgetSnapshot: [WidgetTodoSnapshot] {
        todos.map {
            WidgetTodoSnapshot(
                id: $0.id,
                isCompleted: $0.isCompleted,
                priority: $0.priority,
                title: $0.title
            )
        }
    }
}

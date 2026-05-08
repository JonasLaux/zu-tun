import Foundation

public enum TodoDocumentLine: Equatable, Sendable {
    case raw(String)
    case todo(TodoItem)

    public var rendered: String {
        switch self {
        case .raw(let line):
            line
        case .todo(let item):
            item.markdownLine
        }
    }
}

public struct TodoDocument: Equatable, Sendable {
    public var lines: [TodoDocumentLine]

    public init(lines: [TodoDocumentLine] = []) {
        self.lines = lines
    }

    public var todos: [TodoItem] {
        lines.compactMap { line in
            if case .todo(let item) = line {
                return item
            }
            return nil
        }
    }

    public var openTodos: [TodoItem] {
        todos
            .filter { !$0.isCompleted }
            .sorted(by: TodoDocument.todoSort)
    }

    public var completedTodos: [TodoItem] {
        todos
            .filter(\.isCompleted)
            .sorted(by: TodoDocument.todoSort)
    }

    public mutating func appendTodo(title: String, priority: TodoPriority) {
        if lines.isEmpty {
            lines = [
                .raw("# Todo"),
                .raw("")
            ]
        }

        let item = TodoItem(
            isCompleted: false,
            priority: priority,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        if let firstCompletedIndex = lines.firstIndex(where: { line in
            if case .todo(let existing) = line {
                return existing.isCompleted
            }
            return false
        }) {
            lines.insert(.todo(item), at: firstCompletedIndex)
        } else {
            lines.append(.todo(item))
        }
    }

    @discardableResult
    public mutating func updateTodo(id: UUID, _ update: (inout TodoItem) -> Void) -> Bool {
        guard let index = lines.firstIndex(where: { line in
            if case .todo(let item) = line {
                return item.id == id
            }
            return false
        }) else {
            return false
        }

        if case .todo(var item) = lines[index] {
            update(&item)
            lines[index] = .todo(item)
            return true
        }

        return false
    }

    @discardableResult
    public mutating func deleteTodo(id: UUID) -> Bool {
        guard let index = lines.firstIndex(where: { line in
            if case .todo(let item) = line {
                return item.id == id
            }
            return false
        }) else {
            return false
        }

        lines.remove(at: index)
        return true
    }

    public func renderedMarkdown() -> String {
        lines.map(\.rendered).joined(separator: "\n") + "\n"
    }

    private static func todoSort(lhs: TodoItem, rhs: TodoItem) -> Bool {
        let leftPriority = lhs.priority?.sortRank ?? Int.max
        let rightPriority = rhs.priority?.sortRank ?? Int.max

        if leftPriority != rightPriority {
            return leftPriority < rightPriority
        }

        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}

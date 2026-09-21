import Foundation

public enum TodoDocumentLine: Equatable, Sendable {
    case raw(String)
    case tag(TodoTag)
    case todo(TodoItem)

    public var rendered: String {
        switch self {
        case .raw(let line):
            line
        case .tag(let tag):
            tag.markdownLine
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

    public var tags: [TodoTag] {
        var seenIDs: Set<String> = []
        return lines.compactMap { line in
            guard case .tag(let tag) = line else {
                return nil
            }

            let key = tag.id
            guard seenIDs.insert(key).inserted else {
                return nil
            }
            return tag
        }
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

    public func activeTodos(at date: Date) -> [TodoItem] {
        openTodos.filter { !$0.isParked(at: date) }
    }

    public func parkedTodos(at date: Date) -> [TodoItem] {
        openTodos
            .filter { $0.isParked(at: date) }
            .sorted(by: TodoDocument.parkedTodoSort)
    }

    public func nextParkingDate(after date: Date) -> Date? {
        todos
            .compactMap { item -> Date? in
                guard !item.isCompleted, case .until(let returnDate) = item.parking, returnDate > date else {
                    return nil
                }
                return returnDate
            }
            .min()
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
            title: TodoTextFormatting.normalizedTitle(title)
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

    @discardableResult
    public mutating func upsertTag(_ tag: TodoTag) -> Bool {
        guard let normalized = normalizedTag(tag) else {
            return false
        }

        let tagLineIndexes = lines.enumerated().compactMap { index, line -> Int? in
            guard case .tag = line else { return nil }
            return index
        }

        let matchingIDIndexes = tagLineIndexes.filter { index in
            guard case .tag(let existing) = lines[index] else { return false }
            return existing.id == normalized.id
        }

        guard matchingIDIndexes.count <= 1 else {
            return false
        }

        let hasDuplicateName = tagLineIndexes.contains { index in
            guard case .tag(let existing) = lines[index] else { return false }
            return existing.id != normalized.id
                && existing.name.caseInsensitiveCompare(normalized.name) == .orderedSame
        }
        guard !hasDuplicateName else {
            return false
        }

        if let index = matchingIDIndexes.first {
            lines[index] = .tag(normalized)
        } else {
            lines.append(.tag(normalized))
        }

        return true
    }

    @discardableResult
    public mutating func removeTag(id: String) -> Bool {
        let hadTag = lines.contains { line in
            guard case .tag(let tag) = line else { return false }
            return tag.id == id
        }

        lines = lines.compactMap { line in
            if case .tag(let tag) = line, tag.id == id {
                return nil
            }

            if case .todo(var item) = line {
                item.tagIDs.removeAll { $0 == id }
                return .todo(item)
            }

            return line
        }

        return hadTag
    }

    @discardableResult
    public mutating func setTagIDs(_ ids: [String], forTodoID id: UUID) -> Bool {
        guard let index = lines.firstIndex(where: { line in
            guard case .todo(let item) = line else { return false }
            return item.id == id
        }) else {
            return false
        }

        guard case .todo(var item) = lines[index] else {
            return false
        }

        let definedIDs = Set(tags.map(\.id))
        let existingUnknownIDs = item.tagIDs.filter { !definedIDs.contains($0) }
        guard ids.allSatisfy({ definedIDs.contains($0) || existingUnknownIDs.contains($0) }) else {
            return false
        }

        var nextIDs: [String] = []
        for tagID in ids + existingUnknownIDs {
            if !nextIDs.contains(tagID) {
                nextIDs.append(tagID)
            }
        }

        item.tagIDs = nextIDs
        lines[index] = .todo(item)
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

    private static func parkedTodoSort(lhs: TodoItem, rhs: TodoItem) -> Bool {
        switch (lhs.parking, rhs.parking) {
        case (.until(let leftDate), .until(let rightDate)) where leftDate != rightDate:
            return leftDate < rightDate
        case (.until, .indefinite):
            return true
        case (.indefinite, .until):
            return false
        default:
            return todoSort(lhs: lhs, rhs: rhs)
        }
    }

    private func normalizedTag(_ tag: TodoTag) -> TodoTag? {
        let name = tag.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = tag.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let color = tag.color.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty,
              !id.isEmpty,
              !id.contains(where: { $0.isNewline }),
              !name.contains(where: { $0.isNewline }),
              color.range(of: #"^#[0-9A-Fa-f]{6}$"#, options: .regularExpression) != nil else {
            return nil
        }

        return TodoTag(id: id, name: name, color: color)
    }
}

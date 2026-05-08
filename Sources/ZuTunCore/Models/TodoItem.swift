import Foundation

public struct TodoItem: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var indent: String
    public var isCompleted: Bool
    public var priority: TodoPriority?
    public var title: String

    public init(
        id: UUID = UUID(),
        indent: String = "",
        isCompleted: Bool,
        priority: TodoPriority?,
        title: String
    ) {
        self.id = id
        self.indent = indent
        self.isCompleted = isCompleted
        self.priority = priority
        self.title = title
    }

    public var markdownLine: String {
        let checkmark = isCompleted ? "x" : " "
        let priorityText = priority.map { "(\($0.rawValue)) " } ?? ""
        return "\(indent)- [\(checkmark)] \(priorityText)\(title)"
    }
}

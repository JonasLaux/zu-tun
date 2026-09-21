import Foundation

public struct TodoItem: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var indent: String
    public var isCompleted: Bool
    public var priority: TodoPriority?
    public var title: String
    public var tagIDs: [String]
    public var referenceID: UUID?

    public init(
        id: UUID = UUID(),
        indent: String = "",
        isCompleted: Bool,
        priority: TodoPriority?,
        title: String,
        tagIDs: [String] = [],
        referenceID: UUID? = nil
    ) {
        self.id = id
        self.indent = indent
        self.isCompleted = isCompleted
        self.priority = priority
        self.title = title
        self.tagIDs = tagIDs
        self.referenceID = referenceID
    }

    public var markdownLine: String {
        let checkmark = isCompleted ? "x" : " "
        let priorityText = priority.map { "(\($0.rawValue)) " } ?? ""
        let reference = referenceID.map { " <!-- zutun-id: \($0.uuidString) -->" } ?? ""
        let tags = tagIDs.isEmpty ? "" : " <!-- zutun-tags: \(tagIDsJSON) -->"
        return "\(indent)- [\(checkmark)] \(priorityText)\(TodoTextFormatting.markdownTitle(title))\(reference)\(tags)"
    }

    private var tagIDsJSON: String {
        guard let data = try? JSONEncoder().encode(tagIDs),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }

        return json.replacingOccurrences(of: ">", with: "\\u003E")
    }
}

import Foundation

public struct TodoItem: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var indent: String
    public var isCompleted: Bool
    public var priority: TodoPriority?
    public var title: String
    public var tagIDs: [String]
    public var referenceID: UUID?
    public var parking: TodoParking?
    public var details: TodoDetails?

    public init(
        id: UUID = UUID(),
        indent: String = "",
        isCompleted: Bool,
        priority: TodoPriority?,
        title: String,
        tagIDs: [String] = [],
        referenceID: UUID? = nil,
        parking: TodoParking? = nil,
        details: TodoDetails? = nil
    ) {
        self.id = id
        self.indent = indent
        self.isCompleted = isCompleted
        self.priority = priority
        self.title = title
        self.tagIDs = tagIDs
        self.referenceID = referenceID
        self.parking = parking
        self.details = details.flatMap { $0.isEmpty ? nil : $0 }
    }

    public func isParked(at date: Date) -> Bool {
        guard !isCompleted, let parking else {
            return false
        }

        switch parking {
        case .until(let returnDate):
            return returnDate > date
        case .indefinite:
            return true
        }
    }

    public var markdownLine: String {
        let checkmark = isCompleted ? "x" : " "
        let priorityText = priority.map { "(\($0.rawValue)) " } ?? ""
        let reference = referenceID.map { " <!-- zutun-id: \($0.uuidString) -->" } ?? ""
        let tags = tagIDs.isEmpty ? "" : " <!-- zutun-tags: \(tagIDsJSON) -->"
        let parking = parking.map { " <!-- zutun-parked: \($0.markdownValue) -->" } ?? ""
        return "\(indent)- [\(checkmark)] \(priorityText)\(TodoTextFormatting.markdownTitle(title))\(reference)\(tags)\(parking)"
    }

    /// The task header and its optional owned details callout.
    ///
    /// A details callout requires a persisted reference ID so that the parser
    /// can prove ownership after a task is moved. The store materializes that
    /// ID before saving a nonempty details value.
    public var markdownBlock: String {
        guard let details, !details.isEmpty, let referenceID else {
            return markdownLine
        }

        let detailIndent = indent + "  "
        let owner = "<!-- zutun-details-for: \(referenceID.uuidString) -->"
        var lines = [
            markdownLine,
            "\(detailIndent)> [!zutun]- Details \(owner)"
        ]

        if !details.state.isEmpty {
            lines.append("\(detailIndent)> **State:** \(TodoTextFormatting.markdownTitle(details.state))")
        }
        if !details.outcome.isEmpty {
            lines.append("\(detailIndent)> **Outcome:** \(TodoTextFormatting.markdownTitle(details.outcome))")
        }

        lines.append("\(detailIndent)> <!-- zutun-details-end -->")
        return lines.joined(separator: "\n")
    }

    private var tagIDsJSON: String {
        guard let data = try? JSONEncoder().encode(tagIDs),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }

        return json.replacingOccurrences(of: ">", with: "\\u003E")
    }
}

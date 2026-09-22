import Foundation

public enum TodoShareReferenceError: Error, Equatable, LocalizedError, Sendable {
    case invalidLineNumber(Int)
    case selectedLineIsNotTodo(Int)
    case selectedTodoIsStale(Int)
    case duplicateReferenceID(UUID)

    public var errorDescription: String? {
        switch self {
        case .invalidLineNumber(let lineNumber):
            return "Todo line \(lineNumber) is outside the current file. Reload and try again."
        case .selectedLineIsNotTodo(let lineNumber):
            return "Todo line \(lineNumber) is no longer a todo. Reload and try again."
        case .selectedTodoIsStale(let lineNumber):
            return "Todo line \(lineNumber) changed before it could be shared. Reload and try again."
        case .duplicateReferenceID(let referenceID):
            return "Todo reference \(referenceID.uuidString) is duplicated, so it cannot be shared safely."
        }
    }
}

public struct TodoShareReference: Equatable, Sendable {
    public let markdown: String
    public let prompt: String
    public let referenceID: UUID
    public let lineNumber: Int

    public static func prepare(
        item: TodoItem,
        lineNumber: Int,
        in markdown: String,
        fileURL: URL
    ) throws -> TodoShareReference {
        let lineRanges = sourceLineRanges(in: markdown)
        guard lineNumber > 0, lineNumber <= lineRanges.count else {
            throw TodoShareReferenceError.invalidLineNumber(lineNumber)
        }

        let document = TodoMarkdownParser.parse(markdown)
        guard let currentItem = document.todo(atPhysicalLineNumber: lineNumber) else {
            throw TodoShareReferenceError.selectedLineIsNotTodo(lineNumber)
        }
        guard semanticallyMatches(item, currentItem) else {
            throw TodoShareReferenceError.selectedTodoIsStale(lineNumber)
        }

        let sourceReferenceIDs = referenceIDOccurrences(in: markdown)
        if let currentReferenceID = currentItem.referenceID,
           sourceReferenceIDs.filter({ $0 == currentReferenceID }).count > 1 {
            throw TodoShareReferenceError.duplicateReferenceID(currentReferenceID)
        }

        let referenceID = currentItem.referenceID ?? {
            var generatedID = UUID()
            while sourceReferenceIDs.contains(generatedID) {
                generatedID = UUID()
            }
            return generatedID
        }()

        let sourceBytes = Array(markdown.utf8)
        let sourceLine = String(decoding: sourceBytes[lineRanges[lineNumber - 1]], as: UTF8.self)
        let outputMarkdown: String
        if currentItem.referenceID != nil {
            outputMarkdown = markdown
        } else {
            let patchedLine = addReferenceMarker(to: sourceLine, referenceID: referenceID)
            var patchedBytes = sourceBytes
            patchedBytes.replaceSubrange(lineRanges[lineNumber - 1], with: patchedLine.utf8)
            outputMarkdown = String(decoding: patchedBytes, as: UTF8.self)
        }

        let prompt = makePrompt(
            title: currentItem.title,
            details: currentItem.details,
            referenceID: referenceID,
            lineNumber: lineNumber,
            fileURL: fileURL
        )

        return TodoShareReference(
            markdown: outputMarkdown,
            prompt: prompt,
            referenceID: referenceID,
            lineNumber: lineNumber
        )
    }

    private init(
        markdown: String,
        prompt: String,
        referenceID: UUID,
        lineNumber: Int
    ) {
        self.markdown = markdown
        self.prompt = prompt
        self.referenceID = referenceID
        self.lineNumber = lineNumber
    }

    private static func semanticallyMatches(_ expected: TodoItem, _ current: TodoItem) -> Bool {
        expected.indent == current.indent
            && expected.isCompleted == current.isCompleted
            && expected.priority == current.priority
            && expected.title == current.title
            && expected.tagIDs == current.tagIDs
            && expected.referenceID == current.referenceID
            && expected.parking == current.parking
            && expected.details == current.details
    }

    private static func sourceLineRanges(in markdown: String) -> [Range<Int>] {
        let bytes = Array(markdown.utf8)
        var ranges: [Range<Int>] = []
        var lineStart = 0

        for index in bytes.indices where bytes[index] == 0x0A {
            ranges.append(lineStart..<index)
            lineStart = index + 1
        }
        ranges.append(lineStart..<bytes.count)
        return ranges
    }

    private static func addReferenceMarker(to line: String, referenceID: UUID) -> String {
        let lineEnding = line.hasSuffix("\r") ? "\r" : ""
        let body = lineEnding.isEmpty ? line : String(line.dropLast())
        let marker = "<!-- zutun-id: \(referenceID.uuidString) -->"

        if let tagsRange = validTrailingTagsRange(in: body) {
            let beforeTags = String(body[..<tagsRange.lowerBound])
            let tagsAndTrailingWhitespace = String(body[tagsRange.lowerBound...])
            return beforeTags + " " + marker + tagsAndTrailingWhitespace + lineEnding
        }

        return body + " " + marker + lineEnding
    }

    private static func validTrailingTagsRange(in line: String) -> Range<String.Index>? {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?:\s+)?<!--\s*zutun-tags:\s*(\[.*\])\s*-->\s*$"#
        ) else {
            return nil
        }

        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let jsonRange = Range(match.range(at: 1), in: line),
              let data = String(line[jsonRange]).data(using: .utf8),
              (try? JSONDecoder().decode([String].self, from: data)) != nil,
              let fullRange = Range(match.range, in: line) else {
            return nil
        }

        return fullRange
    }

    private static func referenceIDOccurrences(in markdown: String) -> [UUID] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<!--\s*zutun-id:\s*([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})\s*-->"#
        ) else {
            return []
        }

        let range = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        return regex.matches(in: markdown, range: range).compactMap { match in
            guard let referenceRange = Range(match.range(at: 1), in: markdown) else {
                return nil
            }
            return UUID(uuidString: String(markdown[referenceRange]))
        }
    }

    private static func makePrompt(
        title: String,
        details: TodoDetails?,
        referenceID: UUID,
        lineNumber: Int,
        fileURL: URL
    ) -> String {
        let pathURL = URL(fileURLWithPath: fileURL.path).standardizedFileURL
        let path = pathURL.path

        return """
        Use the global zu-tun skill (it may be listed as todo-md). Check out this todo, read its current text and nearby notes/subtasks, then start working on it.

        File: \(path)
        Current title: \(title)
        Stable todo ID: \(referenceID.uuidString)
        Line hint: \(lineNumber) (1-based)
        \(detailsSnapshot(details))

        Read the current owned Details callout directly below this task when it exists. Update its State and Outcome fields as the work changes, and keep those details out of the task title and overview. If the line moved, search case-insensitively for the UUID \(referenceID.uuidString) inside a zutun-id comment and verify the UUID before editing. Preserve the existing marker and keep the owned Details block with the task. Stop and ask for clarification if the item is missing or ambiguous, including when the stable ID appears more than once.
        """
    }

    private static func detailsSnapshot(_ details: TodoDetails?) -> String {
        guard let details, !details.isEmpty else {
            return ""
        }

        var snapshot = ""
        if !details.state.isEmpty {
            snapshot += "Current State: \(details.state)\n"
        }
        if !details.outcome.isEmpty {
            snapshot += "Current Outcome: \(details.outcome)\n"
        }
        return snapshot
    }
}

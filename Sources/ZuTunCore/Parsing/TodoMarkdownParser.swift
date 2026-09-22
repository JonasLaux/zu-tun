import Foundation

public enum TodoMarkdownParser {
    private static let todoPattern = #"^(\s*)-\s+\[([ xX])\]\s*(?:\((P[123])\)\s*)?(.*)$"#
    private static let tagPattern = #"^\s*<!--\s*zutun-tag:\s*(\{.*\})\s*-->\s*$"#
    private static let tagIDsPattern = #"^(.*?)(?:\s+)?<!--\s*zutun-tags:\s*(\[.*\])\s*-->\s*$"#
    private static let referenceIDPattern = #"^(.*?)(?:\s+)?<!--\s*zutun-id:\s*([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})\s*-->\s*$"#
    private static let parkingPattern = #"^(.*?)(?:\s+)?<!--\s*zutun-parked:\s*([^>]*)\s*-->\s*$"#
    private static let detailsStartPattern = #"^(\s*)>\s*\[!zutun\]-\s*Details\s+<!--\s*zutun-details-for:\s*([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})\s*-->\s*$"#
    private static let detailsFieldPattern = #"^(\s*)>\s*\*\*(State|Outcome):\*\*\s*(.*?)\s*$"#
    private static let detailsFieldLikePattern = #"^\s*\*\*[^*:\r\n]+:\*\*"#
    private static let detailsEndPattern = #"^(\s*)>\s*<!--\s*zutun-details-end\s*-->\s*$"#
    private static let detailsBodyPattern = #"^(\s*)>\s?(.*)$"#

    private struct DetailsBlock: Sendable {
        let indent: String
        let ownerID: UUID
        let details: TodoDetails
        let endIndex: Int
    }

    public static func parse(_ markdown: String) -> TodoDocument {
        let regex = try? NSRegularExpression(pattern: todoPattern)
        let tagRegex = try? NSRegularExpression(pattern: tagPattern)
        let tagIDsRegex = try? NSRegularExpression(pattern: tagIDsPattern)
        let parkingRegex = try? NSRegularExpression(pattern: parkingPattern)
        // `String.split(separator:)` treats CRLF as one Character on some
        // Swift runtimes. Components keeps physical lines and their `\r`
        // bytes intact for parsing while TodoShareReference patches the
        // original source separately.
        let rawLines = markdown.components(separatedBy: "\n")

        let detailsStartRegex = try? NSRegularExpression(pattern: detailsStartPattern)
        let detailsFieldRegex = try? NSRegularExpression(pattern: detailsFieldPattern)
        let detailsFieldLikeRegex = try? NSRegularExpression(pattern: detailsFieldLikePattern)
        let detailsEndRegex = try? NSRegularExpression(pattern: detailsEndPattern)
        let detailsBodyRegex = try? NSRegularExpression(pattern: detailsBodyPattern)

        var detailBlocks: [Int: DetailsBlock] = [:]
        var detailOwnerCounts: [UUID: Int] = [:]
        var todoReferenceCounts: [UUID: Int] = [:]
        for startIndex in rawLines.indices {
            if let item = parseTodoItem(
                from: rawLines[startIndex],
                logicalIndex: startIndex,
                regex: regex,
                tagIDsRegex: tagIDsRegex,
                parkingRegex: parkingRegex
            ), let referenceID = item.referenceID {
                todoReferenceCounts[referenceID, default: 0] += 1
            }

            if let ownerID = detailsOwnerID(from: rawLines[startIndex], startRegex: detailsStartRegex) {
                detailOwnerCounts[ownerID, default: 0] += 1
            }

            guard let block = parseDetailsBlock(
                startingAt: startIndex,
                in: rawLines,
                startRegex: detailsStartRegex,
                fieldRegex: detailsFieldRegex,
                fieldLikeRegex: detailsFieldLikeRegex,
                endRegex: detailsEndRegex,
                bodyRegex: detailsBodyRegex
            ) else {
                continue
            }

            detailBlocks[startIndex] = block
        }

        var lines: [TodoDocumentLine] = []
        var physicalLineCounts: [Int] = []
        var index = 0
        var logicalIndex = 0

        while index < rawLines.count {
            let line = rawLines[index]

            if let tagRegex,
               let match = firstMatch(in: line, using: tagRegex),
               let json = capture(1, in: line, match: match),
               let data = json.data(using: .utf8),
               let tag = try? JSONDecoder().decode(TodoTag.self, from: data),
               isValidTag(tag) {
                lines.append(.tag(tag))
                physicalLineCounts.append(1)
                index += 1
                logicalIndex += 1
                continue
            }

            if let item = parseTodoItem(
                from: line,
                logicalIndex: logicalIndex,
                regex: regex,
                tagIDsRegex: tagIDsRegex,
                parkingRegex: parkingRegex
            ) {
                var item = item
                if let block = detailBlocks[index + 1],
                   let referenceID = item.referenceID,
                   referenceID == block.ownerID,
                   block.indent == item.indent + "  ",
                   detailOwnerCounts[referenceID] == 1,
                   todoReferenceCounts[referenceID] == 1 {
                    item.details = block.details
                    lines.append(.todo(item))
                    physicalLineCounts.append(block.endIndex - index + 1)
                    index = block.endIndex + 1
                    logicalIndex += 1
                    continue
                }

                lines.append(.todo(item))
                physicalLineCounts.append(1)
                index += 1
                logicalIndex += 1
                continue
            }

            lines.append(.raw(line))
            physicalLineCounts.append(1)
            index += 1
            logicalIndex += 1
        }

        return TodoDocument(lines: lines, physicalLineCounts: physicalLineCounts)
    }

    private static func parseTodoItem(
        from line: String,
        logicalIndex: Int,
        regex: NSRegularExpression?,
        tagIDsRegex: NSRegularExpression?,
        parkingRegex: NSRegularExpression?
    ) -> TodoItem? {
        guard let regex,
              let match = firstMatch(in: line, using: regex) else {
            return nil
        }

        let indent = capture(1, in: line, match: match) ?? ""
        let checkmark = capture(2, in: line, match: match) ?? " "
        let priority = capture(3, in: line, match: match).flatMap(TodoPriority.init(rawValue:))
        let originalTitle = capture(4, in: line, match: match)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let parsedMetadata = parseMetadata(
            from: originalTitle,
            tagIDsRegex: tagIDsRegex,
            parkingRegex: parkingRegex
        )

        var item = TodoItem(
            id: UUID(),
            indent: indent,
            isCompleted: checkmark.lowercased() == "x",
            priority: priority,
            title: TodoTextFormatting.titleFromMarkdown(parsedMetadata.title),
            tagIDs: parsedMetadata.tagIDs,
            referenceID: parsedMetadata.referenceID,
            parking: parsedMetadata.parking
        )
        // The widget cache renders owned details canonically (`<br>`), so its
        // physical offsets can differ from the source. Hash the canonical task
        // header and logical document position while keeping source physical
        // spans separately for sharing and edits.
        item.id = stableID(for: item.markdownLine, logicalIndex: logicalIndex)
        return item
    }

    private static func parseDetailsBlock(
        startingAt startIndex: Int,
        in lines: [String],
        startRegex: NSRegularExpression?,
        fieldRegex: NSRegularExpression?,
        fieldLikeRegex: NSRegularExpression?,
        endRegex: NSRegularExpression?,
        bodyRegex: NSRegularExpression?
    ) -> DetailsBlock? {
        guard let startRegex, lines.indices.contains(startIndex) else {
            return nil
        }

        let startLine = withoutCarriageReturn(lines[startIndex])
        guard let startMatch = firstMatch(in: startLine, using: startRegex),
              let indent = capture(1, in: startLine, match: startMatch),
              let rawOwnerID = capture(2, in: startLine, match: startMatch),
              let ownerID = UUID(uuidString: rawOwnerID) else {
            return nil
        }

        var stateParts: [String] = []
        var outcomeParts: [String] = []
        var currentField: String?
        var index = startIndex + 1

        while index < lines.count {
            let line = withoutCarriageReturn(lines[index])

            if firstMatch(in: line, using: startRegex) != nil {
                return nil
            }

            if let endRegex,
               let endMatch = firstMatch(in: line, using: endRegex),
               capture(1, in: line, match: endMatch) == indent {
                let details = TodoDetails(
                    state: stateParts.joined(separator: "\n"),
                    outcome: outcomeParts.joined(separator: "\n")
                )
                guard !details.isEmpty else {
                    return nil
                }
                return DetailsBlock(indent: indent, ownerID: ownerID, details: details, endIndex: index)
            }

            if let fieldRegex,
               let fieldMatch = firstMatch(in: line, using: fieldRegex),
               let field = capture(2, in: line, match: fieldMatch),
               let value = capture(3, in: line, match: fieldMatch),
               capture(1, in: line, match: fieldMatch) == indent {
                guard field != "State" || stateParts.isEmpty,
                      field != "Outcome" || outcomeParts.isEmpty else {
                    return nil
                }

                currentField = field
                if field == "State" {
                    stateParts.append(value)
                } else {
                    outcomeParts.append(value)
                }
                index += 1
                continue
            }

            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let currentField {
                    appendDetailsPart("", to: currentField, state: &stateParts, outcome: &outcomeParts)
                }
                index += 1
                continue
            }

            if let bodyRegex,
               let bodyMatch = firstMatch(in: line, using: bodyRegex),
               capture(1, in: line, match: bodyMatch) == indent,
               let body = capture(2, in: line, match: bodyMatch) {
                if body.isEmpty {
                    if let currentField {
                        appendDetailsPart("", to: currentField, state: &stateParts, outcome: &outcomeParts)
                    }
                    index += 1
                    continue
                }

                guard let currentField,
                      !isFieldLike(body, using: fieldLikeRegex) else {
                    return nil
                }
                appendDetailsPart(body, to: currentField, state: &stateParts, outcome: &outcomeParts)
                index += 1
                continue
            }

            // The explicit end marker is required. Any non-callout line makes
            // this candidate malformed and leaves every source line raw.
            return nil
        }

        return nil
    }

    private static func isFieldLike(
        _ body: String,
        using regex: NSRegularExpression?
    ) -> Bool {
        guard let regex else {
            return false
        }

        return firstMatch(in: body, using: regex) != nil
    }

    private static func detailsOwnerID(
        from line: String,
        startRegex: NSRegularExpression?
    ) -> UUID? {
        guard let startRegex else {
            return nil
        }

        let line = withoutCarriageReturn(line)
        guard let match = firstMatch(in: line, using: startRegex),
              let rawOwnerID = capture(2, in: line, match: match) else {
            return nil
        }
        return UUID(uuidString: rawOwnerID)
    }

    private static func appendDetailsPart(
        _ part: String,
        to field: String,
        state: inout [String],
        outcome: inout [String]
    ) {
        if field == "State" {
            state.append(part)
        } else {
            outcome.append(part)
        }
    }

    private static func withoutCarriageReturn(_ line: String) -> String {
        line.hasSuffix("\r") ? String(line.dropLast()) : line
    }

    private static func capture(_ index: Int, in string: String, match: NSTextCheckingResult) -> String? {
        let range = match.range(at: index)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: string) else {
            return nil
        }

        return String(string[swiftRange])
    }

    private static func firstMatch(
        in string: String,
        using regex: NSRegularExpression
    ) -> NSTextCheckingResult? {
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return regex.firstMatch(in: string, range: range)
    }

    private static func parseMetadata(
        from title: String,
        tagIDsRegex: NSRegularExpression?,
        parkingRegex: NSRegularExpression?
    ) -> (title: String, tagIDs: [String], referenceID: UUID?, parking: TodoParking?) {
        let referenceRegex = try? NSRegularExpression(pattern: referenceIDPattern)
        var remaining = title
        var tagIDs: [String] = []
        var referenceID: UUID?
        var parking: TodoParking?

        // Metadata is allowed in either trailing order. Strip one valid
        // comment at a time so a valid ID remains discoverable beside tags.
        var strippedReferenceID = false
        var strippedTagIDs = false
        var strippedMetadata = true
        while strippedMetadata {
            strippedMetadata = false

            if let referenceRegex,
               !strippedReferenceID,
               let match = firstMatch(in: remaining, using: referenceRegex),
               let rawReferenceID = capture(2, in: remaining, match: match),
               let parsedReferenceID = UUID(uuidString: rawReferenceID) {
                referenceID = referenceID ?? parsedReferenceID
                remaining = capture(1, in: remaining, match: match)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                strippedReferenceID = true
                strippedMetadata = true
            }

            if let tagIDsRegex,
               !strippedTagIDs,
               let match = firstMatch(in: remaining, using: tagIDsRegex),
               let json = capture(2, in: remaining, match: match),
               let data = json.data(using: .utf8),
               let parsedTagIDs = try? JSONDecoder().decode([String].self, from: data) {
                tagIDs = parsedTagIDs
                remaining = capture(1, in: remaining, match: match)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                strippedTagIDs = true
                strippedMetadata = true
            }

            if let parkingRegex,
               let match = firstMatch(in: remaining, using: parkingRegex),
               let rawParking = capture(2, in: remaining, match: match),
               let parsedParking = TodoParking.parseMarkdownValue(rawParking) {
                parking = parking ?? parsedParking
                remaining = capture(1, in: remaining, match: match)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                strippedMetadata = true
            }
        }

        return (
            remaining.trimmingCharacters(in: .whitespacesAndNewlines),
            tagIDs,
            referenceID,
            parking
        )
    }

    private static func isValidTag(_ tag: TodoTag) -> Bool {
        let name = tag.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = tag.id.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty
            && !name.contains(where: { $0.isNewline })
            && !id.isEmpty
            && !id.contains(where: { $0.isNewline })
            && tag.color.range(of: #"^#[0-9A-Fa-f]{6}$"#, options: .regularExpression) != nil
    }

    private static func stableID(for canonicalHeader: String, logicalIndex: Int) -> UUID {
        let input = "\(logicalIndex):\(canonicalHeader)"
        var first = UInt64(0xcbf29ce484222325)
        var second = UInt64(0x84222325cbf29ce4)

        for byte in input.utf8 {
            first ^= UInt64(byte)
            first &*= 0x100000001b3

            second &+= UInt64(byte)
            second &*= 0x100000001b3
        }

        var bytes = [UInt8](repeating: 0, count: 16)
        for offset in 0..<8 {
            bytes[offset] = UInt8((first >> UInt64((7 - offset) * 8)) & 0xff)
            bytes[offset + 8] = UInt8((second >> UInt64((7 - offset) * 8)) & 0xff)
        }

        bytes[6] = (bytes[6] & 0x0f) | 0x40
        bytes[8] = (bytes[8] & 0x3f) | 0x80

        let tuple = (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )

        return UUID(uuid: tuple)
    }
}

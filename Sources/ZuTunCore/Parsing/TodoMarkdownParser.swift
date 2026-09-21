import Foundation

public enum TodoMarkdownParser {
    private static let todoPattern = #"^(\s*)-\s+\[([ xX])\]\s*(?:\((P[123])\)\s*)?(.*)$"#
    private static let tagPattern = #"^\s*<!--\s*zutun-tag:\s*(\{.*\})\s*-->\s*$"#
    private static let tagIDsPattern = #"^(.*?)(?:\s+)?<!--\s*zutun-tags:\s*(\[.*\])\s*-->\s*$"#
    private static let referenceIDPattern = #"^(.*?)(?:\s+)?<!--\s*zutun-id:\s*([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})\s*-->\s*$"#
    private static let parkingPattern = #"^(.*?)(?:\s+)?<!--\s*zutun-parked:\s*([^>]*)\s*-->\s*$"#

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

        let lines = rawLines.enumerated().map { index, line -> TodoDocumentLine in
            if let tagRegex,
               let match = firstMatch(in: line, using: tagRegex),
               let json = capture(1, in: line, match: match),
               let data = json.data(using: .utf8),
               let tag = try? JSONDecoder().decode(TodoTag.self, from: data),
               isValidTag(tag) {
                return .tag(tag)
            }

            guard let regex else {
                return .raw(line)
            }

            guard let match = firstMatch(in: line, using: regex) else {
                return .raw(line)
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

            return .todo(
                TodoItem(
                    id: stableID(for: line, index: index),
                    indent: indent,
                    isCompleted: checkmark.lowercased() == "x",
                    priority: priority,
                    title: TodoTextFormatting.titleFromMarkdown(parsedMetadata.title),
                    tagIDs: parsedMetadata.tagIDs,
                    referenceID: parsedMetadata.referenceID,
                    parking: parsedMetadata.parking
                )
            )
        }

        return TodoDocument(lines: lines)
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

    private static func stableID(for line: String, index: Int) -> UUID {
        let input = "\(index):\(line)"
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

import Foundation

public enum TodoMarkdownParser {
    private static let todoPattern = #"^(\s*)-\s+\[([ xX])\]\s*(?:\((P[123])\)\s*)?(.*)$"#

    public static func parse(_ markdown: String) -> TodoDocument {
        let regex = try? NSRegularExpression(pattern: todoPattern)
        let rawLines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        let lines = rawLines.enumerated().map { index, line -> TodoDocumentLine in
            guard let regex else {
                return .raw(line)
            }

            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, range: range) else {
                return .raw(line)
            }

            let indent = capture(1, in: line, match: match) ?? ""
            let checkmark = capture(2, in: line, match: match) ?? " "
            let priority = capture(3, in: line, match: match).flatMap(TodoPriority.init(rawValue:))
            let title = capture(4, in: line, match: match)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            return .todo(
                TodoItem(
                    id: stableID(for: line, index: index),
                    indent: indent,
                    isCompleted: checkmark.lowercased() == "x",
                    priority: priority,
                    title: title
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

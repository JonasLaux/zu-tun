import Foundation

/// Presentation only: the original Markdown task text remains unchanged.
public struct TodoLinks: Sendable {
    public struct Item: Identifiable, Equatable, Sendable {
        public let id: Int
        public let label: String
        public let url: URL
    }

    public let text: String
    public let links: [Item]

    public init(_ title: String) {
        let source = title as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        var matches: [(range: NSRange, label: String?, url: URL)] = []
        // Named Markdown links get their human-readable label.
        let markdown = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\((https?://[^\s]+)\)"#)
        for match in markdown?.matches(in: title, range: fullRange) ?? [] {
            guard let url = URL(string: source.substring(with: match.range(at: 2))) else { continue }
            matches.append((match.range, source.substring(with: match.range(at: 1)), url))
        }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        for match in detector?.matches(in: title, range: fullRange) ?? [] {
            guard let url = match.url,
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  !matches.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 }) else { continue }
            matches.append((match.range, nil, url))
        }
        matches.sort { $0.range.location < $1.range.location }
        links = matches.enumerated().map { index, match in
            let host = match.url.host() ?? match.url.absoluteString
            return Item(id: index, label: match.label ?? host, url: match.url)
        }
        let remaining = NSMutableString(string: title)
        for match in matches.reversed() {
            remaining.replaceCharacters(in: match.range, with: "")
        }
        text = (remaining as String).trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+[—–-]\s*$"#, with: "", options: .regularExpression)
    }
}

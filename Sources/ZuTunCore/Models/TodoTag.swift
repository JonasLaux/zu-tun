import Foundation

public struct TodoTag: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var color: String

    public init(
        id: String = UUID().uuidString,
        name: String,
        color: String
    ) {
        self.id = id
        self.name = name
        self.color = color
    }

    public var markdownLine: String {
        "<!-- zutun-tag: \(metadataJSON) -->"
    }

    var metadataJSON: String {
        guard let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }

        // Keep a name or ID containing `-->` inside the Markdown comment.
        // JSON decoders turn this escape back into the original character.
        return json.replacingOccurrences(of: ">", with: "\\u003E")
    }
}

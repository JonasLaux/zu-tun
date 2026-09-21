import Foundation
import Testing
@testable import ZuTunCore

@Suite("Todo links")
struct TodoLinksTests {
    @Test func plainTextUnchanged() {
        let content = TodoLinks("Ship the thing #today")
        #expect(content.text == "Ship the thing #today")
        #expect(content.links.isEmpty)
    }

    @Test func detectsURLsAndKeepsDestinations() {
        let content = TodoLinks("Review — https://example.com/a?x=1&y=2")
        #expect(content.text == "Review")
        #expect(content.links.first?.label == "example.com")
        #expect(content.links.first?.url.absoluteString == "https://example.com/a?x=1&y=2")
    }

    @Test func namedAndBareLinksKeepOrder() {
        let content = TodoLinks("Check [the PR](https://github.com/org/repo/pull/42) and https://example.com.")
        #expect(content.links.map(\.label) == ["the PR", "example.com"])
        #expect(content.links.last?.url.absoluteString == "https://example.com")
        #expect(content.links.map(\.id) == [0, 1])
    }

    @Test func multilineTitlesKeepBreaksAndLinkOrder() {
        let title = "Review [the PR](https://github.com/org/repo/pull/42)\n\nFollow up at https://example.com/notes"
        let content = TodoLinks(title)

        #expect(content.links.map(\.label) == ["the PR", "example.com"])
        #expect(content.links.map(\.id) == [0, 1])
        #expect(content.text.contains("Review"))
        #expect(content.text.contains("\n\n"))
        #expect(content.text.contains("Follow up at"))
    }

    @Test func unicodeAndParentheses() {
        let content = TodoLinks("🚀 Read https://example.com/wiki/Thing_(example)")
        #expect(content.text == "🚀 Read")
        #expect(content.links.first?.url.absoluteString == "https://example.com/wiki/Thing_(example)")
    }

    @Test func unsupportedSchemesStayText() {
        let title = "Run file:///tmp/example or email person@example.com"
        let content = TodoLinks(title)
        #expect(content.text == title)
        #expect(content.links.isEmpty)
    }
}

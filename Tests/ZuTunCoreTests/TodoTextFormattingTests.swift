import Foundation
import Testing
@testable import ZuTunCore

@Suite("Todo text formatting")
struct TodoTextFormattingTests {
    @Test func rendersInlineFormatting() {
        let rendered = TodoTextFormatting.render("Ship **bold** and *italic* with `code` 🚀")
        #expect(String(rendered.characters) == "Ship bold and italic with code 🚀")
        #expect(rendered.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        #expect(rendered.runs.contains { $0.inlinePresentationIntent?.contains(.emphasized) == true })
        #expect(rendered.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true })
    }

    @Test func formattingAndTagsSurviveTitleEdit() throws {
        var document = TodoMarkdownParser.parse("# Todo\n- [x] (P1) Old title <!-- zutun-tags: [\"work\"] -->")
        let item = try #require(document.todos.first)
        let title = "Review **the plan** with [context](https://example.com)"
        #expect(document.updateTodo(id: item.id) { $0.title = title })
        let saved = try #require(TodoMarkdownParser.parse(document.renderedMarkdown()).todos.first)
        #expect(saved.title == title)
        #expect(saved.tagIDs == ["work"])
        #expect(saved.isCompleted)
        #expect(saved.priority == .p1)
        #expect(TodoLinks(saved.title).links.first?.label == "context")
    }

    @Test func normalizesPastedLineEndingsWhileKeepingBlankLines() {
        let pasted = "\t  First\r\n\r\nSecond\rThird\u{2028}\u{2029}Fourth  \n"

        #expect(
            TodoTextFormatting.normalizedTitle(pasted)
                == "First\n\nSecond\nThird\n\nFourth"
        )
    }

    @Test func markdownBreakMarkersRoundTripFormattingAndBlankLines() {
        let title = "Review **the plan**\n\nwith [context](https://example.com)\nand `code`"
        let rendered = TodoTextFormatting.render(title)

        #expect(
            TodoTextFormatting.markdownTitle(title)
                == "Review **the plan**<br><br>with [context](https://example.com)<br>and `code`"
        )
        #expect(String(rendered.characters) == "Review the plan\n\nwith context\nand code")
        #expect(rendered.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        #expect(rendered.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true })
        #expect(
            TodoTextFormatting.titleFromMarkdown(
                "Review **the plan**<BR><br/>with [context](https://example.com)<br />and `code`"
            ) == title
        )
    }

    @Test func multilineTitleRoundTripsWithFormattingTagsAndStableID() throws {
        let tag = TodoTag(id: "work", name: "Work", color: "#3478F6")
        let referenceID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let title = "Review **the plan**\n\nwith [context](https://example.com)\nKeep &lt;br&gt; visible"
        let item = TodoItem(
            isCompleted: true,
            priority: .p1,
            title: title,
            tagIDs: [tag.id],
            referenceID: referenceID
        )
        let document = TodoDocument(lines: [.raw("# Todo"), .raw(""), .tag(tag), .todo(item)])

        let rendered = document.renderedMarkdown()
        let parsed = TodoMarkdownParser.parse(rendered)
        let reloaded = try #require(parsed.todos.first)

        #expect(rendered.contains("<br><br>"))
        #expect(rendered.components(separatedBy: "\n").filter { $0.contains("- [x]") }.count == 1)
        #expect(parsed.tags == [tag])
        #expect(reloaded.title == title)
        #expect(reloaded.tagIDs == [tag.id])
        #expect(reloaded.referenceID == referenceID)
        #expect(reloaded.isCompleted)
        #expect(reloaded.priority == .p1)
    }

    @Test func pastedCheckboxLikeTextCannotCreateTasks() throws {
        let title = "  First\r\n- [ ] Second\n\nThird  "
        var document = TodoDocument()
        document.appendTodo(title: title, priority: .p2)
        let parsed = TodoMarkdownParser.parse(document.renderedMarkdown())

        #expect(parsed.todos.count == 1)
        #expect(parsed.todos.first?.title == "First\n- [ ] Second\n\nThird")
    }

    @Test func preservesPlainTextAndUnfinishedMarkup() {
        let title = "Fix **unfinished markup & keep  two spaces"
        #expect(String(TodoTextFormatting.render(title).characters) == title)
    }
}

import Foundation
import Testing
@testable import ZuTunCore

@Suite("Todo details")
struct TodoDetailsTests {
    private let fileURL = URL(fileURLWithPath: "/tmp/zu-tun/todo.md")

    @Test("round trips owned details and encoded field breaks")
    func roundTripsDetails() throws {
        let referenceID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let markdown = """
        # Todo
        - [ ] First <!-- zutun-id: \(referenceID.uuidString) -->
          > [!zutun]- Details <!-- zutun-details-for: \(referenceID.uuidString) -->
          > **State:** Waiting<br>for approval
          > **Outcome:** Approval received
          > <!-- zutun-details-end -->
        - [ ] Later
        """

        let document = TodoMarkdownParser.parse(markdown)
        let first = try #require(document.todos.first)
        let later = try #require(document.todos.last)

        #expect(first.details == TodoDetails(state: "Waiting\nfor approval", outcome: "Approval received"))
        #expect(document.physicalLineNumber(forTodoID: first.id) == 2)
        #expect(document.physicalLineNumber(forTodoID: later.id) == 7)
        #expect(document.todo(atPhysicalLineNumber: 3) == nil)

        let rendered = document.renderedMarkdown()
        #expect(rendered.contains("  > [!zutun]- Details <!-- zutun-details-for: \(referenceID.uuidString) -->"))
        #expect(rendered.contains("**State:** Waiting<br>for approval"))
        #expect(TodoMarkdownParser.parse(rendered).todos.first?.details == first.details)
    }

    @Test("uses task indentation for nested owned details")
    func nestedDetailsUseRelativeIndentation() throws {
        let referenceID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let item = TodoItem(
            indent: "  ",
            isCompleted: false,
            priority: .p2,
            title: "Nested",
            referenceID: referenceID,
            details: TodoDetails(state: "In progress")
        )
        let document = TodoDocument(lines: [.todo(item)])

        #expect(document.renderedMarkdown().contains(
            "    > [!zutun]- Details <!-- zutun-details-for: \(referenceID.uuidString) -->"
        ))
        let parsed = try #require(TodoMarkdownParser.parse(document.renderedMarkdown()).todos.first)
        #expect(parsed.indent == "  ")
        #expect(parsed.details == item.details)
    }

    @Test("keeps source physical spans for blank and continuation lines")
    func preservesSourcePhysicalSpans() throws {
        let firstID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        let markdown = """
        # Todo
        - [ ] First <!-- zutun-id: \(firstID.uuidString) -->
          > [!zutun]- Details <!-- zutun-details-for: \(firstID.uuidString) -->
          > **State:** First line
          >
          > continuation line
          > **Outcome:** Complete
          > <!-- zutun-details-end -->
        - [ ] Later
        """

        let document = TodoMarkdownParser.parse(markdown)
        let first = try #require(document.todos.first)
        let later = try #require(document.todos.last)

        #expect(first.details?.state == "First line\n\ncontinuation line")
        #expect(document.physicalLineNumber(forTodoID: later.id) == 9)
        _ = document.renderedMarkdown()
        #expect(document.physicalLineNumber(forTodoID: later.id) == 9)

        let reparsed = TodoMarkdownParser.parse(markdown.replacingOccurrences(of: "\n", with: "\r\n"))
        let reloadedLater = try #require(reparsed.todos.last)
        #expect(reparsed.physicalLineNumber(forTodoID: reloadedLater.id) == 9)
    }

    @Test("keeps transient IDs aligned with the canonical widget cache")
    func canonicalWidgetCacheKeepsTransientIDs() throws {
        let firstID = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!
        let source = """
        # Todo

        - [ ] First <!-- zutun-id: \(firstID.uuidString) -->
          > [!zutun]- Details <!-- zutun-details-for: \(firstID.uuidString) -->
          > **State:** Waiting
          >
          > continuation line
          > **Outcome:** Complete
          > <!-- zutun-details-end -->
        - [ ] Later
        - [ ] Later
        """
        let sourceDocument = TodoMarkdownParser.parse(source)
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZuTunCoreTests-WidgetCache-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: cacheURL) }

        try TodoFile.save(sourceDocument, to: cacheURL)
        var cacheDocument = try TodoFile.loadDocument(from: cacheURL)

        #expect(sourceDocument.todos.map(\.id) == cacheDocument.todos.map(\.id))
        #expect(Set(sourceDocument.todos.map(\.id)).count == sourceDocument.todos.count)
        #expect(Set(cacheDocument.todos.map(\.id)).count == cacheDocument.todos.count)
        #expect(sourceDocument.physicalLineNumber(forTodoID: sourceDocument.todos[1].id) == 10)
        #expect(cacheDocument.updateTodo(id: sourceDocument.todos[1].id) { $0.isCompleted = true })
    }

    @Test("sharing uses physical lines after an owned details block and preserves CRLF")
    func sharesLaterPhysicalLine() throws {
        let firstID = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
        let source = """
        # Todo
        - [ ] First <!-- zutun-id: \(firstID.uuidString) -->
          > [!zutun]- Details <!-- zutun-details-for: \(firstID.uuidString) -->
          > **State:** Waiting
          >
          > continuation
          > **Outcome:** Complete
          > <!-- zutun-details-end -->
        - [ ] Later
        """.replacingOccurrences(of: "\n", with: "\r\n")
        let document = TodoMarkdownParser.parse(source)
        let later = try #require(document.todos.last)
        let prepared = try TodoShareReference.prepare(
            item: later,
            lineNumber: 9,
            in: source,
            fileURL: fileURL
        )

        #expect(prepared.markdown.contains("- [ ] Later <!-- zutun-id:"))
        #expect(prepared.markdown.contains("\r\n"))
        #expect(prepared.markdown.components(separatedBy: "\r\n")[8].contains("Later"))
    }

    @Test("deleting a todo removes its owned details block")
    func deletingDetailsRemovesBlock() throws {
        let referenceID = UUID(uuidString: "55555555-5555-4555-8555-555555555555")!
        var document = TodoMarkdownParser.parse("""
        # Todo
        - [ ] Remove me <!-- zutun-id: \(referenceID.uuidString) -->
          > [!zutun]- Details <!-- zutun-details-for: \(referenceID.uuidString) -->
          > **State:** Temporary
          > <!-- zutun-details-end -->
        - [ ] Keep me
        """)
        let first = try #require(document.todos.first)

        let deleted = document.deleteTodo(id: first.id)
        #expect(deleted)
        let rendered = document.renderedMarkdown()
        #expect(!rendered.contains("Remove me"))
        #expect(!rendered.contains("zutun-details-for:"))
        #expect(document.todos.map(\.title) == ["Keep me"])
    }

    @Test("does not attach mismatched, malformed, duplicate, or ambiguous owners")
    func rejectsUnsafeOwnership() throws {
        let firstID = UUID(uuidString: "66666666-6666-4666-8666-666666666666")!
        let secondID = UUID(uuidString: "77777777-7777-4777-8777-777777777777")!
        let markdown = """
        - [ ] Mismatched <!-- zutun-id: \(firstID.uuidString) -->
          > [!zutun]- Details <!-- zutun-details-for: \(secondID.uuidString) -->
          > **State:** Wrong owner
          > <!-- zutun-details-end -->
        - [ ] Duplicate owner <!-- zutun-id: \(firstID.uuidString) -->
          > [!zutun]- Details <!-- zutun-details-for: \(firstID.uuidString) -->
          > **State:** First copy
          > <!-- zutun-details-end -->
        - [ ] Malformed owner <!-- zutun-id: \(secondID.uuidString) -->
          > [!zutun]- Details <!-- zutun-details-for: \(secondID.uuidString) -->
          > **State:** Missing end
        - [ ] Duplicate task ID <!-- zutun-id: \(firstID.uuidString) -->
          > [!zutun]- Details <!-- zutun-details-for: \(firstID.uuidString) -->
          > **State:** Second copy
          > <!-- zutun-details-end -->
        """

        let document = TodoMarkdownParser.parse(markdown)
        #expect(document.todos.allSatisfy { $0.details == nil })
        #expect(document.renderedMarkdown().contains("Mismatched"))
        #expect(document.renderedMarkdown().contains("Missing end"))
        #expect(document.renderedMarkdown().contains("Second copy"))
    }

    @Test("preserves field-like malformed details when clearing details")
    func preservesUnsupportedFieldsWhenClearing() throws {
        let evidenceID = UUID(uuidString: "99999999-9999-4999-8999-999999999999")!
        let ownerID = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
        let markdown = """
        - [ ] Evidence field <!-- zutun-id: \(evidenceID.uuidString) -->
          > [!zutun]- Details <!-- zutun-details-for: \(evidenceID.uuidString) -->
          > **State:** Waiting
          > **Evidence:** https://example.com
          > <!-- zutun-details-end -->
        - [ ] Owner field <!-- zutun-id: \(ownerID.uuidString) -->
          > [!zutun]- Details <!-- zutun-details-for: \(ownerID.uuidString) -->
          > **State:** Waiting
          > **Owner:** Alice
          > <!-- zutun-details-end -->
        """

        var document = TodoMarkdownParser.parse(markdown)
        let items = document.todos
        #expect(items.count == 2)
        #expect(items.allSatisfy { $0.details == nil })
        #expect(document.renderedMarkdown() == markdown + "\n")

        for item in items {
            #expect(document.updateTodo(id: item.id) { $0.details = nil })
        }
        #expect(document.renderedMarkdown() == markdown + "\n")
    }

    @Test("details changes make a shared selection stale and appear in the prompt")
    func staleDetailsAndPrompt() throws {
        let referenceID = UUID(uuidString: "88888888-8888-4888-8888-888888888888")!
        let markdown = "- [ ] Task <!-- zutun-id: \(referenceID.uuidString) -->\n"
            + "  > [!zutun]- Details <!-- zutun-details-for: \(referenceID.uuidString) -->\n"
            + "  > **State:** Waiting\n"
            + "  > **Outcome:** Pending\n"
            + "  > <!-- zutun-details-end -->\n"
        let item = try #require(TodoMarkdownParser.parse(markdown).todos.first)
        let changed = markdown.replacingOccurrences(of: "Waiting", with: "Approved")

        do {
            _ = try TodoShareReference.prepare(item: item, lineNumber: 1, in: changed, fileURL: fileURL)
            Issue.record("changed details should be rejected")
        } catch let error as TodoShareReferenceError {
            #expect(error == .selectedTodoIsStale(1))
        }

        let prepared = try TodoShareReference.prepare(item: item, lineNumber: 1, in: markdown, fileURL: fileURL)
        #expect(prepared.prompt.contains("Current State: Waiting"))
        #expect(prepared.prompt.contains("Current Outcome: Pending"))
        #expect(prepared.prompt.contains("owned Details callout"))
    }
}

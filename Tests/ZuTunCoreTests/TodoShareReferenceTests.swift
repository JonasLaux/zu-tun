import Foundation
import Testing
@testable import ZuTunCore

@Suite("Todo sharing")
struct TodoShareReferenceTests {
    private let fileURL = URL(fileURLWithPath: "/tmp/zu-tun/todo.md")

    @Test("parses IDs in either order and renders the canonical order")
    func parsesMetadataOrdering() throws {
        let firstID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let secondID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let markdown = """
        - [ ] First <!-- zutun-id: \(firstID.uuidString) --> <!-- zutun-tags: ["work"] -->
        - [x] Second <!-- zutun-tags: ["home"] --> <!-- zutun-id: \(secondID.uuidString) -->
        """

        let todos = TodoMarkdownParser.parse(markdown).todos

        #expect(todos.map(\.referenceID) == [firstID, secondID])
        #expect(todos.map(\.tagIDs) == [["work"], ["home"]])
        #expect(todos[0].title == "First")
        #expect(todos[1].title == "Second")
        #expect(todos[1].markdownLine == "- [x] Second <!-- zutun-id: \(secondID.uuidString) --> <!-- zutun-tags: [\"home\"] -->")
    }

    @Test("keeps malformed and repeated metadata in the title")
    func preservesMalformedMetadata() throws {
        let firstID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        let secondID = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
        let markdown = """
        - [ ] Broken <!-- zutun-id: not-a-uuid --> <!-- zutun-tags: ["work", 1] -->
        - [ ] Repeated <!-- zutun-id: \(firstID.uuidString) --> <!-- zutun-id: \(secondID.uuidString) -->
        """

        let todos = TodoMarkdownParser.parse(markdown).todos

        #expect(todos[0].referenceID == nil)
        #expect(todos[0].tagIDs.isEmpty)
        #expect(todos[0].title.contains("zutun-id: not-a-uuid"))
        #expect(todos[0].title.contains("zutun-tags: [\"work\", 1]"))
        #expect(todos[1].referenceID == secondID)
        #expect(todos[1].title.contains(firstID.uuidString))
    }

    @Test("keeps a reference across moved, renamed, and completed lines")
    func referenceSurvivesTodoChanges() throws {
        let markdown = "- [ ] Plan the release"
        let initial = try #require(TodoMarkdownParser.parse(markdown).todos.first)
        let shared = try TodoShareReference.prepare(
            item: initial,
            lineNumber: 1,
            in: markdown,
            fileURL: fileURL
        )
        let moved = "# Todo\n\n- [x] Rename the release <!-- zutun-id: \(shared.referenceID.uuidString) -->"
        let updated = try #require(TodoMarkdownParser.parse(moved).todos.first)

        #expect(updated.referenceID == shared.referenceID)
        #expect(updated.title == "Rename the release")
        #expect(updated.isCompleted)
        #expect(updated.id != initial.id)
    }

    @Test("patches one CRLF line without changing unrelated bytes or EOF")
    func preservesSourceBytesAndRepeatedCopies() throws {
        let markdown = "# Todo\r\n- [ ] Keep this <!-- zutun-tags: [\"work\"] -->\r\n- [x] Leave this"
        let item = try #require(TodoMarkdownParser.parse(markdown).todos.first)

        let first = try TodoShareReference.prepare(
            item: item,
            lineNumber: 2,
            in: markdown,
            fileURL: fileURL
        )
        let expected = "# Todo\r\n- [ ] Keep this <!-- zutun-id: \(first.referenceID.uuidString) --> <!-- zutun-tags: [\"work\"] -->\r\n- [x] Leave this"

        #expect(first.markdown == expected)
        #expect(!first.markdown.hasSuffix("\n"))
        #expect(first.markdown.contains("\r\n"))
        #expect(TodoMarkdownParser.parse(first.markdown).todos[0].referenceID == first.referenceID)

        let reloaded = try #require(TodoMarkdownParser.parse(first.markdown).todos.first)
        let second = try TodoShareReference.prepare(
            item: reloaded,
            lineNumber: 2,
            in: first.markdown,
            fileURL: fileURL
        )
        #expect(second.markdown == first.markdown)
        #expect(second.referenceID == first.referenceID)
    }

    @Test("allows unrelated duplicate IDs while rejecting an ambiguous selected ID")
    func validatesReferenceUniqueness() throws {
        let duplicateID = UUID(uuidString: "55555555-5555-4555-8555-555555555555")!
        let unrelated = """
        - [ ] New target
        - [ ] Other <!-- zutun-id: \(duplicateID.uuidString) -->
        - [ ] Copy <!-- zutun-id: \(duplicateID.uuidString) -->
        """
        let target = try #require(TodoMarkdownParser.parse(unrelated).todos.first)

        let prepared = try TodoShareReference.prepare(
            item: target,
            lineNumber: 1,
            in: unrelated,
            fileURL: fileURL
        )
        #expect(prepared.markdown.contains("New target <!-- zutun-id: \(prepared.referenceID.uuidString) -->"))

        let ambiguous = TodoMarkdownParser.parse(unrelated).todos[1]
        do {
            _ = try TodoShareReference.prepare(
                item: ambiguous,
                lineNumber: 2,
                in: unrelated,
                fileURL: fileURL
            )
            Issue.record("sharing a duplicated reference should fail")
        } catch let error as TodoShareReferenceError {
            #expect(error == .duplicateReferenceID(duplicateID))
        }
    }

    @Test("rejects stale line selections and includes an agent-ready prompt")
    func rejectsStaleSelectionAndBuildsPrompt() throws {
        let markdown = "# Todo\n- [ ] Read the notes"
        let item = try #require(TodoMarkdownParser.parse(markdown).todos.last)
        let changed = "# Todo\n- [ ] Read a different note"

        do {
            _ = try TodoShareReference.prepare(
                item: item,
                lineNumber: 2,
                in: changed,
                fileURL: fileURL
            )
            Issue.record("a changed line should be rejected")
        } catch let error as TodoShareReferenceError {
            #expect(error == .selectedTodoIsStale(2))
        }

        let prepared = try TodoShareReference.prepare(
            item: item,
            lineNumber: 2,
            in: markdown,
            fileURL: fileURL
        )
        #expect(prepared.prompt.contains("global zu-tun skill"))
        #expect(prepared.prompt.contains("/tmp/zu-tun/todo.md"))
        #expect(prepared.prompt.contains("Read the notes"))
        #expect(prepared.prompt.contains(prepared.referenceID.uuidString))
        #expect(prepared.prompt.contains("nearby notes/subtasks"))
        #expect(prepared.prompt.contains("Line hint: 2 (1-based)"))
    }
}

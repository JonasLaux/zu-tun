import Foundation
import Testing
@testable import ZuTunCore

@Suite("Todo tags")
struct TodoTagTests {
    @Test("round trips definitions and references, including unknown IDs")
    func roundTripsDefinitionsAndReferences() {
        let markdown = """
        # Todo

        <!-- zutun-tag: {"id":"work","name":"Work","color":"#FF8800"} -->
        - [ ] Plan the release <!-- zutun-tags: ["work","from-an-old-version"] -->
        - [x] Finish the release <!-- zutun-tags: ["work"] -->
        """

        let document = TodoMarkdownParser.parse(markdown)

        #expect(document.tags == [TodoTag(id: "work", name: "Work", color: "#FF8800")])
        #expect(document.todos[0].title == "Plan the release")
        #expect(document.todos[0].tagIDs == ["work", "from-an-old-version"])
        #expect(document.todos[1].isCompleted)
        #expect(document.todos[1].tagIDs == ["work"])
        let reparsed = TodoMarkdownParser.parse(document.renderedMarkdown())
        #expect(reparsed.tags == document.tags)
        #expect(reparsed.todos.map(\.tagIDs) == document.todos.map(\.tagIDs))
        #expect(reparsed.todos.map(\.title) == document.todos.map(\.title))
    }

    @Test("escapes a comment terminator in tag metadata and decodes it again")
    func escapesCommentTerminator() {
        let tag = TodoTag(id: "id-->part", name: "Work --> later", color: "#112233")
        let rendered = tag.markdownLine

        #expect(rendered.contains("\\u003E"))
        #expect(!rendered.contains("--> later"))
        #expect(TodoMarkdownParser.parse(rendered).tags == [tag])
    }

    @Test("upserts valid tags and rejects invalid or duplicate metadata")
    func upsertsAndValidatesTags() {
        var document = TodoDocument(lines: [.raw("# Todo")])
        let work = TodoTag(id: "work", name: "  Work  ", color: " #112233 ")

        let added = document.upsertTag(work)
        #expect(added)
        #expect(document.tags == [TodoTag(id: "work", name: "Work", color: "#112233")])
        let updated = document.upsertTag(TodoTag(id: "work", name: "Updated", color: "#445566"))
        #expect(updated)
        #expect(document.tags == [TodoTag(id: "work", name: "Updated", color: "#445566")])
        let duplicateName = document.upsertTag(TodoTag(id: "other", name: " updated ", color: "#778899"))
        #expect(!duplicateName)
        let invalidColor = document.upsertTag(TodoTag(id: "other", name: "Other", color: "fff"))
        #expect(!invalidColor)
        let multilineName = document.upsertTag(TodoTag(id: "other", name: "line\nbreak", color: "#778899"))
        #expect(!multilineName)
        let multilineID = document.upsertTag(TodoTag(id: "line\nbreak", name: "Other", color: "#778899"))
        #expect(!multilineID)
    }

    @Test("updates known IDs while preserving existing unknown IDs")
    func setsTagIDsPreservingUnknownIDs() {
        let todoID = UUID()
        let known = TodoTag(id: "known", name: "Known", color: "#112233")
        let existing = TodoItem(
            id: todoID,
            isCompleted: false,
            priority: nil,
            title: "Task",
            tagIDs: ["legacy", known.id]
        )
        var document = TodoDocument(lines: [.tag(known), .todo(existing)])

        let clearedKnown = document.setTagIDs([], forTodoID: todoID)
        #expect(clearedKnown)
        #expect(document.todos[0].tagIDs == ["legacy"])
        let rejectedMissing = document.setTagIDs(["missing"], forTodoID: todoID)
        #expect(!rejectedMissing)
        #expect(document.todos[0].tagIDs == ["legacy"])
        let restoredKnown = document.setTagIDs([known.id], forTodoID: todoID)
        #expect(restoredKnown)
        #expect(document.todos[0].tagIDs == [known.id, "legacy"])
    }

    @Test("removing a tag removes its definition and every task reference")
    func removesTagFromOpenAndCompletedTodos() {
        let work = TodoTag(id: "work", name: "Work", color: "#112233")
        let other = TodoTag(id: "other", name: "Other", color: "#445566")
        let open = TodoItem(
            isCompleted: false,
            priority: nil,
            title: "Open",
            tagIDs: [work.id, other.id]
        )
        let completed = TodoItem(
            isCompleted: true,
            priority: nil,
            title: "Completed",
            tagIDs: [work.id]
        )
        var document = TodoDocument(lines: [.tag(work), .tag(other), .todo(open), .todo(completed)])

        let removed = document.removeTag(id: work.id)
        #expect(removed)
        #expect(document.tags == [other])
        #expect(document.openTodos[0].tagIDs == [other.id])
        #expect(document.completedTodos[0].tagIDs.isEmpty)
        let removedAgain = document.removeTag(id: work.id)
        #expect(!removedAgain)
    }

    @Test("preserves malformed metadata and unrelated prose")
    func preservesMalformedMetadataAndProse() {
        let markdown = """
        # Todo
        Keep this prose <!-- zutun-tag: not-json -->
        <!-- zutun-tag: {"id":"bad","name":"","color":"#112233"} -->
        - [ ] Keep malformed <!-- zutun-tags: ["known",42] -->
        """

        let document = TodoMarkdownParser.parse(markdown)

        #expect(document.tags.isEmpty)
        #expect(document.todos.count == 1)
        #expect(document.todos[0].tagIDs.isEmpty)
        #expect(document.todos[0].title == "Keep malformed <!-- zutun-tags: [\"known\",42] -->")
        let reparsed = TodoMarkdownParser.parse(document.renderedMarkdown())
        #expect(reparsed.tags == document.tags)
        #expect(reparsed.todos.map(\.title) == document.todos.map(\.title))
        #expect(reparsed.todos.map(\.tagIDs) == document.todos.map(\.tagIDs))
    }

    @Test("keeps duplicate definitions removable without duplicate exposed IDs")
    func preservesDuplicateDefinitions() {
        let markdown = """
        <!-- zutun-tag: {"id":"one","name":"Work","color":"#112233"} -->
        <!-- zutun-tag: {"id":"one","name":"Other","color":"#445566"} -->
        <!-- zutun-tag: {"id":"two","name":"work","color":"#778899"} -->
        """

        let document = TodoMarkdownParser.parse(markdown)

        #expect(document.tags.count == 2)
        #expect(document.tags[0].id == "one")
        #expect(document.tags[1].id == "two")
        #expect(document.lines.count == 3)
        if case .tag(let duplicateID) = document.lines[1] {
            #expect(duplicateID.id == "one")
        } else {
            Issue.record("duplicate ID definition should remain parsed")
        }
        if case .tag(let duplicateName) = document.lines[2] {
            #expect(duplicateName.name == "work")
        } else {
            Issue.record("duplicate name definition should remain parsed")
        }
    }
    @Test("renaming and recoloring retain references after reload")
    func renameRetainsAssignments() {
        var document = TodoMarkdownParser.parse("""
        <!-- zutun-tag: {"id":"work","name":"Work","color":"#112233"} -->
        - [ ] Open <!-- zutun-tags: ["work"] -->
        - [x] Done <!-- zutun-tags: ["work"] -->
        """)
        let changed = document.upsertTag(TodoTag(id: "work", name: "Office", color: "#445566"))
        #expect(changed)
        let reloaded = TodoMarkdownParser.parse(document.renderedMarkdown())
        #expect(reloaded.tags.first?.name == "Office")
        #expect(reloaded.tags.first?.color == "#445566")
        #expect(reloaded.todos.allSatisfy { $0.tagIDs == ["work"] })
    }

    @Test("deleting duplicate definitions cannot resurrect a tag")
    func deleteDuplicateDefinitions() {
        var document = TodoMarkdownParser.parse("""
        <!-- zutun-tag: {"id":"work","name":"Work","color":"#112233"} -->
        <!-- zutun-tag: {"id":"work","name":"Duplicate","color":"#445566"} -->
        - [ ] Open <!-- zutun-tags: ["work"] -->
        - [x] Done <!-- zutun-tags: ["work"] -->
        """)
        let removed = document.removeTag(id: "work")
        #expect(removed)
        let reloaded = TodoMarkdownParser.parse(document.renderedMarkdown())
        #expect(reloaded.tags.isEmpty)
        #expect(reloaded.todos.count == 2)
        #expect(reloaded.todos.allSatisfy { $0.tagIDs.isEmpty })
    }

}

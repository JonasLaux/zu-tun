import AppKit
import Foundation
import Testing
@testable import ZuTun
@testable import ZuTunCore

@Suite("TodoStore sharing")
@MainActor
struct TodoStoreSharingTests {
    @Test("first copy persists a stable ID and copies a skill-aware prompt")
    func firstCopyPersistsReferenceAndPrompt() throws {
        let fixture = try makeFixture(
            """
            # Todo

            - [ ] (P2) Prepare the release

            """
        )
        defer { fixture.cleanup() }

        fixture.store.reloadFromDisk()
        let item = try #require(fixture.store.document.todos.first)
        let originalMarkdown = try fixture.readMarkdown()

        #expect(fixture.store.copyForAgent(item))

        let copiedMarkdown = try fixture.readMarkdown()
        let copiedItem = try #require(TodoMarkdownParser.parse(copiedMarkdown).todos.first)
        let referenceID = try #require(copiedItem.referenceID)
        let prompt = try #require(fixture.pasteboard.string(forType: .string))

        #expect(copiedMarkdown != originalMarkdown)
        #expect(copiedMarkdown.contains("<!-- zutun-id: \(referenceID.uuidString) -->"))
        #expect(copiedItem.title == item.title)
        #expect(prompt.contains("global zu-tun skill"))
        #expect(prompt.contains(fixture.fileURL.path))
        #expect(prompt.contains(copiedItem.title))
        #expect(prompt.contains(referenceID.uuidString))
        #expect(fixture.store.copiedReferenceID == referenceID)
    }

    @Test("repeating a copy reuses the persisted reference without changing the file")
    func repeatingCopyDoesNotChangeFile() throws {
        let fixture = try makeFixture(
            """
            # Todo

            - [ ] Keep the same reference

            """
        )
        defer { fixture.cleanup() }

        fixture.store.reloadFromDisk()
        let item = try #require(fixture.store.document.todos.first)
        #expect(fixture.store.copyForAgent(item))
        let firstMarkdown = try fixture.readMarkdown()
        let firstPrompt = try #require(fixture.pasteboard.string(forType: .string))

        let sharedItem = try #require(fixture.store.document.todos.first)
        #expect(fixture.store.copyForAgent(sharedItem))

        #expect(try fixture.readMarkdown() == firstMarkdown)
        #expect(fixture.pasteboard.string(forType: .string) == firstPrompt)
        #expect(fixture.store.copiedReferenceID == sharedItem.referenceID)
    }

    @Test("copying immediately after adding a todo handles its runtime ID")
    func copyAfterAddingTodo() throws {
        let fixture = try makeFixture(
            """
            # Todo

            """
        )
        defer { fixture.cleanup() }

        fixture.store.reloadFromDisk()
        fixture.store.addTodo(title: "Added without reload", priority: .p2)
        let added = try #require(fixture.store.document.todos.first)

        #expect(fixture.store.copyForAgent(added))
        let saved = try fixture.readMarkdown()
        let copied = try #require(TodoMarkdownParser.parse(saved).todos.first)
        let prompt = try #require(fixture.pasteboard.string(forType: .string))
        #expect(copied.title == added.title)
        let referenceID = try #require(copied.referenceID)
        #expect(saved.contains("<!-- zutun-id: \(referenceID.uuidString) -->"))
        #expect(prompt.contains(added.title))
    }

    @Test("copying immediately after a title edit handles its runtime ID")
    func copyAfterTitleEdit() throws {
        let fixture = try makeFixture(
            """
            # Todo

            - [ ] Before the edit

            """
        )
        defer { fixture.cleanup() }

        fixture.store.reloadFromDisk()
        let item = try #require(fixture.store.document.todos.first)
        #expect(fixture.store.updateTitle("After the edit", for: item))
        let renamed = try #require(fixture.store.document.todos.first)

        #expect(fixture.store.copyForAgent(renamed))
        let saved = try fixture.readMarkdown()
        let copied = try #require(TodoMarkdownParser.parse(saved).todos.first)
        #expect(copied.title == "After the edit")
        #expect(fixture.pasteboard.string(forType: .string)?.contains("After the edit") == true)
    }

    @Test("multiline titles survive add, edit, reload, and copy without shifting following lines")
    func multilineTitleRoundTripsThroughStore() throws {
        let fixture = try makeFixture(
            """
            # Todo

            - [x] Existing completed task

            """
        )
        defer { fixture.cleanup() }

        fixture.store.reloadFromDisk()
        let addedTitle = "First line\n\nSecond **bold**\n- [ ] Pasted checkbox"
        fixture.store.addTodo(title: addedTitle, priority: .p2)
        let added = try #require(fixture.store.document.todos.first)

        #expect(added.title == addedTitle)
        #expect(fixture.store.document.todos.last?.title == "Existing completed task")

        let editedTitle = "Edited **title**\n\nKeep [context](https://example.com)\n- [ ] Still one task"
        #expect(fixture.store.updateTitle(editedTitle, for: added))

        fixture.store.reloadFromDisk()
        let reloaded = try #require(fixture.store.document.todos.first)
        let beforeCopy = try fixture.readMarkdown()
        let physicalLines = beforeCopy.components(separatedBy: "\n")

        #expect(reloaded.title == editedTitle)
        #expect(physicalLines[2].contains("Edited **title**<br><br>Keep [context](https://example.com)<br>- [ ] Still one task"))
        #expect(physicalLines[3] == "- [x] Existing completed task")
        #expect(TodoMarkdownParser.parse(beforeCopy).todos.count == 2)

        #expect(fixture.store.copyForAgent(reloaded))
        let copiedMarkdown = try fixture.readMarkdown()
        let copied = try #require(TodoMarkdownParser.parse(copiedMarkdown).todos.first)
        let prompt = try #require(fixture.pasteboard.string(forType: .string))

        #expect(copied.title == editedTitle)
        #expect(copiedMarkdown.components(separatedBy: "\n")[3] == physicalLines[3])
        #expect(prompt.contains("Current title: \(editedTitle)"))
        #expect(prompt.contains("Line hint: 3 (1-based)"))
    }

    @Test("break markers stay in sync through add, reload, and copy")
    func breakMarkerRoundTripsThroughCopy() throws {
        let fixture = try makeFixture(
            """
            # Todo

            """
        )
        defer { fixture.cleanup() }

        fixture.store.reloadFromDisk()
        fixture.store.addTodo(title: "First<br>Second", priority: .p2)
        let added = try #require(fixture.store.document.todos.first)

        #expect(added.title == "First\nSecond")
        #expect(fixture.store.copyForAgent(added))

        fixture.store.reloadFromDisk()
        let reloaded = try #require(fixture.store.document.todos.first)
        let saved = try fixture.readMarkdown()
        let prompt = try #require(fixture.pasteboard.string(forType: .string))

        #expect(reloaded.title == "First\nSecond")
        #expect(saved.contains("First<br>Second <!-- zutun-id:"))
        #expect(prompt.contains("Current title: First\nSecond"))
    }

    @Test("an external file change refuses to copy and leaves the clipboard untouched")
    func externalChangeRefusesCopy() throws {
        let fixture = try makeFixture(
            """
            # Todo

            - [ ] Original task

            """
        )
        defer { fixture.cleanup() }

        fixture.store.reloadFromDisk()
        let item = try #require(fixture.store.document.todos.first)
        fixture.pasteboard.clearContents()
        #expect(fixture.pasteboard.setString("leave this alone", forType: .string))
        let originalMarkdown = try fixture.readMarkdown()

        try """
        # Todo

        - [ ] Changed outside the app

        """.write(to: fixture.fileURL, atomically: true, encoding: .utf8)

        #expect(!fixture.store.copyForAgent(item))
        #expect(fixture.pasteboard.string(forType: .string) == "leave this alone")
        #expect(try fixture.readMarkdown() != originalMarkdown)
    }

    @Test("an ambiguous persisted ID refuses to copy and leaves the clipboard untouched")
    func duplicateReferenceRefusesCopy() throws {
        let duplicateID = UUID()
        let fixture = try makeFixture(
            """
            # Todo

            - [ ] First copy target <!-- zutun-id: \(duplicateID.uuidString) -->
            - [ ] Second copy target <!-- zutun-id: \(duplicateID.uuidString) -->

            """
        )
        defer { fixture.cleanup() }

        fixture.store.reloadFromDisk()
        let item = try #require(fixture.store.document.todos.first)
        fixture.pasteboard.clearContents()
        #expect(fixture.pasteboard.setString("leave this alone", forType: .string))
        let originalMarkdown = try fixture.readMarkdown()

        #expect(!fixture.store.copyForAgent(item))
        #expect(fixture.pasteboard.string(forType: .string) == "leave this alone")
        #expect(try fixture.readMarkdown() == originalMarkdown)
    }

    private func makeFixture(_ markdown: String) throws -> Fixture {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZuTunTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fileURL = folder.appendingPathComponent("todo.md")
        try markdown.write(to: fileURL, atomically: true, encoding: .utf8)

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ZuTunTests-\(UUID().uuidString)"))
        let store = TodoStore(fileURL: fileURL, pasteboard: pasteboard, syncsWidget: false)
        return Fixture(folder: folder, fileURL: fileURL, pasteboard: pasteboard, store: store)
    }
}

@MainActor
private struct Fixture {
    let folder: URL
    let fileURL: URL
    let pasteboard: NSPasteboard
    let store: TodoStore

    func readMarkdown() throws -> String {
        try String(contentsOf: fileURL, encoding: .utf8)
    }

    func cleanup() {
        pasteboard.clearContents()
        try? FileManager.default.removeItem(at: folder)
    }
}

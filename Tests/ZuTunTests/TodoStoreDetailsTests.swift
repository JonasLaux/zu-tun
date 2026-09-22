import AppKit
import Foundation
import Testing
@testable import ZuTun
@testable import ZuTunCore

@Suite("TodoStore details")
@MainActor
struct TodoStoreDetailsTests {
    @Test("saving details creates a stable owner and keeps the overview separate")
    func saveDetails() throws {
        let fixture = try DetailsFixture("- [ ] (P2) Fix query retries\n- [ ] Another task\n")
        defer { fixture.cleanup() }
        let original = try #require(fixture.store.document.todos.first)
        let details = TodoDetails(state: "Waiting for review", outcome: "Test passes.\n[PR](https://example.com/pr)")

        #expect(fixture.store.updateTodo(title: original.title, details: details, for: original))
        fixture.store.reloadFromDisk()
        let saved = try #require(fixture.store.document.todos.first)
        let referenceID = try #require(saved.referenceID)
        let markdown = try fixture.markdown()

        #expect(saved.title == original.title)
        #expect(saved.details == details)
        #expect(!saved.isCompleted)
        #expect(saved.parking == nil)
        #expect(fixture.store.activeTodos.count == 2)
        #expect(markdown.contains("zutun-details-for: \(referenceID.uuidString)"))
        #expect(markdown.components(separatedBy: "zutun-id:").count == 2)
        #expect(!saved.markdownLine.contains("Waiting for review"))
    }

    @Test("title edits preserve details and clearing details keeps the stable ID")
    func editAndClearDetails() throws {
        let fixture = try DetailsFixture()
        defer { fixture.cleanup() }
        let original = try #require(fixture.store.document.todos.first)
        #expect(fixture.store.updateTitle("Renamed task", for: original))
        fixture.store.reloadFromDisk()
        let renamed = try #require(fixture.store.document.todos.first)
        #expect(renamed.details == original.details)
        #expect(renamed.referenceID == original.referenceID)

        #expect(fixture.store.updateTodo(title: renamed.title, details: TodoDetails(state: " \n", outcome: "  "), for: renamed))
        fixture.store.reloadFromDisk()
        let cleared = try #require(fixture.store.document.todos.first)
        #expect(cleared.details == nil)
        #expect(cleared.referenceID == original.referenceID)
        #expect(!(try fixture.markdown()).contains("zutun-details"))
    }

    @Test("sharing after a details block uses the physical source line and preserves the block")
    func shareFollowingTodo() throws {
        let fixture = try DetailsFixture(DetailsFixture.source + "- [ ] Share this task\n")
        defer { fixture.cleanup() }
        let originalDetails = fixture.store.document.todos.first?.details
        let target = try #require(fixture.store.document.todos.last)
        let before = try fixture.markdown()
        let physicalLine = try #require(before.components(separatedBy: "\n").firstIndex { $0 == "- [ ] Share this task" }) + 1

        #expect(fixture.store.copyForAgent(target))
        let prompt = try #require(fixture.pasteboard.string(forType: .string))
        #expect(prompt.contains("Line hint: \(physicalLine) (1-based)"))
        #expect(prompt.contains("Current title: Share this task"))
        #expect(fixture.store.document.todos.first?.details == originalDetails)
        #expect(try fixture.markdown().hasPrefix(DetailsFixture.source))
    }

    @Test("an editor opened before an external details update cannot overwrite it", arguments: [false, true])
    func staleEditor(reloadBeforeSave: Bool) throws {
        let fixture = try DetailsFixture()
        defer { fixture.cleanup() }
        let original = try #require(fixture.store.document.todos.first)
        let external = DetailsFixture.source.replacingOccurrences(of: "Waiting for review", with: "Review complete; waiting for deployment")
        try external.write(to: fixture.fileURL, atomically: true, encoding: .utf8)
        if reloadBeforeSave { fixture.store.reloadFromDisk() }

        #expect(!fixture.store.updateTodo(title: original.title, details: TodoDetails(state: "Stale edit"), for: original))
        #expect(try fixture.markdown() == external)
        #expect(fixture.store.document.todos.first?.details?.state == "Review complete; waiting for deployment")
        #expect(fixture.store.errorMessage != nil)
    }

    @Test("list actions do not overwrite externally updated details", arguments: ["toggle", "priority", "delete", "move"])
    func staleListAction(action: String) throws {
        let fixture = try DetailsFixture()
        defer { fixture.cleanup() }
        let original = try #require(fixture.store.document.todos.first)
        let external = DetailsFixture.source.replacingOccurrences(of: "Waiting for review", with: "New information from another editor")
        try external.write(to: fixture.fileURL, atomically: true, encoding: .utf8)

        switch action {
        case "toggle": fixture.store.toggle(original)
        case "priority": fixture.store.setPriority(.p1, for: original)
        case "delete": fixture.store.delete(original)
        default: _ = fixture.store.moveTodos(ids: [original.id], to: .p3)
        }

        #expect(try fixture.markdown() == external)
        #expect(fixture.store.document.todos.first?.details?.state == "New information from another editor")
        #expect(fixture.store.errorMessage != nil)
    }

    @Test("parking, moving, completing, and deleting retain owned details correctly")
    func listLifecycle() throws {
        let fixture = try DetailsFixture()
        defer { fixture.cleanup() }
        let original = try #require(fixture.store.document.todos.first)
        #expect(fixture.store.setParking(.indefinite, for: original))
        let parked = try #require(fixture.store.parkedTodos.first)
        #expect(parked.details == original.details)
        #expect(fixture.store.moveTodos(ids: [parked.id], to: .p1))
        let moved = try #require(fixture.store.activeTodos.first)
        #expect(moved.details == original.details)
        fixture.store.toggle(moved)
        fixture.store.reloadFromDisk()
        let completed = try #require(fixture.store.document.completedTodos.first)
        #expect(completed.details == original.details)
        fixture.store.delete(completed)
        #expect(fixture.store.document.todos.isEmpty)
        #expect(!(try fixture.markdown()).contains("zutun-details"))
    }

    @Test("conflicting owner blocks cannot be overwritten by the details editor")
    func conflictingDetails() throws {
        let conflicting = DetailsFixture.source + "  > [!zutun]- Details <!-- zutun-details-for: \(DetailsFixture.referenceID) -->\n  > **State:** Other state\n  > <!-- zutun-details-end -->\n"
        let fixture = try DetailsFixture(conflicting)
        defer { fixture.cleanup() }
        let original = try #require(fixture.store.document.todos.first)
        #expect(!fixture.store.updateTodo(title: original.title, details: TodoDetails(state: "New state"), for: original))
        #expect(try fixture.markdown() == conflicting)
    }
}

@MainActor
private struct DetailsFixture {
    static let referenceID = "7151B593-3789-459A-8490-1AE76E448070"
    static let source = """
    - [ ] (P2) Fix query retries <!-- zutun-id: \(referenceID) -->
      > [!zutun]- Details <!-- zutun-details-for: \(referenceID) -->
      > **State:** Waiting for review
      > **Outcome:** [Regression test](https://example.com/test) passes.
      > <!-- zutun-details-end -->

    """

    let folder: URL
    let fileURL: URL
    let store: TodoStore
    let pasteboard: NSPasteboard

    init(_ markdown: String = Self.source) throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("ZuTunDetailsTests-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("todo.md")
        try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
        pasteboard = NSPasteboard(name: NSPasteboard.Name("ZuTunDetailsTests-\(UUID())"))
        store = TodoStore(fileURL: fileURL, pasteboard: pasteboard, syncsWidget: false)
        store.reloadFromDisk()
    }

    func markdown() throws -> String { try String(contentsOf: fileURL, encoding: .utf8) }

    func cleanup() {
        pasteboard.clearContents()
        try? FileManager.default.removeItem(at: folder)
    }
}

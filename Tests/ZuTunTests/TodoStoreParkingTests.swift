import AppKit
import Foundation
import Testing
@testable import ZuTun
@testable import ZuTunCore

@Suite("TodoStore parking")
@MainActor
struct TodoStoreParkingTests {
    @Test("parking survives reload and keeps task details")
    func parkingPersists() throws {
        let fixture = try ParkingFixture()
        defer { fixture.cleanup() }
        let item = try #require(fixture.store.activeTodos.first)
        let until = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) + 3600)

        #expect(fixture.store.setParking(.until(until), for: item))
        #expect(fixture.store.activeTodos.isEmpty)
        #expect(fixture.store.parkedTodos.count == 1)
        fixture.store.reloadFromDisk()
        let parked = try #require(fixture.store.parkedTodos.first)
        #expect(parked.parking == .until(until))
        #expect(parked.title == item.title)
        #expect(parked.priority == item.priority)
        #expect(parked.referenceID == item.referenceID)
        #expect(parked.tagIDs == item.tagIDs)
        #expect(fixture.store.document.completedTodos.isEmpty)
    }

    @Test("expiry restores visibility without modifying the file or completing the task")
    func expiryRestoresWithoutWriting() throws {
        let fixture = try ParkingFixture()
        defer { fixture.cleanup() }
        let item = try #require(fixture.store.activeTodos.first)
        let until = Date().addingTimeInterval(3600)
        #expect(fixture.store.setParking(.until(until), for: item))
        let saved = try fixture.markdown()

        fixture.store.refreshParking(at: until.addingTimeInterval(-1))
        #expect(fixture.store.activeTodos.isEmpty)
        fixture.store.refreshParking(at: until)
        #expect(fixture.store.activeTodos.map(\.title) == [item.title])
        #expect(fixture.store.parkedTodos.isEmpty)
        #expect(fixture.store.document.completedTodos.isEmpty)
        #expect(try fixture.markdown() == saved)
    }

    @Test("indefinite parking can be brought back early")
    func bringBack() throws {
        let fixture = try ParkingFixture()
        defer { fixture.cleanup() }
        let item = try #require(fixture.store.activeTodos.first)
        #expect(fixture.store.setParking(.indefinite, for: item))
        fixture.store.refreshParking(at: Date().addingTimeInterval(365 * 86400))
        #expect(fixture.store.activeTodos.isEmpty)
        let parked = try #require(fixture.store.parkedTodos.first)
        #expect(fixture.store.setParking(nil, for: parked))
        #expect(fixture.store.activeTodos.count == 1)
        #expect(!((try fixture.markdown()).contains("zutun-parked:")))
    }

    @Test("past dates are rejected without changing the task")
    func rejectPastDate() throws {
        let fixture = try ParkingFixture()
        defer { fixture.cleanup() }
        let item = try #require(fixture.store.activeTodos.first)
        let original = try fixture.markdown()
        #expect(!fixture.store.setParking(.until(Date().addingTimeInterval(-1)), for: item))
        #expect(fixture.store.activeTodos.count == 1)
        #expect(fixture.store.errorMessage != nil)
        #expect(try fixture.markdown() == original)
    }

    @Test("stale parking actions never overwrite external edits")
    func rejectExternalChange() throws {
        let fixture = try ParkingFixture()
        defer { fixture.cleanup() }
        let item = try #require(fixture.store.activeTodos.first)
        let external = "# Todo\n\n- [ ] Changed externally with more context\n"
        try external.write(to: fixture.fileURL, atomically: true, encoding: .utf8)
        #expect(!fixture.store.setParking(.indefinite, for: item))
        #expect(try fixture.markdown() == external)
        #expect(fixture.store.parkedTodos.isEmpty)
    }

    @Test("bringing a parked todo into a priority group makes it active")
    func dragRestoresTask() throws {
        let fixture = try ParkingFixture()
        defer { fixture.cleanup() }
        let item = try #require(fixture.store.activeTodos.first)
        #expect(fixture.store.setParking(.indefinite, for: item))
        let parked = try #require(fixture.store.parkedTodos.first)
        #expect(fixture.store.moveTodos(ids: [parked.id], to: .p1))
        #expect(fixture.store.activeTodos.first?.priority == .p1)
        #expect(fixture.store.parkedTodos.isEmpty)
    }

    @Test("sharing a parked todo preserves its parking metadata")
    func sharingPreservesParking() throws {
        let fixture = try ParkingFixture()
        defer { fixture.cleanup() }
        let item = try #require(fixture.store.activeTodos.first)
        #expect(fixture.store.setParking(.indefinite, for: item))
        let parked = try #require(fixture.store.parkedTodos.first)
        #expect(fixture.store.copyForAgent(parked))
        fixture.store.reloadFromDisk()
        #expect(fixture.store.parkedTodos.first?.parking == .indefinite)
        #expect(fixture.store.activeTodos.isEmpty)
    }
}

@MainActor
private struct ParkingFixture {
    let folder: URL
    let fileURL: URL
    let store: TodoStore
    let pasteboard: NSPasteboard

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("ZuTunParkingTests-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("todo.md")
        try "# Todo\n\n- [ ] (P2) Wait for approval <!-- zutun-id: 7151B593-3789-459A-8490-1AE76E448070 --> <!-- zutun-tags: [\"work\"] -->\n"
            .write(to: fileURL, atomically: true, encoding: .utf8)
        pasteboard = NSPasteboard(name: NSPasteboard.Name("ZuTunParkingTests-\(UUID())"))
        store = TodoStore(fileURL: fileURL, pasteboard: pasteboard, syncsWidget: false)
        store.reloadFromDisk()
    }

    func markdown() throws -> String { try String(contentsOf: fileURL, encoding: .utf8) }

    func cleanup() {
        pasteboard.clearContents()
        try? FileManager.default.removeItem(at: folder)
    }
}

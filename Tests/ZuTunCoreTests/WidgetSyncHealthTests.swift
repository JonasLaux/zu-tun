import Foundation
import Testing
@testable import ZuTunCore

@Suite("Widget sync health")
struct WidgetSyncHealthTests {
    @Test("reports stale when selected todo and widget cache differ")
    func reportsStaleWhenDocumentsDiffer() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let todoURL = folder.appendingPathComponent("todo.md")
        let widgetURL = folder.appendingPathComponent("widget-todo.md")

        try """
        # Todo

        - [ ] (P2) Current task

        """.write(to: todoURL, atomically: true, encoding: .utf8)
        try """
        # Todo

        - [ ] (P2) Old task

        """.write(to: widgetURL, atomically: true, encoding: .utf8)

        let health = WidgetSyncHealth.current(todoURL: todoURL, widgetURL: widgetURL)

        #expect(health.state == .stale)
    }

    @Test("reports synced when selected todo and widget cache match")
    func reportsSyncedWhenDocumentsMatch() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let todoURL = folder.appendingPathComponent("todo.md")
        let widgetURL = folder.appendingPathComponent("widget-todo.md")
        let markdown = """
        # Todo

        - [ ] (P2) Same task

        """

        try markdown.write(to: todoURL, atomically: true, encoding: .utf8)
        try markdown.write(to: widgetURL, atomically: true, encoding: .utf8)

        let health = WidgetSyncHealth.current(todoURL: todoURL, widgetURL: widgetURL)

        #expect(health.state == .synced)
    }

    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZuTunCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

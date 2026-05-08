import Foundation

public enum TodoLocation {
    public static let appGroupIdentifier = "X38QBU523M.dev.jonaslaux.ZuTun"
    public static let didChangeNotification = Notification.Name("dev.jonaslaux.ZuTun.TodoLocation.didChange")

    private static let folderBookmarkKey = "folderBookmark"
    private static let todoFileName = "todo.md"
    private static let sidecarFileName = "todo-path.txt"
    private static let pendingWidgetTogglesFileName = "pending-widget-toggles.txt"

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    public static var appGroupContainerURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    public static var appGroupTodoURL: URL {
        if let container = appGroupContainerURL {
            return container.appendingPathComponent(todoFileName)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(todoFileName)
    }

    public static var pathSidecarURL: URL? {
        appGroupContainerURL?.appendingPathComponent(sidecarFileName)
    }

    public static var pendingWidgetTogglesURL: URL? {
        appGroupContainerURL?.appendingPathComponent(pendingWidgetTogglesFileName)
    }

    public static func publishPathSidecar() {
        guard let sidecar = pathSidecarURL else {
            return
        }

        let path = currentTodoURL.path
        try? FileManager.default.createDirectory(
            at: sidecar.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? path.write(to: sidecar, atomically: true, encoding: .utf8)
    }

    public static var currentFolderURL: URL {
        resolveBookmarkedFolder() ?? defaultFolderURL
    }

    public static var currentTodoURL: URL {
        currentFolderURL.appendingPathComponent(todoFileName)
    }

    public static var hasCustomFolder: Bool {
        sharedDefaults?.data(forKey: folderBookmarkKey) != nil
    }

    public static var defaultFolderURL: URL {
        if let container = appGroupContainerURL {
            return container
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    public static func setFolder(_ url: URL) throws {
        let bookmark = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        sharedDefaults?.set(bookmark, forKey: folderBookmarkKey)
        publishPathSidecar()
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    public static func clearFolder() {
        sharedDefaults?.removeObject(forKey: folderBookmarkKey)
        publishPathSidecar()
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    public static func enqueuePendingWidgetToggle(id: UUID) throws {
        guard hasCustomFolder, let url = pendingWidgetTogglesURL else {
            return
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let contents = existing + id.uuidString + "\n"
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    public static func consumePendingWidgetToggleIDs() throws -> [UUID] {
        guard let url = pendingWidgetTogglesURL, FileManager.default.fileExists(atPath: url.path) else {
            return []
        }

        let contents = try String(contentsOf: url, encoding: .utf8)
        try? FileManager.default.removeItem(at: url)

        return contents
            .split(whereSeparator: \.isNewline)
            .compactMap { UUID(uuidString: String($0)) }
    }

    public static func withFolderAccess<T>(_ work: (URL) throws -> T) throws -> T {
        let folder = currentFolderURL
        let didStart = folder.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                folder.stopAccessingSecurityScopedResource()
            }
        }
        return try work(folder)
    }

    private static func resolveBookmarkedFolder() -> URL? {
        guard let data = sharedDefaults?.data(forKey: folderBookmarkKey) else {
            return nil
        }

        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            return nil
        }

        if stale {
            refreshBookmark(for: url)
        }

        return url
    }

    private static func refreshBookmark(for url: URL) {
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let refreshed = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return
        }

        sharedDefaults?.set(refreshed, forKey: folderBookmarkKey)
    }
}

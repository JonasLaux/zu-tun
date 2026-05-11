import Combine
import AppKit
import Foundation
import WidgetKit
import ZuTunCore

struct TodoCompletionEvent: Equatable, Identifiable {
    let id = UUID()
    var title: String
}

@MainActor
final class TodoStore: ObservableObject {
    @Published private(set) var document = TodoDocument()
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastLoadedAt: Date?
    @Published private(set) var completionEvent: TodoCompletionEvent?
    @Published private(set) var fileURL: URL
    @Published private(set) var widgetSyncHealth: WidgetSyncHealth
    @Published private(set) var installHealth = AppInstallHealth.current()

    private var lastKnownSignature: FileSignature?
    private var pollTask: Task<Void, Never>?
    private nonisolated(unsafe) var locationObserver: NSObjectProtocol?

    init(fileURL: URL = TodoLocation.currentTodoURL) {
        self.fileURL = fileURL
        self.widgetSyncHealth = WidgetSyncHealth.current(todoURL: fileURL)
    }

    deinit {
        pollTask?.cancel()
        if let observer = locationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func start() {
        guard pollTask == nil else {
            return
        }

        observeLocationChanges()
        TodoLocation.publishPathSidecar()
        refreshInstallHealth()
        reloadFromDisk()
        processPendingWidgetToggles()
        WidgetCenter.shared.reloadAllTimelines()
        pollTask = Task { [weak self] in
            await self?.pollForExternalChanges()
        }
    }

    func reloadFromDisk() {
        do {
            document = try TodoLocation.withFolderAccess { _ in
                try TodoFile.loadDocument(from: fileURL)
            }
            lastKnownSignature = try signature(for: fileURL)
            lastLoadedAt = Date()
            errorMessage = nil
            publishWidgetSnapshot()
        } catch {
            errorMessage = "Could not read \(fileURL.path): \(error.localizedDescription)"
            updateWidgetSyncHealth()
        }
    }

    func relocate() {
        let newURL = TodoLocation.currentTodoURL
        guard newURL != fileURL else {
            return
        }
        fileURL = newURL
        lastKnownSignature = nil
        reloadFromDisk()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func addTodo(title: String, priority: TodoPriority) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return
        }

        document.appendTodo(title: trimmedTitle, priority: priority)
        saveDocument()
    }

    func refreshWidgetSnapshot() {
        reloadFromDisk()
        WidgetCenter.shared.reloadAllTimelines()
    }

    var statusWarning: String? {
        if let installWarning = installHealth.warning {
            return installWarning
        }

        switch widgetSyncHealth.state {
        case .synced:
            return nil
        case .stale:
            return "Widget cache is stale"
        case .missingTodo:
            return "Todo file is missing"
        case .missingCache:
            return "Widget cache is missing"
        case .unreadable:
            return "Widget sync needs attention"
        }
    }

    func toggle(_ item: TodoItem) {
        let completedTitle = item.isCompleted ? nil : item.title

        guard document.updateTodo(id: item.id, { $0.isCompleted.toggle() }) else {
            reloadFromDisk()
            return
        }

        if saveDocument(), let completedTitle {
            announceCompletion(title: completedTitle)
        }
    }

    func setPriority(_ priority: TodoPriority?, for item: TodoItem) {
        setPriority(priority, forTodoID: item.id)
    }

    func setPriority(_ priority: TodoPriority?, forTodoID id: UUID) {
        guard document.updateTodo(id: id, { $0.priority = priority }) else {
            reloadFromDisk()
            return
        }

        saveDocument()
    }

    func delete(_ item: TodoItem) {
        deleteTodo(id: item.id)
    }

    @discardableResult
    func moveTodos(ids: [UUID], to priority: TodoPriority?) -> Bool {
        let changed = ids.reduce(false) { changed, id in
            document.updateTodo(id: id) {
                $0.isCompleted = false
                $0.priority = priority
            } || changed
        }

        if changed {
            saveDocument()
        } else {
            reloadFromDisk()
        }

        return changed
    }

    @discardableResult
    func deleteTodos(ids: [UUID]) -> Bool {
        let changed = ids.reduce(false) { changed, id in
            document.deleteTodo(id: id) || changed
        }

        if changed {
            saveDocument()
        } else {
            reloadFromDisk()
        }

        return changed
    }

    private func deleteTodo(id: UUID) {
        guard document.deleteTodo(id: id) else {
            reloadFromDisk()
            return
        }

        saveDocument()
    }

    private func observeLocationChanges() {
        guard locationObserver == nil else {
            return
        }

        locationObserver = NotificationCenter.default.addObserver(
            forName: TodoLocation.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.relocate()
            }
        }
    }

    private func pollForExternalChanges() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            processPendingWidgetToggles()
            reloadIfChanged()
        }
    }

    private func reloadIfChanged() {
        do {
            try TodoLocation.withFolderAccess { _ in
                try TodoFile.ensureExists(at: fileURL)
            }
            let currentSignature = try signature(for: fileURL)
            if currentSignature != lastKnownSignature {
                reloadFromDisk()
                WidgetCenter.shared.reloadAllTimelines()
            } else {
                updateWidgetSyncHealth()
            }
        } catch {
            errorMessage = "Could not watch \(fileURL.path): \(error.localizedDescription)"
            updateWidgetSyncHealth()
        }
    }

    @discardableResult
    private func saveDocument() -> Bool {
        do {
            try TodoLocation.withFolderAccess { _ in
                try TodoFile.save(document, to: fileURL)
            }
            lastKnownSignature = try signature(for: fileURL)
            lastLoadedAt = Date()
            errorMessage = nil
            publishWidgetSnapshot()
            WidgetCenter.shared.reloadAllTimelines()
            return true
        } catch {
            errorMessage = "Could not write \(fileURL.path): \(error.localizedDescription)"
            updateWidgetSyncHealth()
            return false
        }
    }

    private func announceCompletion(title: String) {
        completionEvent = TodoCompletionEvent(title: title)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        NSSound(named: NSSound.Name("Glass"))?.play()
    }

    private func processPendingWidgetToggles() {
        do {
            let ids = try TodoLocation.consumePendingWidgetToggleIDs()
            guard !ids.isEmpty else {
                return
            }

            var latestDocument = try TodoLocation.withFolderAccess { _ in
                try TodoFile.loadDocument(from: fileURL)
            }

            let changed = ids.reduce(false) { changed, id in
                latestDocument.updateTodo(id: id) {
                    $0.isCompleted.toggle()
                } || changed
            }

            if changed {
                try TodoLocation.withFolderAccess { _ in
                    try TodoFile.save(latestDocument, to: fileURL)
                }
                document = latestDocument
                lastKnownSignature = try signature(for: fileURL)
                lastLoadedAt = Date()
                errorMessage = nil
                publishWidgetSnapshot()
                WidgetCenter.shared.reloadAllTimelines()
            } else {
                reloadFromDisk()
            }
        } catch {
            errorMessage = "Could not apply widget update to \(fileURL.path): \(error.localizedDescription)"
        }
    }

    private func publishWidgetSnapshot() {
        do {
            try TodoFile.saveWidgetDocument(document)
        } catch {
            errorMessage = "Could not update widget cache: \(error.localizedDescription)"
        }
        updateWidgetSyncHealth()
    }

    private func signature(for url: URL) throws -> FileSignature {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let modifiedAt = attributes[.modificationDate] as? Date
        let size = (attributes[.size] as? NSNumber)?.uint64Value
        return FileSignature(modifiedAt: modifiedAt, size: size)
    }

    private func updateWidgetSyncHealth() {
        widgetSyncHealth = WidgetSyncHealth.current(todoURL: fileURL)
    }

    private func refreshInstallHealth() {
        installHealth = AppInstallHealth.current()
    }
}

private struct FileSignature: Equatable {
    var modifiedAt: Date?
    var size: UInt64?
}

struct AppInstallHealth: Equatable {
    var runningPath: String
    var warning: String?

    static func current(bundleURL: URL = Bundle.main.bundleURL) -> AppInstallHealth {
        let fileManager = FileManager.default
        let runningURL = bundleURL.standardizedFileURL.resolvingSymlinksInPath()
        let expectedURL = URL(fileURLWithPath: "/Applications/ZuTun.app")
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let legacyURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/ZuTun.app")
            .standardizedFileURL
            .resolvingSymlinksInPath()

        let warning: String?
        if runningURL == legacyURL {
            warning = "Running old app copy from ~/Applications"
        } else if fileManager.fileExists(atPath: legacyURL.path), runningURL == expectedURL {
            warning = "Old app copy exists in ~/Applications"
        } else {
            warning = nil
        }

        return AppInstallHealth(runningPath: runningURL.path, warning: warning)
    }
}

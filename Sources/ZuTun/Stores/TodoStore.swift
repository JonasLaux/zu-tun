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
    @Published private(set) var copiedReferenceID: UUID?
    @Published private(set) var fileURL: URL
    @Published private(set) var widgetSyncHealth: WidgetSyncHealth
    @Published private(set) var installHealth = AppInstallHealth.current()
    @Published private(set) var currentDate = Date()

    var activeTodos: [TodoItem] { document.activeTodos(at: currentDate) }
    var parkedTodos: [TodoItem] { document.parkedTodos(at: currentDate) }

    private var lastKnownSignature: FileSignature?
    private var pollTask: Task<Void, Never>?
    private var copyFeedbackTask: Task<Void, Never>?
    private nonisolated(unsafe) var locationObserver: NSObjectProtocol?
    private let pasteboard: NSPasteboard
    private let syncsWidget: Bool

    init(
        fileURL: URL = TodoLocation.currentTodoURL,
        pasteboard: NSPasteboard = .general,
        syncsWidget: Bool = true
    ) {
        self.fileURL = fileURL
        self.pasteboard = pasteboard
        self.syncsWidget = syncsWidget
        self.widgetSyncHealth = WidgetSyncHealth.current(todoURL: fileURL)
    }

    deinit {
        pollTask?.cancel()
        copyFeedbackTask?.cancel()
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
            currentDate = Date()
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
        let trimmedTitle = TodoTextFormatting.normalizedTitle(title)
        guard !trimmedTitle.isEmpty else {
            return
        }

        document.appendTodo(title: trimmedTitle, priority: priority)
        saveDocument()
    }

    @discardableResult
    func updateTitle(_ title: String, for item: TodoItem) -> Bool {
        updateTodo(title: title, details: item.details, for: item)
    }

    @discardableResult
    func updateTodo(title: String, details: TodoDetails?, for item: TodoItem) -> Bool {
        let title = TodoTextFormatting.normalizedTitle(title)
        guard !title.isEmpty else { return false }
        let normalizedDetails = details.map {
            TodoDetails(
                state: TodoTextFormatting.normalizedTitle($0.state),
                outcome: TodoTextFormatting.normalizedTitle($0.outcome)
            )
        }
        let nextDetails = normalizedDetails.flatMap { $0.isEmpty ? nil : $0 }
        do {
            guard try signature(for: fileURL) == lastKnownSignature,
                  document.todos.contains(item) else {
                reloadFromDisk()
                errorMessage = "The todo changed while you were editing. Copy your text, reload, and try again."
                return false
            }
            let previous = document
            let previousSignature = lastKnownSignature
            if nextDetails != nil, let referenceID = item.referenceID,
               document.todos.filter({ $0.referenceID == referenceID }).count != 1 {
                errorMessage = "This todo's stable ID is duplicated. Give each task its own ID before editing details."
                return false
            }
            let referenceID = item.referenceID ?? (nextDetails == nil ? nil : UUID())
            guard document.updateTodo(id: item.id, {
                $0.title = title
                $0.details = nextDetails
                $0.referenceID = referenceID
            }) else { return false }
            // Do not write an apparently valid edit into an ambiguous or
            // malformed details block left in the source by an external editor.
            if let nextDetails, let referenceID {
                let savedItems = TodoMarkdownParser.parse(document.renderedMarkdown()).todos
                    .filter { $0.referenceID == referenceID }
                guard savedItems.count == 1, savedItems.first?.details == nextDetails else {
                    document = previous
                    errorMessage = "This todo has conflicting details in the Markdown file. Fix its details block before saving."
                    return false
                }
            }
            guard saveDocument() else {
                if lastKnownSignature == previousSignature { document = previous }
                return false
            }
            return true
        } catch {
            errorMessage = "Could not read the todo file: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func copyForAgent(_ item: TodoItem) -> Bool {
        do {
            let reference = try TodoLocation.withFolderAccess { _ in
                guard try signature(for: fileURL) == lastKnownSignature,
                      document.todos.contains(item),
                      let lineNumber = document.physicalLineNumber(forTodoID: item.id) else {
                    throw TodoCopyError.changed
                }

                let markdown = try String(contentsOf: fileURL, encoding: .utf8)
                let reference = try TodoShareReference.prepare(
                    item: item, lineNumber: lineNumber, in: markdown, fileURL: fileURL
                )
                if reference.markdown != markdown {
                    guard try String(contentsOf: fileURL, encoding: .utf8) == markdown else {
                        throw TodoCopyError.changed
                    }
                    try reference.markdown.write(to: fileURL, atomically: true, encoding: .utf8)
                }
                return reference
            }

            document = TodoMarkdownParser.parse(reference.markdown)
            lastKnownSignature = try signature(for: fileURL)
            lastLoadedAt = Date()
            errorMessage = nil
            publishWidgetSnapshot()
            if syncsWidget { WidgetCenter.shared.reloadAllTimelines() }

            pasteboard.clearContents()
            guard pasteboard.setString(reference.prompt, forType: .string) else {
                errorMessage = "Could not copy to the clipboard. Please try again."
                return false
            }

            copyFeedbackTask?.cancel()
            copiedReferenceID = reference.referenceID
            copyFeedbackTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                self?.copiedReferenceID = nil
            }
            return true
        } catch {
            errorMessage = "Could not copy this todo: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func saveTag(_ tag: TodoTag) -> Bool {
        editTags { $0.upsertTag(tag) }
    }

    @discardableResult
    func removeTag(_ tag: TodoTag) -> Bool {
        editTags { $0.removeTag(id: tag.id) }
    }

    func setTags(_ ids: [String], for item: TodoItem) {
        editTags { $0.setTagIDs(ids, forTodoID: item.id) }
    }

    @discardableResult
    private func editTags(_ edit: (inout TodoDocument) -> Bool) -> Bool {
        do {
            guard try signature(for: fileURL) == lastKnownSignature else {
                reloadFromDisk()
                errorMessage = "The todo file changed. Please try your tag change again."
                return false
            }
        } catch {
            errorMessage = "Could not read the todo file: \(error.localizedDescription)"
            return false
        }
        let previous = document
        let previousSignature = lastKnownSignature
        guard edit(&document) else {
            document = previous
            errorMessage = "Use a unique, nonempty tag name and a valid color. The todo or tag may have changed."
            return false
        }
        guard saveDocument() else {
            if lastKnownSignature == previousSignature { document = previous }
            return false
        }
        return true
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

    @discardableResult
    func setParking(_ parking: TodoParking?, for item: TodoItem) -> Bool {
        let now = Date()
        if case .until(let date) = parking, date <= now || !date.timeIntervalSince1970.isFinite {
            errorMessage = "Choose a future date and time to park this todo."
            return false
        }

        do {
            guard try signature(for: fileURL) == lastKnownSignature,
                  !item.isCompleted,
                  document.todos.contains(item) else {
                reloadFromDisk()
                errorMessage = "The todo changed. Please try your parking change again."
                return false
            }
            let previous = document
            let previousSignature = lastKnownSignature
            guard document.updateTodo(id: item.id, { $0.parking = parking }) else { return false }
            guard saveDocument() else {
                if lastKnownSignature == previousSignature { document = previous }
                return false
            }
            currentDate = now
            return true
        } catch {
            errorMessage = "Could not read the todo file: \(error.localizedDescription)"
            return false
        }
    }

    // Expiry changes visibility, not the file. Checking the wall clock also
    // catches tasks that became available while the Mac was asleep.
    func refreshParking(at date: Date = Date()) {
        let visibilityChanged = document.openTodos.contains {
            $0.isParked(at: currentDate) != $0.isParked(at: date)
        }
        currentDate = date
        if visibilityChanged && syncsWidget {
            WidgetCenter.shared.reloadAllTimelines()
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
                $0.parking = nil
            } || changed
        }

        if changed {
            return saveDocument()
        }
        reloadFromDisk()
        return false
    }

    @discardableResult
    func deleteTodos(ids: [UUID]) -> Bool {
        let changed = ids.reduce(false) { changed, id in
            document.deleteTodo(id: id) || changed
        }

        if changed {
            return saveDocument()
        }
        reloadFromDisk()
        return false
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
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            refreshParking()
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
                guard try signature(for: fileURL) == lastKnownSignature else {
                    throw TodoSaveError.changed
                }
                try TodoFile.save(document, to: fileURL)
            }
            lastKnownSignature = try signature(for: fileURL)
            lastLoadedAt = Date()
            errorMessage = nil
            publishWidgetSnapshot()
            WidgetCenter.shared.reloadAllTimelines()
            return true
        } catch TodoSaveError.changed {
            reloadFromDisk()
            errorMessage = "The todo file changed. Please try your change again."
            return false
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
        guard syncsWidget else { return }
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

private enum TodoSaveError: Error {
    case changed
}

private enum TodoCopyError: LocalizedError {
    case changed

    var errorDescription: String? {
        "The todo file changed. Reload and try copying again."
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

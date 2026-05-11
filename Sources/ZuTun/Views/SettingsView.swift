import AppKit
import SwiftUI
import ZuTunCore

struct SettingsView: View {
    @ObservedObject var store: TodoStore
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Folder") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(store.fileURL.deletingLastPathComponent().path)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .truncationMode(.middle)

                        HStack(spacing: 8) {
                            Button("Choose Folder…") {
                                chooseFolder()
                            }

                            if TodoLocation.hasCustomFolder {
                                Button("Reset to Default") {
                                    TodoLocation.clearFolder()
                                    store.relocate()
                                    errorMessage = nil
                                }
                            }

                            Button("Reveal in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
                            }
                        }
                    }
                }

                Text("Zu Tun reads and writes `todo.md` inside the selected folder. If no `todo.md` exists, one is created.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Storage")
            }

            Section {
                LabeledContent("Status") {
                    WidgetSyncStatusView(health: store.widgetSyncHealth)
                }

                LabeledContent("Todo File") {
                    PathValueView(path: store.widgetSyncHealth.todoURL.path)
                }

                LabeledContent("Widget Cache") {
                    PathValueView(path: store.widgetSyncHealth.widgetURL.path)
                }

                LabeledContent("Cache Updated") {
                    Text(cacheUpdatedText)
                        .foregroundStyle(.secondary)
                }

                if let warning = store.installHealth.warning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }

                Button {
                    store.refreshWidgetSnapshot()
                } label: {
                    Label("Refresh Widget Now", systemImage: "arrow.clockwise")
                }
            } header: {
                Text("Widget Sync")
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 540, minHeight: 380)
    }

    private var cacheUpdatedText: String {
        guard let date = store.widgetSyncHealth.widgetModifiedAt else {
            return "Never"
        }

        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Todo Folder"
        panel.message = "Pick a folder for todo.md."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = store.fileURL.deletingLastPathComponent()

        guard panel.runModal() == .OK, let folder = panel.url else {
            return
        }

        do {
            try TodoLocation.setFolder(folder)
            store.relocate()
            errorMessage = nil
        } catch {
            errorMessage = "Could not save folder: \(error.localizedDescription)"
        }
    }
}

private struct WidgetSyncStatusView: View {
    var health: WidgetSyncHealth

    var body: some View {
        Label(title, systemImage: systemImage)
            .foregroundStyle(color)
            .font(.callout.weight(.medium))
    }

    private var title: String {
        switch health.state {
        case .synced:
            return "Synced"
        case .stale:
            return "Stale"
        case .missingTodo:
            return "Todo Missing"
        case .missingCache:
            return "Cache Missing"
        case .unreadable:
            return "Cannot Read"
        }
    }

    private var systemImage: String {
        switch health.state {
        case .synced:
            return "checkmark.circle.fill"
        case .stale, .missingTodo, .missingCache, .unreadable:
            return "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch health.state {
        case .synced:
            return .green
        case .stale:
            return .orange
        case .missingTodo, .missingCache, .unreadable:
            return .red
        }
    }
}

private struct PathValueView: View {
    var path: String

    var body: some View {
        Text(path)
            .font(.callout)
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .lineLimit(2)
            .truncationMode(.middle)
            .multilineTextAlignment(.trailing)
    }
}

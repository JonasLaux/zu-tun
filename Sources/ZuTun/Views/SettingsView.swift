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

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 220)
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

import AppKit
import SwiftUI
import ZuTunCore

@main
struct ZuTunApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = TodoStore()

    var body: some Scene {
        WindowGroup("Zu Tun", id: "main") {
            ContentView(store: store)
                .task {
                    store.start()
                }
        }
        .defaultSize(width: 420, height: 620)
        .commands {
            CommandMenu("Todo") {
                Button("Reload") {
                    store.reloadFromDisk()
                }
                .keyboardShortcut("r")

                Button("Open todo.md") {
                    NSWorkspace.shared.open(store.fileURL)
                }
                .keyboardShortcut("o")
            }
        }

        Settings {
            SettingsView(store: store)
        }

        MenuBarExtra("Zu Tun", systemImage: "checklist") {
            MenuBarTodoView(store: store)
                .task {
                    store.start()
                }
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

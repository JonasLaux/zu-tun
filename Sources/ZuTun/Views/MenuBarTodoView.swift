import AppKit
import SwiftUI
import ZuTunCore

struct MenuBarTodoView: View {
    @ObservedObject var store: TodoStore
    @Environment(\.openWindow) private var openWindow
    @State private var draftTitle = ""
    @State private var draftPriority: TodoPriority = .p2

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Label("Zu Tun", systemImage: "checklist")
                    .font(.headline)

                Spacer()

                Button {
                    store.reloadFromDisk()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Reload")

                Button {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Image(systemName: "macwindow")
                }
                .buttonStyle(.plain)
                .help("Open window")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if store.document.openTodos.isEmpty {
                Text("Nothing open")
                    .foregroundStyle(.secondary)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(compactGroups) { group in
                            CompactPrioritySection(group: group, store: store)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxHeight: 320)
                .animation(.spring(response: 0.28, dampingFraction: 0.82), value: store.document.openTodos.map(\.id))
            }

            Divider()

            HStack(spacing: 8) {
                Picker("Priority", selection: $draftPriority) {
                    ForEach(TodoPriority.allCases) { priority in
                        Text(priority.rawValue).tag(priority)
                    }
                }
                .labelsHidden()
                .frame(width: 68)

                TextField("New todo", text: $draftTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addDraft)

                Button(action: addDraft) {
                    Image(systemName: "plus")
                }
                .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Add")
            }
            .padding(10)
        }
        .frame(width: 340)
        .overlay(alignment: .top) {
            if let event = store.completionEvent {
                CompletionCelebrationView(event: event)
                    .id(event.id)
                    .padding(.top, 42)
                    .padding(.horizontal, 10)
                    .allowsHitTesting(false)
            }
        }
    }

    private var compactGroups: [CompactTodoGroup] {
        var groups = TodoPriority.allCases.compactMap { priority -> CompactTodoGroup? in
            let todos = store.document.openTodos.filter { $0.priority == priority }
            guard !todos.isEmpty else {
                return nil
            }
            return CompactTodoGroup(priority: priority.rawValue, todos: todos)
        }

        let unprioritized = store.document.openTodos.filter { $0.priority == nil }
        if !unprioritized.isEmpty {
            groups.append(CompactTodoGroup(priority: "No Priority", todos: unprioritized))
        }

        return groups
    }

    private func addDraft() {
        store.addTodo(title: draftTitle, priority: draftPriority)
        draftTitle = ""
    }
}

private struct CompactTodoGroup: Identifiable {
    var priority: String
    var todos: [TodoItem]

    var id: String { priority }
}

private struct CompactPrioritySection: View {
    var group: CompactTodoGroup
    @ObservedObject var store: TodoStore

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(group.priority)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.5))
                    .frame(height: 1)
            }

            ForEach(group.todos) { item in
                CompactTodoRow(item: item, store: store)
            }
        }
    }
}

private struct CompactTodoRow: View {
    var item: TodoItem
    @ObservedObject var store: TodoStore

    var body: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    store.toggle(item)
                }
            } label: {
                Image(systemName: "circle")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("Mark done")

            Text(item.title)
                .lineLimit(1)

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }
}

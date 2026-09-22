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

                Text("\(store.activeTodos.count) active")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                ManageTagsButton(store: store)

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

            if let errorMessage = store.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(10)
            }

            if store.activeTodos.isEmpty && store.parkedTodos.isEmpty {
                Text("Nothing active")
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

                        CompactParkedSectionView(store: store)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxHeight: 320)
                .animation(.spring(response: 0.28, dampingFraction: 0.82), value: store.activeTodos.map(\.id))
                .animation(.spring(response: 0.28, dampingFraction: 0.82), value: store.parkedTodos.map(\.id))
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

                TextField("New todo", text: $draftTitle, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .onSubmit(addDraft)
                    .help("Return to add. Option-Return for a new line.")

                FormatDraftButton(text: $draftTitle)

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
            let todos = store.activeTodos.filter { $0.priority == priority }
            guard !todos.isEmpty else {
                return nil
            }
            return CompactTodoGroup(priority: priority.rawValue, todos: todos)
        }

        let unprioritized = store.activeTodos.filter { $0.priority == nil }
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

            ForEach(todoDetailsRows(for: group.todos)) { row in
                CompactTodoRow(item: row.item, store: store)
            }
        }
    }
}

private struct CompactTodoRow: View {
    var item: TodoItem
    @ObservedObject var store: TodoStore
    @State private var isParkingPickerPresented = false
    @State private var isDetailsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
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

                if let details = item.details, !details.isEmpty {
                    TodoDetailsToggle(
                        title: item.title,
                        compact: true,
                        isExpanded: $isDetailsExpanded
                    )
                }

                VStack(alignment: .leading, spacing: 3) {
                    TodoTitleView(title: item.title, compact: true, expanded: true)
                    if store.document.tags.contains(where: { item.tagIDs.contains($0.id) }) {
                        TagBadges(item: item, tags: store.document.tags)
                    }
                }

                Spacer(minLength: 4)
                TodoActionsMenu(item: item, store: store)
            }

            if isDetailsExpanded, let details = item.details, !details.isEmpty {
                TodoDetailsView(details: details, compact: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 48)
                    .padding(.top, 3)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                store.copyForAgent(item)
            } label: {
                Label("Copy for Agent", systemImage: "square.and.arrow.up")
            }

            Divider()

            Menu("Park…") {
                ParkingMenuContents(item: item, store: store, onChooseDate: showParkingPicker)
            }

            Button("Mark Done") {
                store.toggle(item)
            }
        }
        .popover(isPresented: $isParkingPickerPresented, arrowEdge: .bottom) {
            ParkingDateTimePicker(item: item, store: store)
        }
    }

    private func showParkingPicker() {
        isParkingPickerPresented = true
    }
}

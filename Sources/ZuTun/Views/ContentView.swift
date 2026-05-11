import AppKit
import SwiftUI
import ZuTunCore

struct ContentView: View {
    @ObservedObject var store: TodoStore
    @State private var draftTitle = ""
    @State private var draftPriority: TodoPriority = .p2
    @FocusState private var isDraftFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(store: store)

            if let errorMessage = store.errorMessage {
                ErrorBanner(message: errorMessage)
            }

            Divider()

            TodoBoardView(store: store)

            Divider()

            BottomBarView(
                store: store,
                draftTitle: $draftTitle,
                draftPriority: $draftPriority,
                isDraftFocused: $isDraftFocused,
                onAdd: addDraft
            )
        }
        .frame(minWidth: 440, minHeight: 520)
        .overlay(alignment: .top) {
            if let event = store.completionEvent {
                CompletionCelebrationView(event: event)
                    .id(event.id)
                    .padding(.top, 54)
                    .allowsHitTesting(false)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    store.reloadFromDisk()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload")

                Button {
                    NSWorkspace.shared.open(store.fileURL)
                } label: {
                    Image(systemName: "doc.text")
                }
                .help("Open todo.md")
            }
        }
    }

    private func addDraft() {
        store.addTodo(title: draftTitle, priority: draftPriority)
        draftTitle = ""
        isDraftFocused = true
    }
}

private struct HeaderView: View {
    @ObservedObject var store: TodoStore

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text("Zu Tun")
                    .font(.headline)

                Text(store.fileURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let statusWarning = store.statusWarning {
                    Label(statusWarning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(store.document.openTodos.count)")
                    .font(.title3.monospacedDigit())
                    .fontWeight(.semibold)

                Text("open")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct ErrorBanner: View {
    var message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.red)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.red.opacity(0.08))
    }
}

struct CompletionCelebrationView: View {
    var event: TodoCompletionEvent
    @State private var isVisible = false
    @State private var isBursting = false

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                ForEach(0..<6, id: \.self) { index in
                    Circle()
                        .fill(sparkColor(at: index))
                        .frame(width: 3, height: 3)
                        .offset(y: isBursting ? -18 : -5)
                        .rotationEffect(.degrees(Double(index) * 60))
                        .opacity(isBursting ? 0 : 1)
                }

                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.green)
                    .font(.title3)
            }
            .frame(width: 26, height: 26)

            Text("Done: \(event.title)")
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: 320, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.green.opacity(0.32), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.94)
        .offset(y: isVisible ? 0 : -8)
        .task(id: event.id) {
            isVisible = false
            isBursting = false

            withAnimation(.spring(response: 0.24, dampingFraction: 0.74)) {
                isVisible = true
            }

            withAnimation(.easeOut(duration: 0.45).delay(0.05)) {
                isBursting = true
            }

            try? await Task.sleep(for: .milliseconds(1150))

            withAnimation(.easeOut(duration: 0.22)) {
                isVisible = false
            }
        }
    }

    private func sparkColor(at index: Int) -> Color {
        switch index % 3 {
        case 0:
            .green
        case 1:
            .accentColor
        default:
            .orange
        }
    }
}

private struct TodoBoardView: View {
    @ObservedObject var store: TodoStore

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(priorityGroups) { group in
                    PrioritySectionView(group: group, store: store)
                }

                if !store.document.completedTodos.isEmpty {
                    DoneSectionView(todos: store.document.completedTodos, store: store)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: store.document.openTodos.map(\.id))
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: store.document.completedTodos.map(\.id))
    }

    private var priorityGroups: [TodoPriorityGroup] {
        var groups = TodoPriority.allCases.map { priority in
            TodoPriorityGroup(
                priority: priority,
                title: priority.rawValue,
                todos: store.document.openTodos.filter { $0.priority == priority }
            )
        }

        let unprioritized = store.document.openTodos.filter { $0.priority == nil }
        if !unprioritized.isEmpty {
            groups.append(TodoPriorityGroup(priority: nil, title: "No Priority", todos: unprioritized))
        }

        return groups
    }
}

private struct TodoPriorityGroup: Identifiable {
    var priority: TodoPriority?
    var title: String
    var todos: [TodoItem]

    var id: String {
        priority?.rawValue ?? "none"
    }
}

private struct PrioritySectionView: View {
    var group: TodoPriorityGroup
    @ObservedObject var store: TodoStore
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: group.title, count: group.todos.count)

            if group.todos.isEmpty {
                EmptySectionRow()
            } else {
                ForEach(group.todos) { item in
                    TodoRow(item: item, store: store)
                }
            }
        }
        .padding(10)
        .background(sectionBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isTargeted ? Color.accentColor : Color.secondary.opacity(0.14), lineWidth: isTargeted ? 2 : 1)
        }
        .dropDestination(
            for: String.self,
            action: { payloads, _ in
                store.moveTodos(ids: todoIDs(from: payloads), to: group.priority)
            },
            isTargeted: { isTargeted = $0 }
        )
    }

    private var sectionBackground: some ShapeStyle {
        isTargeted ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.06)
    }
}

private struct DoneSectionView: View {
    var todos: [TodoItem]
    @ObservedObject var store: TodoStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Done", count: todos.count)

            ForEach(todos) { item in
                TodoRow(item: item, store: store)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct SectionHeader: View {
    var title: String
    var count: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.headline)

            Text("\(count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.tertiary, in: Capsule())

            Rectangle()
                .fill(.separator.opacity(0.55))
                .frame(height: 1)
        }
    }
}

private struct EmptySectionRow: View {
    var body: some View {
        HStack {
            Image(systemName: "tray")
                .foregroundStyle(.tertiary)

            Text("Empty")
                .foregroundStyle(.secondary)
                .italic()

            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
    }
}

private struct TodoRow: View {
    var item: TodoItem
    @ObservedObject var store: TodoStore

    var body: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    store.toggle(item)
                }
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(item.isCompleted ? .green : .secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(item.isCompleted ? "Mark open" : "Mark done")

            Text(item.title)
                .font(.body)
                .lineLimit(2)
                .strikethrough(item.isCompleted)
                .foregroundStyle(item.isCompleted ? .secondary : .primary)

            Spacer(minLength: 8)

            PriorityMenu(item: item, store: store)

            Button {
                store.delete(item)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Delete")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(.background.opacity(0.58), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .draggable(item.id.uuidString) {
            DragPreview(item: item)
        }
        .contextMenu {
            Button(item.isCompleted ? "Mark Open" : "Mark Done") {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    store.toggle(item)
                }
            }

            Menu("Priority") {
                ForEach(TodoPriority.allCases) { priority in
                    Button(priority.rawValue) {
                        store.setPriority(priority, for: item)
                    }
                }

                Button("None") {
                    store.setPriority(nil, for: item)
                }
            }

            Button("Delete", role: .destructive) {
                store.delete(item)
            }
        }
    }
}

private struct DragPreview: View {
    var item: TodoItem

    var body: some View {
        Text(item.title)
            .font(.callout)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct PriorityMenu: View {
    var item: TodoItem
    @ObservedObject var store: TodoStore

    var body: some View {
        Menu {
            ForEach(TodoPriority.allCases) { priority in
                Button(priority.rawValue) {
                    store.setPriority(priority, for: item)
                }
            }

            Divider()

            Button("None") {
                store.setPriority(nil, for: item)
            }
        } label: {
            Image(systemName: "flag")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
        }
        .menuStyle(.button)
        .fixedSize()
        .help("Priority")
    }
}

private struct BottomBarView: View {
    @ObservedObject var store: TodoStore
    @Binding var draftTitle: String
    @Binding var draftPriority: TodoPriority
    var isDraftFocused: FocusState<Bool>.Binding
    var onAdd: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TrashDropZone(store: store)

            ComposerView(
                draftTitle: $draftTitle,
                draftPriority: $draftPriority,
                isFocused: isDraftFocused,
                onAdd: onAdd
            )
        }
        .padding(12)
    }
}

private struct TrashDropZone: View {
    @ObservedObject var store: TodoStore
    @State private var isTargeted = false

    var body: some View {
        Label("Delete", systemImage: "trash")
            .font(.callout.weight(.semibold))
            .foregroundStyle(isTargeted ? .red : .secondary)
            .frame(width: 118, height: 34)
            .background(isTargeted ? Color.red.opacity(0.14) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isTargeted ? Color.red : Color.secondary.opacity(0.16), lineWidth: isTargeted ? 2 : 1)
            }
            .dropDestination(
                for: String.self,
                action: { payloads, _ in
                    store.deleteTodos(ids: todoIDs(from: payloads))
                },
                isTargeted: { isTargeted = $0 }
            )
    }
}

private struct ComposerView: View {
    @Binding var draftTitle: String
    @Binding var draftPriority: TodoPriority
    var isFocused: FocusState<Bool>.Binding
    var onAdd: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Picker("Priority", selection: $draftPriority) {
                ForEach(TodoPriority.allCases) { priority in
                    Text(priority.rawValue).tag(priority)
                }
            }
            .labelsHidden()
            .frame(width: 72)

            TextField("New todo", text: $draftTitle)
                .textFieldStyle(.roundedBorder)
                .focused(isFocused)
                .onSubmit(onAdd)

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderedProminent)
            .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Add")
        }
    }
}

private func todoIDs(from payloads: [String]) -> [UUID] {
    payloads.compactMap(UUID.init(uuidString:))
}

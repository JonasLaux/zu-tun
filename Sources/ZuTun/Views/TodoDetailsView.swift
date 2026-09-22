import SwiftUI
import ZuTunCore

enum TodoDetailsRowIdentity: Hashable {
    case reference(UUID)
    case item(UUID)
    case position(Int)
}

struct TodoDetailsRow: Identifiable {
    let item: TodoItem
    let id: TodoDetailsRowIdentity
}

func todoDetailsRows(for items: [TodoItem]) -> [TodoDetailsRow] {
    var referenceCounts: [UUID: Int] = [:]
    var itemCounts: [UUID: Int] = [:]

    for item in items {
        if let referenceID = item.referenceID {
            referenceCounts[referenceID, default: 0] += 1
        }
        itemCounts[item.id, default: 0] += 1
    }

    return items.enumerated().map { index, item in
        let identity: TodoDetailsRowIdentity
        if let referenceID = item.referenceID, referenceCounts[referenceID] == 1 {
            identity = .reference(referenceID)
        } else if itemCounts[item.id] == 1 {
            identity = .item(item.id)
        } else {
            identity = .position(index)
        }
        return TodoDetailsRow(item: item, id: identity)
    }
}

struct TodoDetailsToggle: View {
    let title: String
    let compact: Bool
    @Binding var isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            if reduceMotion {
                isExpanded.toggle()
            } else {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            }
        } label: {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: compact ? 9 : 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: compact ? 12 : 16, height: compact ? 20 : 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "Hide details" : "Show details")
        .accessibilityLabel(isExpanded ? "Hide details for \(title)" : "Show details for \(title)")
        .accessibilityHint(isExpanded ? "Current state and outcome are visible." : "Shows the current state and outcome.")
    }
}

struct TodoDetailsView: View {
    let details: TodoDetails
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            if !details.state.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                detailLine(label: "Current state", value: details.state)
            }

            if !details.outcome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                detailLine(label: "Outcome", value: details.outcome)
            }
        }
        .font(compact ? .caption : .callout)
        .foregroundStyle(.secondary)
        .padding(.top, 2)
        .transition(.opacity)
    }

    @ViewBuilder
    private func detailLine(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            TodoTitleView(title: value, compact: compact, expanded: true)
                .font(compact ? .caption : .callout)
                .foregroundStyle(.primary.opacity(0.82))
        }
    }
}

struct TodoActionsMenu: View {
    let item: TodoItem
    @ObservedObject var store: TodoStore
    @State private var editingItem: TodoItem?
    @State private var isParkingPickerPresented = false
    @State private var managingTags = false

    private var isCopied: Bool {
        item.referenceID != nil && item.referenceID == store.copiedReferenceID
    }

    var body: some View {
        Menu {
            Button {
                editingItem = item
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button {
                store.copyForAgent(item)
            } label: {
                Label("Copy for Agent", systemImage: "square.and.arrow.up")
            }

            Divider()

            Menu("Tags") {
                ForEach(store.document.tags) { tag in
                    Toggle(tag.name, isOn: Binding(
                        get: { item.tagIDs.contains(tag.id) },
                        set: { selected in
                            let ids = selected
                                ? item.tagIDs + [tag.id]
                                : item.tagIDs.filter { $0 != tag.id }
                            store.setTags(ids, for: item)
                        }
                    ))
                }

                Divider()

                Button("Manage Tags…") {
                    managingTags = true
                }
            }

            Menu("Priority") {
                ForEach(TodoPriority.allCases) { priority in
                    Button(priority.rawValue) {
                        store.setPriority(priority, for: item)
                    }
                }

                Divider()

                Button("None") {
                    store.setPriority(nil, for: item)
                }
            }

            if !item.isCompleted {
                Menu(item.isParked(at: store.currentDate) ? "Parking" : "Park…") {
                    ParkingMenuContents(
                        item: item,
                        store: store,
                        onChooseDate: { isParkingPickerPresented = true }
                    )
                }
            }

            Divider()

            Button("Delete", role: .destructive) {
                store.delete(item)
            }
        } label: {
            Image(systemName: isCopied ? "checkmark" : "ellipsis")
                .foregroundStyle(isCopied ? Color.green : Color.secondary)
                .frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(isCopied ? "Copied for Agent" : "More actions")
        .accessibilityLabel("More actions for \(item.title)")
        .popover(item: $editingItem, arrowEdge: .bottom) { original in
            TodoTextEditor(
                initialText: original.title,
                initialDetails: original.details,
                actionTitle: "Save",
                errorMessage: store.errorMessage,
                showsDetails: true
            ) { text, details in
                store.updateTodo(title: text, details: details, for: original)
            }
        }
        .popover(isPresented: $isParkingPickerPresented, arrowEdge: .bottom) {
            ParkingDateTimePicker(item: item, store: store)
        }
        .sheet(isPresented: $managingTags) {
            TagManagerView(store: store)
        }
    }
}

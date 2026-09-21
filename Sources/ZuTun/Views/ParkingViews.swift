import Foundation
import SwiftUI
import ZuTunCore

/// The shared actions used by the clock button and by each todo's context menu.
/// Keeping these actions in one view makes the menu-bar and main-window flows
/// use the same parking choices and dates.
struct ParkingMenuContents: View {
    let item: TodoItem
    @ObservedObject var store: TodoStore
    let onChooseDate: () -> Void

    private var oneHour: Date {
        store.currentDate.addingTimeInterval(60 * 60)
    }

    private var tomorrowAtNine: Date {
        let calendar = Calendar.autoupdatingCurrent
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: store.currentDate)
            ?? store.currentDate.addingTimeInterval(24 * 60 * 60)
        var components = calendar.dateComponents([.year, .month, .day], from: tomorrow)
        components.hour = 9
        components.minute = 0
        components.second = 0
        return calendar.date(from: components) ?? tomorrow
    }

    private var oneWeek: Date {
        Calendar.autoupdatingCurrent.date(byAdding: .day, value: 7, to: store.currentDate)
            ?? store.currentDate.addingTimeInterval(7 * 24 * 60 * 60)
    }

    var body: some View {
        if item.isParked(at: store.currentDate) {
            Button {
                store.setParking(nil, for: item)
            } label: {
                Label("Bring back now", systemImage: "arrow.uturn.backward")
            }

            Divider()
        }

        Button {
            store.setParking(.until(oneHour), for: item)
        } label: {
            parkingChoiceLabel("For 1 hour", date: oneHour)
        }

        Button {
            store.setParking(.until(tomorrowAtNine), for: item)
        } label: {
            parkingChoiceLabel("Until tomorrow", date: tomorrowAtNine)
        }

        Button {
            store.setParking(.until(oneWeek), for: item)
        } label: {
            parkingChoiceLabel("For 1 week", date: oneWeek)
        }

        Button {
            onChooseDate()
        } label: {
            Label("Choose date & time…", systemImage: "calendar.badge.clock")
        }

        Divider()

        Button {
            store.setParking(.indefinite, for: item)
        } label: {
            Label("Until I bring it back", systemImage: "pause.circle")
        }
    }

    private func parkingChoiceLabel(_ title: String, date: Date) -> some View {
        Label {
            Text("\(title) · \(parkingDateTimeText(date))")
        } icon: {
            Image(systemName: "clock")
        }
    }
}

/// A compact clock action for unfinished todo rows.
struct ParkingButton: View {
    let item: TodoItem
    @ObservedObject var store: TodoStore
    let onChooseDate: () -> Void

    var body: some View {
        Menu {
            ParkingMenuContents(item: item, store: store, onChooseDate: onChooseDate)
        } label: {
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(item.isParked(at: store.currentDate) ? "Change parking" : "Park")
        .accessibilityLabel(item.isParked(at: store.currentDate) ? "Change parking" : "Park")
        .accessibilityHint("Choose when this todo should return to the active list.")
    }
}

struct ParkingDateTimePicker: View {
    let item: TodoItem
    @ObservedObject var store: TodoStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate: Date
    @State private var validationMessage: String?

    init(item: TodoItem, store: TodoStore) {
        self.item = item
        self.store = store
        _selectedDate = State(initialValue: parkingEditorDate(for: item, currentDate: store.currentDate))
    }

    private var minimumDate: Date {
        store.currentDate
    }

    private var isFuture: Bool {
        selectedDate > store.currentDate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Park todo")
                .font(.headline)

            Text(item.title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            DatePicker(
                "Return to active",
                selection: $selectedDate,
                in: minimumDate...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.field)

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text("The todo will stay hidden until this time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Park") {
                    park()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!isFuture)
            }
        }
        .padding(16)
        .frame(width: 310)
        .onAppear {
            selectedDate = parkingEditorDate(for: item, currentDate: store.currentDate)
        }
        .onChange(of: selectedDate) { _, _ in
            validationMessage = nil
        }
    }

    private func park() {
        guard isFuture else {
            validationMessage = "Choose a future date and time."
            return
        }

        if store.setParking(.until(selectedDate), for: item) {
            dismiss()
        } else {
            validationMessage = "This todo changed. Reload and try again."
        }
    }
}

struct ParkedSectionView: View {
    @ObservedObject var store: TodoStore
    @State private var isExpanded = false

    var body: some View {
        if !store.parkedTodos.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ParkingSectionHeader(
                    title: "Parked",
                    count: store.parkedTodos.count,
                    isExpanded: isExpanded
                ) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        isExpanded.toggle()
                    }
                }

                if isExpanded {
                    ForEach(store.parkedTodos) { item in
                        ParkedTodoRow(item: item, store: store)
                    }
                }
            }
            .padding(10)
            .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.orange.opacity(0.2), lineWidth: 1)
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: store.parkedTodos.map(\.id))
        }
    }
}

private struct ParkingSectionHeader: View {
    let title: String
    let count: Int
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)

                Image(systemName: "clock")
                    .foregroundStyle(.orange)

                Text(title)
                    .font(.headline)

                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.tertiary, in: Capsule())

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(count) todos")
        .accessibilityHint(isExpanded ? "Collapse parked todos" : "Show parked todos")
    }
}

struct ParkedTodoRow: View {
    let item: TodoItem
    @ObservedObject var store: TodoStore
    @State private var isParkingPickerPresented = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    store.toggle(item)
                }
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 18, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Mark done")
            .accessibilityLabel("Mark \(item.title) done")

            VStack(alignment: .leading, spacing: 4) {
                TodoTitleView(title: item.title)
                    .font(.body)

                if store.document.tags.contains(where: { item.tagIDs.contains($0.id) }) {
                    TagBadges(item: item, tags: store.document.tags)
                }

                ParkingScheduleLabel(item: item, currentDate: store.currentDate)
            }

            Spacer(minLength: 8)

            CopyTodoButton(item: item, store: store)
            EditTodoButton(item: item, store: store)
            ItemTagsMenu(item: item, store: store)

            Button {
                store.setParking(nil, for: item)
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Bring back now")
            .accessibilityLabel("Bring back \(item.title) now")

            Button {
                showParkingPicker()
            } label: {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Change parking time")
            .accessibilityLabel("Change parking time for \(item.title)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(.background.opacity(0.58), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
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

            Button("Mark Done") {
                store.toggle(item)
            }

            Button("Delete", role: .destructive) {
                store.delete(item)
            }
        }
        .draggable(item.id.uuidString) {
            DragPreview(item: item)
        }
        .popover(isPresented: $isParkingPickerPresented, arrowEdge: .bottom) {
            ParkingDateTimePicker(item: item, store: store)
        }
    }

    private func showParkingPicker() {
        isParkingPickerPresented = true
    }
}

struct ParkingScheduleLabel: View {
    let item: TodoItem
    let currentDate: Date

    var body: some View {
        Label(parkingDescription(for: item.parking), systemImage: "clock")
            .font(.caption)
            .foregroundStyle(.orange)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .help(parkingDescription(for: item.parking))
    }
}

struct CompactParkedSectionView: View {
    @ObservedObject var store: TodoStore
    @State private var isExpanded = false

    var body: some View {
        if !store.parkedTodos.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .frame(width: 10)
                        Image(systemName: "clock")
                            .foregroundStyle(.orange)
                        Text("Parked")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text("\(store.parkedTodos.count)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Rectangle()
                            .fill(Color(nsColor: .separatorColor).opacity(0.5))
                            .frame(height: 1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Parked, \(store.parkedTodos.count) todos")
                .accessibilityHint(isExpanded ? "Collapse parked todos" : "Show parked todos")

                if isExpanded {
                    ForEach(store.parkedTodos) { item in
                        CompactParkedTodoRow(item: item, store: store)
                    }
                }
            }
            .padding(.top, 3)
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: store.parkedTodos.map(\.id))
        }
    }
}

private struct CompactParkedTodoRow: View {
    let item: TodoItem
    @ObservedObject var store: TodoStore
    @State private var isParkingPickerPresented = false

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
            .accessibilityLabel("Mark \(item.title) done")

            VStack(alignment: .leading, spacing: 3) {
                TodoTitleView(title: item.title, compact: true)
                ParkingScheduleLabel(item: item, currentDate: store.currentDate)
            }

            Spacer(minLength: 8)

            Button {
                store.setParking(nil, for: item)
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.plain)
            .help("Bring back now")
            .accessibilityLabel("Bring back \(item.title) now")

            Button {
                showParkingPicker()
            } label: {
                Image(systemName: "clock")
            }
            .buttonStyle(.plain)
            .help("Change parking time")
            .accessibilityLabel("Change parking time for \(item.title)")

            CopyTodoButton(item: item, store: store)
            EditTodoButton(item: item, store: store)
            ItemTagsMenu(item: item, store: store)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .contextMenu {
            Menu("Park…") {
                ParkingMenuContents(item: item, store: store, onChooseDate: showParkingPicker)
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

            Button("Mark Done") {
                store.toggle(item)
            }

            Button("Delete", role: .destructive) {
                store.delete(item)
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

func parkingDateTimeText(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .shortened)
}

func parkingDescription(for parking: TodoParking?) -> String {
    guard let parking else {
        return "Parked"
    }

    switch parking {
    case .until(let date):
        return "Until \(parkingDateTimeText(date))"
    case .indefinite:
        return "Until you bring it back"
    }
}

func parkingEditorDate(for item: TodoItem, currentDate: Date) -> Date {
    if let parking = item.parking,
       case .until(let date) = parking,
       date > currentDate {
        return date
    }

    return currentDate.addingTimeInterval(60 * 60)
}

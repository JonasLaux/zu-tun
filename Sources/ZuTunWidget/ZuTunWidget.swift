import AppIntents
import Foundation
import SwiftUI
import WidgetKit
import ZuTunCore

struct ToggleTodoIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Todo"
    static let description = IntentDescription("Marks a Zu Tun item done or open.")

    @Parameter(title: "Todo ID")
    var todoID: String

    init() {
        todoID = ""
    }

    init(todoID: String) {
        self.todoID = todoID
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: todoID) else {
            return .result()
        }

        var document = try TodoFile.loadWidgetDocument()
        if document.updateTodo(id: id, { $0.isCompleted.toggle() }) {
            try TodoFile.saveWidgetDocument(document)
            try TodoLocation.enqueuePendingWidgetToggle(id: id)
        }

        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct TodoTimelineEntry: TimelineEntry {
    let date: Date
    let openTodos: [TodoItem]
    let totalOpenCount: Int
    let completedCount: Int
}

struct TodoTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodoTimelineEntry {
        TodoTimelineEntry(
            date: Date(),
            openTodos: [
                TodoItem(isCompleted: false, priority: .p1, title: "Review today"),
                TodoItem(isCompleted: false, priority: .p2, title: "Ship the tiny app")
            ],
            totalOpenCount: 2,
            completedCount: 0
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TodoTimelineEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodoTimelineEntry>) -> Void) {
        let entry = loadEntry()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func loadEntry() -> TodoTimelineEntry {
        do {
            let document = try TodoFile.loadWidgetDocument()
            let openTodos = document.openTodos
            return TodoTimelineEntry(
                date: Date(),
                openTodos: Array(openTodos.prefix(12)),
                totalOpenCount: openTodos.count,
                completedCount: document.completedTodos.count
            )
        } catch {
            return TodoTimelineEntry(date: Date(), openTodos: [], totalOpenCount: 0, completedCount: 0)
        }
    }
}

struct ZuTunWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: TodoTimelineEntry

    var body: some View {
        VStack(alignment: .leading, spacing: contentSpacing) {
            WidgetHeader(entry: entry, family: family)

            if entry.openTodos.isEmpty {
                WidgetEmptyState(family: family)
            } else {
                VStack(alignment: .leading, spacing: rowSpacing) {
                    ForEach(visibleTodos) { item in
                        WidgetTodoRow(item: item, family: family)
                    }

                    if overflowCount > 0 {
                        WidgetOverflowRow(count: overflowCount, family: family)
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .padding(widgetPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.background, for: .widget)
    }

    private var maxVisibleRows: Int {
        switch family {
        case .systemSmall:
            3
        case .systemMedium:
            4
        case .systemLarge:
            8
        default:
            8
        }
    }

    private var contentSpacing: CGFloat {
        family == .systemSmall ? 9 : 11
    }

    private var rowSpacing: CGFloat {
        family == .systemSmall ? 4 : 6
    }

    private var widgetPadding: CGFloat {
        switch family {
        case .systemSmall:
            12
        case .systemMedium:
            13
        default:
            14
        }
    }

    private var visibleTodos: [TodoItem] {
        let capacity = entry.totalOpenCount > maxVisibleRows ? maxVisibleRows - 1 : maxVisibleRows
        return Array(entry.openTodos.prefix(max(capacity, 0)))
    }

    private var overflowCount: Int {
        max(entry.totalOpenCount - visibleTodos.count, 0)
    }
}

struct WidgetHeader: View {
    var entry: TodoTimelineEntry
    var family: WidgetFamily

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Label("Zu Tun", systemImage: "checklist")
                .font(headerFont)
                .labelStyle(.titleAndIcon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary, Color.accentColor)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(countText)
                    .font(Font.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.secondary.opacity(0.1), in: Capsule())

                if family == .systemLarge && entry.completedCount > 0 {
                    Text("\(entry.completedCount) done")
                        .font(Font.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var countText: String {
        family == .systemSmall ? "\(entry.totalOpenCount)" : "\(entry.totalOpenCount) open"
    }

    private var headerFont: Font {
        family == .systemSmall ? .headline.weight(.semibold) : .title3.weight(.semibold)
    }
}

struct WidgetEmptyState: View {
    var family: WidgetFamily

    var body: some View {
        Spacer(minLength: 0)

        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.green)

            Text("Done for now")
                .font(family == .systemSmall ? .caption : .subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)

        Spacer(minLength: 0)
    }
}

struct WidgetTodoRow: View {
    var item: TodoItem
    var family: WidgetFamily

    var body: some View {
        HStack(spacing: family == .systemSmall ? 7 : 9) {
            Button(intent: ToggleTodoIntent(todoID: item.id.uuidString)) {
                ZStack {
                    Circle()
                        .stroke(priorityColor, lineWidth: 1.5)

                    Circle()
                        .fill(priorityColor.opacity(0.16))
                        .frame(width: innerDotSize, height: innerDotSize)
                }
                .frame(width: iconSize, height: iconSize)
            }
            .buttonStyle(.plain)

            Text(item.title)
                .font(rowFont)
                .fontWeight(.medium)
                .lineLimit(family == .systemLarge ? 2 : 1)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            if family != .systemSmall {
                Text(item.priority?.rawValue ?? "")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(priorityColor)
                    .frame(width: 20, alignment: .trailing)
            }
        }
        .padding(.horizontal, family == .systemSmall ? 0 : 7)
        .padding(.vertical, family == .systemSmall ? 2 : 5)
        .background(
            family == .systemSmall ? Color.clear : Color.secondary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .contentShape(Rectangle())
    }

    private var rowFont: Font {
        family == .systemSmall ? .caption : .callout
    }

    private var priorityColor: Color {
        switch item.priority {
        case .p1:
            .red
        case .p2:
            .orange
        case .p3:
            .blue
        case nil:
            .secondary
        }
    }

    private var iconSize: CGFloat {
        family == .systemSmall ? 14 : 16
    }

    private var innerDotSize: CGFloat {
        family == .systemSmall ? 5 : 6
    }
}

struct WidgetOverflowRow: View {
    var count: Int
    var family: WidgetFamily

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "ellipsis")
                .font(.caption.weight(.bold))
                .frame(width: family == .systemSmall ? 14 : 16)

            Text("\(count) more")
                .font(family == .systemSmall ? .caption2 : .caption)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, family == .systemSmall ? 0 : 7)
        .padding(.vertical, family == .systemSmall ? 1 : 4)
    }
}

struct ZuTunSidebarWidget: Widget {
    let kind = "dev.jonaslaux.ZuTun.SidebarWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodoTimelineProvider()) { entry in
            ZuTunWidgetView(entry: entry)
        }
        .configurationDisplayName("Zu Tun")
        .description("Shows open todos from your todo.md.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

@main
struct ZuTunWidgetBundle: WidgetBundle {
    var body: some Widget {
        ZuTunSidebarWidget()
    }
}

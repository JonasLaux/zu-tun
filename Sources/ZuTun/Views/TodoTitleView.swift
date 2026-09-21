import SwiftUI
import ZuTunCore

struct TodoTitleView: View {
    var title: String
    var isCompleted = false
    var compact = false
    var expanded = false

    var body: some View {
        let content = TodoLinks(title)
        VStack(alignment: .leading, spacing: 5) {
            if !content.text.isEmpty {
                Text(TodoTextFormatting.render(content.text))
                    .lineLimit(expanded || title.contains("\n") ? nil : (compact ? 2 : 3))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
                    .strikethrough(isCompleted)
                    .foregroundStyle(isCompleted ? .secondary : .primary)
                    .help(content.text)
            }
            ForEach(content.links) { link in
                NeonTodoLink(link: link)
            }
        }
    }
}

private struct NeonTodoLink: View {
    let link: TodoLinks.Item
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    private var neon: Color {
        if colorScheme == .dark {
            return hovering ? Color(red: 1, green: 0.38, blue: 0.88)
                : Color(red: 0.2, green: 0.91, blue: 1)
        }
        // Deeper neon hues remain readable on a light background.
        return hovering ? Color(red: 0.68, green: 0.04, blue: 0.52)
            : Color(red: 0, green: 0.37, blue: 0.49)
    }

    var body: some View {
        Link(destination: link.url) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
                    .offset(x: hovering && !reduceMotion ? 1 : 0,
                            y: hovering && !reduceMotion ? -1 : 0)
                Text(link.label)
                    .underline()
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(neon)
            .shadow(color: neon.opacity(hovering ? 0.55 : 0), radius: hovering ? 4 : 0)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(link.url.absoluteString)
        .accessibilityLabel("Open \(link.label)")
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: hovering)
    }
}

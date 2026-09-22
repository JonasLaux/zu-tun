import AppKit
import SwiftUI
import ZuTunCore

struct EditTodoButton: View {
    let item: TodoItem
    @ObservedObject var store: TodoStore
    @State private var editing = false
    @State private var original: TodoItem?

    var body: some View {
        Button {
            original = item
            editing = true
        } label: {
            Image(systemName: "pencil")
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .help("Edit text, state, and outcome")
        .accessibilityLabel("Edit todo text and details")
        .popover(isPresented: $editing) {
            if let original {
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
        }
    }
}

struct FormatDraftButton: View {
    @Binding var text: String
    @State private var editing = false

    var body: some View {
        Button { editing = true } label: {
            Image(systemName: "textformat")
        }
        .help("Format todo text")
        .accessibilityLabel("Format todo text")
        .popover(isPresented: $editing) {
            TodoTextEditor(initialText: text, actionTitle: "Apply", showsDetails: false) { formattedText, _ in
                text = TodoTextFormatting.normalizedTitle(formattedText)
                return true
            }
        }
    }
}

struct TodoTextEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var state: String
    @State private var outcome: String
    @StateObject private var controller = MarkdownEditorController()
    let actionTitle: String
    var errorMessage: String?
    let showsDetails: Bool
    let onSave: (String, TodoDetails?) -> Bool

    init(
        initialText: String,
        initialDetails: TodoDetails? = nil,
        actionTitle: String,
        errorMessage: String? = nil,
        showsDetails: Bool = true,
        onSave: @escaping (String, TodoDetails?) -> Bool
    ) {
        _text = State(initialValue: initialText)
        _state = State(initialValue: initialDetails?.state ?? "")
        _outcome = State(initialValue: initialDetails?.outcome ?? "")
        self.actionTitle = actionTitle
        self.errorMessage = errorMessage
        self.showsDetails = showsDetails
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit todo").font(.headline)
            HStack(spacing: 6) {
                formatButton("Bold", symbol: "bold", prefix: "**", suffix: "**")
                formatButton("Italic", symbol: "italic", prefix: "*", suffix: "*")
                formatButton("Code", symbol: "chevron.left.forwardslash.chevron.right", prefix: "`", suffix: "`")
                formatButton("Link", symbol: "link", prefix: "[", suffix: "](https://example.com)")
                Spacer()
                Text("Select text to format")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            MarkdownTextInput(text: $text, controller: controller)
                .frame(height: 110)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(.separator))

            if showsDetails {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Optional details")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        if !draftDetails.isEmpty {
                            Button("Clear") {
                                state = ""
                                outcome = ""
                            }
                            .buttonStyle(.borderless)
                            .help("Remove current state and outcome")
                            .accessibilityLabel("Clear current state and outcome")
                        }
                    }

                    TextField("Current state (optional)", text: $state, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...2)
                        .accessibilityLabel("Current state")
                        .accessibilityHint("Optional short description of the todo's current state.")

                    TextField("Outcome (optional)", text: $outcome, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)
                        .accessibilityLabel("Outcome")
                        .accessibilityHint("Optional concise description of the achieved or verified result.")
                }
            }

            Text("Preview").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                TodoTitleView(title: text, expanded: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 45, maxHeight: 150)

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Text("Return for a new line. ⌘Return to \(actionTitle.lowercased()).")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(actionTitle) {
                    if onSave(text, draftDetails) { dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(TodoTextFormatting.normalizedTitle(text).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 440)
    }

    private var draftDetails: TodoDetails {
        TodoDetails(
            state: state.trimmingCharacters(in: .whitespacesAndNewlines),
            outcome: outcome.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func formatButton(_ title: String, symbol: String, prefix: String, suffix: String) -> some View {
        Button {
            controller.wrapSelection(prefix: prefix, suffix: suffix)
        } label: {
            Image(systemName: symbol).frame(width: 22, height: 20)
        }
        .help(title)
        .accessibilityLabel(title)
    }
}

@MainActor
private final class MarkdownEditorController: ObservableObject {
    weak var textView: NSTextView?

    func wrapSelection(prefix: String, suffix: String) {
        guard let textView else { return }
        let range = textView.selectedRange()
        let selected = (textView.string as NSString).substring(with: range)
        let content = selected.isEmpty ? "text" : selected
        let replacement = prefix + content + suffix
        guard textView.shouldChangeText(in: range, replacementString: replacement) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: replacement)
        textView.didChangeText()
        let selection: NSRange
        if prefix == "[" {
            selection = NSRange(location: range.location + (prefix + content + "](").utf16.count,
                                length: "https://example.com".utf16.count)
        } else {
            selection = NSRange(location: range.location + prefix.utf16.count, length: content.utf16.count)
        }
        textView.setSelectedRange(selection)
        textView.window?.makeFirstResponder(textView)
    }
}

private struct MarkdownTextInput: NSViewRepresentable {
    @Binding var text: String
    let controller: MarkdownEditorController

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let view = scroll.documentView as? NSTextView else { return scroll }
        view.isRichText = false
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.font = .systemFont(ofSize: NSFont.systemFontSize)
        view.textColor = .labelColor
        view.textContainerInset = NSSize(width: 8, height: 8)
        view.setAccessibilityLabel("Todo Markdown text")
        view.string = text
        view.delegate = context.coordinator
        controller.textView = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let view = scroll.documentView as? NSTextView else { return }
        if view.string != text { view.string = text }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            text.wrappedValue = view.string
        }
    }
}

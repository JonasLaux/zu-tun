import SwiftUI
import ZuTunCore

struct CopyTodoButton: View {
    let item: TodoItem
    @ObservedObject var store: TodoStore

    private var isCopied: Bool {
        item.referenceID != nil && item.referenceID == store.copiedReferenceID
    }

    var body: some View {
        Button {
            store.copyForAgent(item)
        } label: {
            Image(systemName: isCopied ? "checkmark" : "square.and.arrow.up")
                .foregroundStyle(isCopied ? Color.green : Color.secondary)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .help(isCopied ? "Copied for Agent" : "Copy for Agent")
        .accessibilityLabel(isCopied ? "Copied for Agent" : "Copy for Agent")
        .accessibilityHint("Copies a prompt using the global zu-tun skill and a stable reference to this todo.")
    }
}

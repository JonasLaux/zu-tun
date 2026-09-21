import AppKit
import SwiftUI
import ZuTunCore

struct TagBadges: View {
    var item: TodoItem
    var tags: [TodoTag]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                ForEach(tags.filter { item.tagIDs.contains($0.id) }) { tag in
                    Label {
                        Text(tag.name).lineLimit(1)
                    } icon: {
                        Circle().fill(Color(tagHex: tag.color)).frame(width: 7, height: 7)
                    }
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                }
            }
            Text(tags.filter { item.tagIDs.contains($0.id) }.map(\.name).joined(separator: ", "))
                .font(.caption)
                .lineLimit(2)
        }
    }
}

struct ItemTagsMenu: View {
    var item: TodoItem
    @ObservedObject var store: TodoStore
    @State private var managing = false

    var body: some View {
        Menu {
            ForEach(store.document.tags) { tag in
                Toggle(tag.name, isOn: Binding(
                    get: { item.tagIDs.contains(tag.id) },
                    set: { selected in
                        let ids = selected ? item.tagIDs + [tag.id] : item.tagIDs.filter { $0 != tag.id }
                        store.setTags(ids, for: item)
                    }
                ))
            }
            Divider()
            Button("Manage Tags…") { managing = true }
        } label: {
            Image(systemName: "tag")
                .frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Tags")
        .accessibilityLabel("Tags for \(item.title)")
        .sheet(isPresented: $managing) { TagManagerView(store: store) }
    }
}

struct ManageTagsButton: View {
    @ObservedObject var store: TodoStore
    @State private var managing = false

    var body: some View {
        Button { managing = true } label: {
            Label("Tags", systemImage: "tag")
        }
        .help("Manage tags")
        .sheet(isPresented: $managing) { TagManagerView(store: store) }
    }
}

struct TagManagerView: View {
    @ObservedObject var store: TodoStore
    @Environment(\.dismiss) private var dismiss
    @State private var editingID: String?
    @State private var name = ""
    @State private var color = Color.blue
    @State private var pendingDelete: TodoTag?
    @State private var confirmingDelete = false
    @State private var validation: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Tags").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Reuse tags on any todo. Changes apply everywhere.")
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVStack(spacing: 8) {
                    if store.document.tags.isEmpty {
                        Text("Create your first tag below.")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 20)
                    }
                    ForEach(store.document.tags) { tag in
                        HStack {
                            Circle().fill(Color(tagHex: tag.color)).frame(width: 10, height: 10)
                            Text(tag.name).lineLimit(2)
                            Spacer()
                            Button("Edit") {
                                editingID = tag.id
                                name = tag.name
                                color = Color(tagHex: tag.color)
                                validation = nil
                            }
                            Button(role: .destructive) {
                                pendingDelete = tag
                                confirmingDelete = true
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("Delete \(tag.name)")
                        }
                        .padding(8)
                    }
                }
            }
            .frame(height: 200)
            Divider()
            Text(editingID == nil ? "New tag" : "Edit tag").font(.headline)
            HStack {
                TextField("Tag name", text: $name).textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                ColorPicker("Color", selection: $color, supportsOpacity: false)
                    .fixedSize()
            }
            if let message = validation ?? store.errorMessage {
                Text(message).font(.callout).foregroundStyle(.red)
            }
            HStack {
                if editingID != nil {
                    Button("Cancel edit") { reset() }
                }
                Spacer()
                Button(editingID == nil ? "Add Tag" : "Save Changes", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .confirmationDialog("Delete \(pendingDelete?.name ?? "tag")?",
                            isPresented: $confirmingDelete, titleVisibility: .visible,
                            presenting: pendingDelete) { tag in
            Button("Delete Tag", role: .destructive) {
                if store.removeTag(tag) {
                    if editingID == tag.id { reset() }
                }
                pendingDelete = nil
            }
        } message: { _ in
            Text("This removes the tag from all open and completed todos. The todos stay in your list.")
        }
    }

    private func save() {
        if let editingID, !store.document.tags.contains(where: { $0.id == editingID }) {
            validation = "This tag was removed. Cancel this edit to create a new tag."
            return
        }
        let tag = TodoTag(id: editingID ?? UUID().uuidString, name: name, color: color.tagHex)
        if store.saveTag(tag) {
            reset()
        } else {
            validation = store.errorMessage ?? "Use a unique, nonempty tag name."
        }
    }

    private func reset() {
        editingID = nil
        name = ""
        validation = nil
    }
}

private extension Color {
    init(tagHex: String) {
        let value = UInt32(tagHex.dropFirst(), radix: 16) ?? 0x007AFF
        self.init(red: Double((value >> 16) & 255) / 255,
                  green: Double((value >> 8) & 255) / 255,
                  blue: Double(value & 255) / 255)
    }

    var tagHex: String {
        let rgb = NSColor(self).usingColorSpace(.sRGB) ?? .systemBlue
        return String(format: "#%02X%02X%02X", Int((rgb.redComponent * 255).rounded()),
                      Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
    }
}

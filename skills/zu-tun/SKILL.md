---
name: zu-tun
description: Use when an agent needs to read, update, or verify todos through the Zu Tun Markdown todo file, or work on the Zu Tun macOS app and widget repository.
---

# Zu Tun

## Source Of Truth

Zu Tun is a file-backed macOS todo app. The main window, menu bar popover, and widget read and write a Markdown file named `todo.md`.

When the user says "my todos", "the widget todos", "todo.md", or "Zu Tun todos", resolve the configured todo file first. Do not assume a fixed path.

The app publishes its selected todo path to an app-group sidecar named `todo-path.txt`. From this repo, resolve it like this:

```sh
APP_GROUP="$(rg -o 'appGroupIdentifier = "[^"]+"' Sources/ZuTunCore/Models/TodoLocation.swift | sed -E 's/.*"([^"]+)"/\1/')"
SIDECAR="$HOME/Library/Group Containers/$APP_GROUP/todo-path.txt"

if [ -s "$SIDECAR" ]; then
  TODO_FILE="$(sed -n '1p' "$SIDECAR")"
else
  TODO_FILE="$HOME/Library/Group Containers/$APP_GROUP/todo.md"
fi
```

Read and edit `$TODO_FILE`. If the sidecar points to a missing file, create `todo.md` there only when the user asks to add/update todos; otherwise report the missing configured file.

## Todo Format

Use one Markdown checkbox per task:

```md
- [ ] (P1) Urgent task
- [ ] (P2) Normal task
- [ ] (P3) Later task
- [x] (P2) Completed task
```

Priorities are optional but preferred:

- `P1`: urgent or highest leverage
- `P2`: normal default
- `P3`: low priority or later

Keep task text short, concrete, and action-oriented. Preserve headings, notes, ordering, and completed items unless the user asks for cleanup.

Task text may contain visual line breaks while each todo remains one physical
Markdown line. Use `<br>` for a visual newline and `<br><br>` for a blank visual
line. `<br/>` and `<br />` are accepted case-insensitively. Preserve inline
Markdown and existing `zutun-id` and `zutun-tags` comments on that line. The
pencil and formatting popovers use Return for a new line and Command-Return to
save or apply; the quick composer uses Option-Return for a new line and Return
to add. Normal rows show all explicit lines, while widgets keep compact limits.
To display a literal `<br>`, write `&lt;br&gt;`. Never use a physical
continuation line or a new checkbox for the wrapped text.

## Reusable Tags

Tags live in the same Markdown file. Define each tag once on its own line:

```markdown
<!-- zutun-tag: {"id":"work","name":"Work","color":"#3478F6"} -->
<!-- zutun-tag: {"id":"home","name":"Home","color":"#34A853"} -->

- [ ] (P2) Review the plan <!-- zutun-tags: ["work"] -->
- [x] (P3) Buy supplies <!-- zutun-tags: ["work","home"] -->
```

- IDs are stable, unique strings. The app generates UUIDs; agents may use a
  unique descriptive ID. Reuse existing definitions instead of duplicating tags.
- Names must be nonempty, single-line, and unique ignoring case. Colors use
  `#RRGGBB`. JSON-escape names and IDs; encode `>` as `\u003E`
  inside JSON strings so comment delimiters stay valid. Keep metadata on one line.
- Assign or unassign a tag by changing only the task's trailing ID array.
  Omit the comment when no tags remain. A task may have multiple tags.
- Edit a tag's name or color in its definition, keeping its ID unchanged;
  this updates every use. Do not rename IDs to rename tags.
- Delete a tag by removing its definition AND that ID from every task,
  including completed tasks. Keep other tags and task content intact.
- Preserve unknown IDs and malformed metadata during unrelated edits. Do not
  convert ordinary hashtags in task text into tags.

## Shared Todo References

**Copy for Agent** in the app copies a prompt that invokes the global `zu-tun` skill and identifies one todo by its file path and `<!-- zutun-id: UUID -->` comment. Search for the UUID in that file; the copied title and line number are hints and may have changed. Read the current task and nearby notes/subtasks before starting. If the ID is missing or appears on more than one task, ask rather than guessing.

Preserve the ID comment when renaming, reprioritizing, completing, or moving a task. Do not reuse it for a new or duplicated task. It can appear before or after a `zutun-tags` comment. Tasks without an ID remain valid; the app adds one only when sharing.

## Editing Workflow

1. Read the todo file before editing it.
2. Make the smallest useful patch.
3. Avoid duplicates; update an existing matching task instead.
4. Verify the file after editing.
5. Summarize exactly what changed without dumping the whole file.

## Repo Workflow

`project.yml` is the source of truth for the Xcode project. `ZuTun.xcodeproj/` is generated and intentionally not committed.

Use these checks:

```sh
swift run ZuTunParserCheck
./script/build_and_run.sh --verify
./script/build_and_run.sh --verify-widget
```

For widget changes, run a full app build because signing and embedded-extension metadata issues do not show up in parser-only checks.

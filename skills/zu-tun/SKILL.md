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

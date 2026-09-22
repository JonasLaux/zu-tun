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

Keep the task overview short and concrete: the task, a brief description, and necessary links. Preserve headings, notes, ordering, and completed items unless the user asks for cleanup. Do not use `todo.md` as a parallel task database or append-only work log.

The task header remains one physical Markdown line. Use `<br>` for a visual
newline and `<br><br>` for a blank visual line. `<br/>` and `<br />` are accepted
case-insensitively. Preserve inline Markdown and existing `zutun-id` and
`zutun-tags` comments on that line. An optional collapsed Details block may
carry the current State and a concise factual Outcome:

```md
- [ ] (P2) Investigate first-chat latency <!-- zutun-id: UUID -->
  > [!zutun]- Details <!-- zutun-details-for: UUID -->
  > **State:** Investigating
  > **Outcome:** Reproduced in preview; [trace](https://example.com/trace)
  > <!-- zutun-details-end -->
```

State and Outcome support inline Markdown and links. Use `<br>` for line breaks
within a field; the app saves multiline values in that form.

Place the block immediately below its task header, with no blank line between
them. Indent every Details line two spaces relative to the task indentation. The
Details owner UUID must equal the task ID; never duplicate `zutun-id` there.
Treat Details as owned task content: move or delete them with the task,
preserve them during unrelated edits and after completion, and update State in
place at meaningful changes. Both fields are optional; omit empty fields and
remove an empty Details block while keeping the task ID. Details have no
checkbox or status semantics; list controls remain authoritative for completion
and visibility. Add or edit Details through **More actions > Edit** and expand or collapse them
with the chevron. The widget shows the task header only. Create a stable task
ID when first saving Details. Copy for Agent reads the current task and its
owned Details.

The Edit and formatting popovers use Return for a new line and Command-Return to
save or apply; the quick composer uses Option-Return for a new line and Return
to add. Normal rows show all explicit lines, while widgets keep compact limits.
To display a literal `<br>`, write `&lt;br&gt;`. Never use a physical
continuation line or a new checkbox for wrapped header text. Details are the
only supported indented block.

## Parked Tasks

Parking is a waiting or snooze state for an unfinished task. It is separate
from completion and does not add a new checkbox status. Store it as one
trailing HTML comment on the task line:

```markdown
- [ ] (P2) Wait for approval <!-- zutun-parked: 2026-09-22T07:00:00Z -->
- [ ] (P2) Revisit later <!-- zutun-parked: indefinite -->
```

Use an ISO 8601 timestamp with an explicit timezone. `indefinite` has no
automatic return. The parking comment may appear before or after existing
`zutun-id` and `zutun-tags` comments in any order; preserve every comment on
the same physical Markdown line.

For an active overview, an unfinished task is hidden when it is parked until a
future timestamp or indefinitely. A task whose timestamp has expired becomes
active automatically. Completed tasks are never active, regardless of a
parking comment. Active counts exclude parked tasks; the app keeps parked
items accessible in its collapsed **Parked** section with actions to bring one
back or change its return time.

The available parking choices are 1 hour, tomorrow at 09:00 local time, 7
calendar days at the same local time, a custom future date and time, or
indefinitely. Expiry means “check again,” not that an external blocker is
cleared. When parking a task, add its `zutun-parked` comment; replace the existing
comment when rescheduling instead of appending a second one. When
bringing it back, remove only that comment. Preserve the parking comment during
unrelated edits to task text, priority, tags, IDs, or ordering, and do not
rewrite the task when its timestamp expires.

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

**Copy for Agent** in the app copies a prompt that invokes the global `zu-tun` skill and identifies one todo by its file path and `<!-- zutun-id: UUID -->` comment. Search for the UUID in that file; the copied title, Details, and line number are hints and may have changed. Read the current task and its owned Details before starting. If the ID is missing or appears on more than one task, ask rather than guessing.

Preserve the ID comment when renaming, reprioritizing, completing, or moving a task. Do not reuse it for a new or duplicated task. It can appear before or after a `zutun-tags` comment. Tasks without an ID remain valid; the app adds one when sharing or first saving Details.

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

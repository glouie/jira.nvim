# Page Spec: Help

## ID

`page_help`

## Purpose

Provide discoverable guidance for keys, commands, and common workflows.

## User jobs

- Find keybindings quickly.
- Learn page-specific actions.
- Resolve common mistakes.

## Layout regions

- `header`: help title + current context
- `main_pane`: grouped shortcut and workflow sections
- `footer`: close/search hints

## Components

- `cmp_help_overlay`
- `cmp_text`
- `cmp_heading`
- `cmp_input_search` (optional within help)

## States

- `ready`: content visible

## Keyboard model

- `?`: toggle help open/closed
- `/`: search inside help content
- `j/k`: move within help sections
- `Esc`: close help

## Validation + errors

- n/a for static help content

## System feedback

- Footer shows current section and search match count.

## Accessibility

- Every keybinding entry includes action text and context scope.

## Telemetry (optional)

- `help_opened`
- `help_search_used`

## Open questions

- Should contextual help open directly to current page section?

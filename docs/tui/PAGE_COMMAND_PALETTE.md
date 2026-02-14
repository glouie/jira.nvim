# Page Spec: Command Palette

## ID

`page_command_palette`

## Purpose

Provide a fast command launcher for navigation and actions.

## User jobs

- Find commands by typing partial names.
- Execute command without leaving keyboard flow.
- Preview command scope before execution.

## Layout regions

- `overlay`: modal panel centered over active page
- `header`: prompt and current scope
- `main_pane`: ranked command results
- `footer`: execution and close hints

## Components

- `cmp_command_palette`
- `cmp_list`
- `cmp_modal`
- `cmp_error_state`

## States

- `idle`: open with empty query
- `loading`: command providers resolving
- `ready`: ranked results visible
- `empty`: no command matches
- `error`: provider failed

## Keyboard model

- `Ctrl+p`: open palette
- `j/k`: move selection
- `Enter`: execute command
- `Esc`: close palette

## Validation + errors

- Invalid command arguments prompt for correction before execute.

## System feedback

- After execution, show toast with command name and result.

## Accessibility

- Selected command includes text marker and row index.

## Telemetry (optional)

- `palette_opened`
- `palette_command_executed`
- `palette_no_match`

## Open questions

- Should commands support aliases and hidden debug commands?

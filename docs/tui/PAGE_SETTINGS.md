# Page Spec: Settings

## ID

`page_settings`

## Purpose

Configure behavior, preferences, and keymap options safely.

## User jobs

- Change one or more settings.
- Validate configuration values.
- Save and confirm new behavior.

## Layout regions

- `header`: settings scope and profile
- `left_pane`: settings section navigation
- `main_pane`: editable settings form
- `footer`: save/reset hints and validation status

## Components

- `cmp_tree` (section nav)
- `cmp_input_text`
- `cmp_switch`
- `cmp_select`
- `cmp_confirm_dialog` (reset defaults)

## States

- `idle`: viewing/editing settings
- `submitting`: save in progress
- `error`: save/validation failure
- `success`: save complete

## Keyboard model

- `j/k`: move section or row selection
- `Enter`: open section/activate control
- `Ctrl+s`: save settings
- `r`: reset selected setting or section

## Validation + errors

- Invalid setting values show inline and block save.

## System feedback

- Footer displays unsaved changes count.

## Accessibility

- Setting descriptions are always visible, not tooltip-only.

## Telemetry (optional)

- `settings_opened`
- `settings_saved`
- `settings_reset`

## Open questions

- Should settings support profile import/export?

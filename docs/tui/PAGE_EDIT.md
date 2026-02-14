# Page Spec: Edit

## ID

`page_edit`

## Purpose

Safely modify an existing record while preserving context.

## User jobs

- Change one or more fields.
- Understand unsaved changes.
- Save or discard intentionally.

## Layout regions

- `header`: item identity + dirty-state marker
- `main_pane`: editable field groups
- `right_pane`: baseline values or change preview
- `footer`: save/discard hints

## Components

- `cmp_input_text`
- `cmp_textarea`
- `cmp_select`
- `cmp_badge` (dirty/clean)
- `cmp_confirm_dialog` (discard confirmation)

## States

- `idle`: editable form
- `submitting`: saving in progress
- `error`: save failure
- `success`: save complete

## Keyboard model

- `Tab`/`Shift+Tab`: field traversal
- `Ctrl+s`: save changes
- `Esc`: attempt close/discard

## Validation + errors

- Prevent submit if required fields become invalid.
- Discard action requires explicit confirmation when dirty.

## System feedback

- Show changed-field count in footer.

## Accessibility

- Dirty-state marker includes text, not color only.

## Telemetry (optional)

- `edit_opened`
- `edit_saved`
- `edit_discarded`

## Open questions

- Should partial field saves be allowed?

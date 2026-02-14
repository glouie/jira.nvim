# Page Spec: Create

## ID

`page_create`

## Purpose

Collect required input and create a new record safely.

## User jobs

- Enter required fields quickly.
- Validate before submission.
- Submit once with confidence.

## Layout regions

- `header`: create context and required-field count
- `main_pane`: form fields grouped by section
- `right_pane`: optional live preview or helper text
- `footer`: submit/cancel hints and validation summary

## Components

- `cmp_input_text`
- `cmp_textarea`
- `cmp_select`
- `cmp_checkbox`
- `cmp_error_state`

## States

- `idle`: editable form
- `submitting`: controls locked, progress shown
- `error`: submission or validation failure
- `success`: confirmation and next action

## Keyboard model

- `Tab`/`Shift+Tab`: move across fields
- `Ctrl+s`: submit form
- `Esc`: cancel flow

## Validation + errors

- Required fields validate before network request.
- Inline errors must identify field and resolution.

## System feedback

- On success, show created record key and open shortcut.

## Accessibility

- Every field requires a visible label and error association.

## Telemetry (optional)

- `create_started`
- `create_submitted`
- `create_failed`

## Open questions

- Should draft content persist between sessions?

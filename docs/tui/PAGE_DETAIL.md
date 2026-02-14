# Page Spec: Detail

## ID

`page_detail`

## Purpose

Show complete information for one selected record and expose contextual actions.

## User jobs

- Read full details without leaving terminal flow.
- Copy key fields or open related links.
- Navigate to adjacent records when relevant.

## Layout regions

- `header`: item key + title + status markers
- `main_pane`: primary content (description/body)
- `right_pane`: metadata fields and links
- `footer`: action hints and loading status

## Components

- `cmp_heading`
- `cmp_text`
- `cmp_badge`
- `cmp_tabs` (optional)
- `cmp_status_bar`

## States

- `loading`: details spinner with placeholder sections
- `ready`: full content and actions available
- `error`: record retrieval failed

## Keyboard model

- `Tab`/`Shift+Tab`: cycle focus across panes
- `j/k`: scroll current pane
- `o`: open external link (if present)
- `q` or `Esc`: close detail view

## Validation + errors

- Missing optional fields render placeholders (`N/A`) not hard errors.

## System feedback

- Footer shows source context and last fetch time.

## Accessibility

- Pane title shown before each pane content for orientation.

## Telemetry (optional)

- `detail_opened`
- `detail_link_opened`

## Open questions

- Should line wrapping default to soft-wrap or horizontal scroll?

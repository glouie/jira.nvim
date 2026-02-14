# Page Spec: List

## ID

`page_list`

## Purpose

Browse and select records quickly from a result set.

## User jobs

- Scan records by key fields.
- Sort and filter to find a target item.
- Open one selected item into detail view.

## Layout regions

- `header`: title + result count + search hint
- `left_pane`: optional filters/saved views
- `main_pane`: table or list viewport
- `right_pane`: optional preview pane
- `footer`: selection and paging hints

## Components

- `cmp_input_search`
- `cmp_table` or `cmp_list`
- `cmp_pagination`
- `cmp_empty_state`
- `cmp_error_state`

## States

- `loading`: table skeleton/spinner
- `ready`: rows visible and selectable
- `empty`: no results for current filter
- `error`: query or network failure

## Keyboard model

- `j/k`: move selection
- `g/G`: jump first/last row
- `/`: focus search
- `[` and `]`: page prev/next
- `Enter`: open selected row
- `r`: retry/refresh

## Validation + errors

- Invalid filter terms must show inline and preserve current query.

## System feedback

- Footer shows selected row index and total rows.

## Accessibility

- Column headers remain visible and aligned with row cells.
- Selected row includes text indicator, not color only.

## Telemetry (optional)

- `list_opened`
- `list_row_opened`
- `list_filter_applied`

## Open questions

- Should preview update on selection change or require explicit open?

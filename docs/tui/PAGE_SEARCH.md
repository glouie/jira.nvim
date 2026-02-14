# Page Spec: Search

## ID

`page_search`

## Purpose

Run free-form or structured queries and inspect grouped results.

## User jobs

- Enter and refine a query.
- Scan grouped matches quickly.
- Open a selected result.

## Layout regions

- `header`: search title + active query summary
- `left_pane`: query history or query helpers
- `main_pane`: grouped results list/table
- `right_pane`: optional selected-result preview
- `footer`: match count + navigation hints

## Components

- `cmp_input_search`
- `cmp_list` or `cmp_table`
- `cmp_empty_state`
- `cmp_error_state`

## States

- `idle`: awaiting query
- `loading`: query executing
- `ready`: results rendered
- `empty`: zero matches
- `error`: query failed

## Keyboard model

- `/`: focus query field
- `j/k`: move result selection
- `n/N`: next/prev in-match highlight
- `Enter`: open selected result
- `Esc`: leave query field or close view

## Validation + errors

- Invalid query syntax returns inline parse feedback.

## System feedback

- Footer displays current selection and total matches.

## Accessibility

- Highlighted matches include text token markers.

## Telemetry (optional)

- `search_submitted`
- `search_result_opened`

## Open questions

- Should query history be local only or synchronized?

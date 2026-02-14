# Page Spec: Filters

## ID

`page_filters`

## Purpose

Build, apply, and save filter combinations for list/search pages.

## User jobs

- Add/remove filter clauses.
- Apply filters without losing current context.
- Save reusable filter sets.

## Layout regions

- `header`: filter context + active filter count
- `left_pane`: saved filters list
- `main_pane`: filter editor controls
- `footer`: apply/reset/save hints

## Components

- `cmp_checkbox`
- `cmp_radio_group`
- `cmp_select`
- `cmp_button`
- `cmp_error_state`

## States

- `idle`: edit filter selections
- `ready`: filters applied and synchronized
- `error`: invalid or failed filter execution

## Keyboard model

- `Tab`/`Shift+Tab`: move between controls
- `Space`: toggle selected filter option
- `Enter`: apply current filter set
- `r`: reset filters

## Validation + errors

- Mutually exclusive filters must block apply and explain conflict.

## System feedback

- Footer shows active clause count and last apply time.

## Accessibility

- Saved filter names must be plain language and unique.

## Telemetry (optional)

- `filters_applied`
- `filters_saved`
- `filters_reset`

## Open questions

- Should saved filters be user-scoped or workspace-scoped?

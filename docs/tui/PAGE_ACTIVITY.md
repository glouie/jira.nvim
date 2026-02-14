# Page Spec: Activity

## ID

`page_activity`

## Purpose

Inspect chronological history for traceability and debugging.

## User jobs

- Review recent events by time range.
- Filter events by type or actor.
- Open linked records from events.

## Layout regions

- `header`: range selector + total event count
- `left_pane`: filter chips/options
- `main_pane`: timeline/log list
- `footer`: follow mode and navigation hints

## Components

- `cmp_log_viewer`
- `cmp_select`
- `cmp_badge`
- `cmp_error_state`

## States

- `loading`: initial event load
- `ready`: events rendered
- `empty`: no events in selected range
- `error`: query failure

## Keyboard model

- `j/k`: move through events
- `[` and `]`: previous/next range
- `f`: toggle follow mode when streaming
- `Enter`: open linked item

## Validation + errors

- Invalid date range must block execution and explain correction.

## System feedback

- Footer shows loaded range and stream status.

## Accessibility

- Event levels include text labels (`INFO`, `WARN`, `ERROR`).

## Telemetry (optional)

- `activity_opened`
- `activity_filter_applied`

## Open questions

- Should timeline group events by day headers by default?

# Page Spec: Home

## ID

`page_home`

## Purpose

Provide a quick orientation view: summary counts, recent items, and immediate next actions.

## User jobs

- Assess current workload at a glance.
- Jump to a recent or high-priority record.
- Open key flows without navigating deep menus.

## Layout regions

- `header`: context + quick actions
- `left_pane`: optional navigation and saved views
- `main_pane`: summary cards + recent list
- `footer`: key hints + system status

## Components

- `cmp_heading`
- `cmp_badge`
- `cmp_list`
- `cmp_status_bar`

## States

- `loading`: show skeleton card placeholders
- `ready`: render cards and recent items
- `empty`: show empty-state guidance
- `error`: show summary failure and retry

## Keyboard model

- `j/k`: move through recent list
- `Enter`: open selected item
- `g h`: return to home from elsewhere
- `r`: refresh panel

## Validation + errors

- If any summary request fails, keep other successful sections visible.
- Expose per-section retry where possible.

## System feedback

- Footer shows sync age and background refresh status.

## Accessibility

- Ensure text labels are present for every summary token.
- Keep focus order deterministic across sections.

## Telemetry (optional)

- `home_opened`
- `home_recent_item_opened`

## Open questions

- Should home include pinned shortcuts or remain read-only summary?

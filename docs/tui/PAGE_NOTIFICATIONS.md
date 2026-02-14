# Page Spec: Notifications

## ID

`page_notifications`

## Purpose

Review actionable alerts and mark them handled.

## User jobs

- Scan unread notifications.
- Open related records.
- Mark alerts as read or dismissed.

## Layout regions

- `header`: unread count + quick actions
- `main_pane`: grouped notification list
- `right_pane`: optional selected alert details
- `footer`: action hints

## Components

- `cmp_list`
- `cmp_badge`
- `cmp_button`
- `cmp_empty_state`

## States

- `loading`: fetching notifications
- `ready`: notifications visible
- `empty`: no notifications
- `error`: retrieval failure

## Keyboard model

- `j/k`: move selection
- `m`: mark selected as read
- `Enter`: open related item
- `r`: refresh

## Validation + errors

- Mark-read failures should keep local state unchanged and show retry.

## System feedback

- Footer displays unread/total counters.

## Accessibility

- Unread/read status indicated with symbol and text.

## Telemetry (optional)

- `notifications_opened`
- `notification_opened`
- `notification_marked_read`

## Open questions

- Should bulk actions be supported in v1?

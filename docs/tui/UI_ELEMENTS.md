# UI Elements Catalog

This catalog defines the expected behavior and language for display elements used in TUI specs.

## Element Contract Fields

- `Element ID`: stable identifier used across docs
- `Purpose`: why the element exists
- `Anatomy`: required visible parts
- `States`: allowed states
- `Keyboard contract`: required keyboard behavior

## Display Elements

| Element ID | Purpose | Anatomy | States | Keyboard contract |
|---|---|---|---|---|
| `cmp_text` | Render static text | label/value | `ready` | n/a |
| `cmp_heading` | Show hierarchy | level/title/subtitle | `ready` | tab landmark only |
| `cmp_status_bar` | Show persistent status | mode/hints/system status | `info` `warning` `error` | always visible |
| `cmp_badge` | Compact status marker | token + tone | `neutral` `success` `warning` `error` | n/a |
| `cmp_button` | Trigger action | label + optional icon | `idle` `focused` `disabled` | `Enter`/`Space` |
| `cmp_icon_button` | Trigger compact action | icon + tooltip label | `idle` `focused` `disabled` | `Enter` |
| `cmp_input_text` | Collect short text | label/input/helper/error | `idle` `focused` `invalid` `disabled` | type/edit/`Esc` clear |
| `cmp_input_search` | Collect query text | prompt/input/result count | `idle` `focused` `loading` | `/` focus, `Enter` submit |
| `cmp_textarea` | Collect long text | label/editor/counter/error | `idle` `focused` `invalid` | cursor keys/edit keys |
| `cmp_select` | Pick one option | trigger/menu/options | `closed` `open` `focused` `disabled` | arrows + `Enter` + `Esc` |
| `cmp_multiselect` | Pick multiple options | trigger/menu/selection chips | `closed` `open` `focused` | arrows + `Space` + `Enter` |
| `cmp_checkbox` | Toggle boolean | checkbox/label/hint | `checked` `unchecked` `disabled` | `Space` |
| `cmp_radio_group` | Pick one of many | label/options | `idle` `focused` `disabled` | arrows + `Space` |
| `cmp_switch` | Immediate on/off | label/switch | `on` `off` `disabled` | `Space` |
| `cmp_tabs` | Switch peer panes | tablist/tabpanel | `idle` `active` `disabled` | arrows + `Enter` |
| `cmp_list` | Browse rows | rows + optional metadata | `loading` `ready` `empty` `error` | `j/k`, `Enter` |
| `cmp_table` | Browse dense rows | columns/header/rows | `loading` `ready` `empty` `error` | arrows or `j/k`, `Enter` |
| `cmp_tree` | Browse hierarchy | nodes/expanders | `collapsed` `expanded` `selected` | arrows + `Enter` |
| `cmp_pagination` | Move among pages | current/total/controls | `idle` `disabled` | `[` and `]` |
| `cmp_breadcrumb` | Show location path | segments/separators | `ready` | arrows + `Enter` |
| `cmp_progress` | Show long operation progress | label/progress meter | `indeterminate` `determinate` `complete` | n/a |
| `cmp_spinner` | Show short wait | spinner + label | `active` | n/a |
| `cmp_empty_state` | Explain no data | title/reason/next action | `ready` | expose action key |
| `cmp_error_state` | Explain failures | message/details/retry action | `ready` | `r` retry |
| `cmp_toast` | Temporary non-blocking message | title/body/optional action | `info` `success` `warning` `error` | dismiss key |
| `cmp_modal` | Block for decision/input | title/body/actions | `open` `closing` | focus trap, `Esc` cancel |
| `cmp_confirm_dialog` | Confirm destructive action | consequence + confirm/cancel | `open` | explicit confirm key |
| `cmp_command_palette` | Launch commands by search | query/results/metadata | `idle` `loading` `ready` `empty` | `Ctrl+p`, `j/k`, `Enter`, `Esc` |
| `cmp_help_overlay` | Show help cheat sheet | sections/shortcuts/examples | `open` | `?` toggle, `Esc` close |
| `cmp_splitter` | Resize pane boundaries | divider + two panes | `idle` `resizing` | resize shortcuts |
| `cmp_log_viewer` | View streaming logs | line list/level markers/follow mode | `streaming` `paused` | `f`, `g`, `G` |

## State and Error Conventions

- All interactive components must define at least one recoverable error path.
- If `error` is shown, expose a direct retry mechanism.
- If `empty` is shown, include one next-step action.
- Disabled controls must include a reason when focused.

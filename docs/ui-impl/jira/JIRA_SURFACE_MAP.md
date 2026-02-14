# Jira.nvim Surface Map

This file defines Jira.nvim-specific UI surfaces using the portable contracts in `docs/tui`
and the renderer constraints in `docs/ui-impl/NEOVIM_LUA_PROFILE.md`.

## Surface Inventory

| Surface ID | Surface | Keymap | Archetype |
|---|---|---|---|
| `jira_issue_detail_popup` | Issue details popup | `<leader>ji` | `PAGE_DETAIL.md` |
| `jira_hover_summary` | Hover summary output | cursor hold | `PAGE_HELP.md` (output-only variant) |
| `jira_buffer_issue_picker` | Buffer issue picker | `<leader>jb` | `PAGE_LIST.md` |
| `jira_assigned_list` | Assigned-to-me unresolved list | `<leader>ja` | `PAGE_LIST.md` |
| `jira_created_list` | Created-by-me unresolved list | `<leader>jc` | `PAGE_LIST.md` |
| `jira_recently_viewed_list` | Recently viewed list | `<leader>jr` | `PAGE_LIST.md` |
| `jira_jql_search` | JQL prompt + paged results | `<leader>js` | `PAGE_SEARCH.md` + `PAGE_LIST.md` |
| `jira_filter_search` | Filter-id prompt + results + preview | `<leader>jf` | `PAGE_FILTERS.md` + `PAGE_LIST.md` |
| `jira_saved_filters` | Saved filters list | `<leader>jj` | `PAGE_LIST.md` |
| `jira_viewed_history` | Persisted viewed issue history | `<leader>jh` | `PAGE_LIST.md` |
| `jira_issue_metrics` | Issue metrics popup | TBD | `PAGE_DETAIL.md` (planned) |
| `jira_filter_metrics` | Filter metrics popup | TBD | `PAGE_DETAIL.md` (planned) |

## Shared Jira.nvim Interaction Rules

- `j`/`k`: move selection/cursor in list and table surfaces.
- `gg`/`G`: jump to top/bottom.
- `/`: search where supported.
- `n`/`N`: repeat search where supported.
- `Ctrl+f`/`Ctrl+b`: next/prev result page where paging exists.
- `Enter`: open selected issue/link.
- `q` or `Esc`: close current popup/surface.
- Optional mouse behavior: Cmd-click (macOS) or Ctrl-click (Linux/Windows) opens URL.

## Surface Contracts

### `jira_issue_detail_popup`

- Entry: trigger on issue key under cursor (`<leader>ji` by default).
- Layout:
  - `main_pane`: summary, description, comments/activity
  - `right_pane`: metadata rows from `popup.details_fields`
  - optional URL pane/bar
- Focus:
  - initial focus is `main_pane`
  - `Tab` cycles across present panes
  - `Ctrl+n`/`Ctrl+p` jumps to next/prev issue match in source buffer
- Actions:
  - `o`: open issue in browser
  - `yk`, `ys`, `yd`, `yl`: copy key/summary/description/url
  - `y` in visual mode copies selected text
  - `Enter` on URL opens URL
- States:
  - `loading`, `ready`, `error`, `partial`
- Return behavior:
  - if opened from a list, close returns to that list with prior state intact

### `jira_hover_summary`

- Behavior:
  - on cursor rest on issue key, display `<KEY>: <summary>`
- Output modes:
  - `message`
  - `statusline`
  - `lualine`
- Performance:
  - debounce hover fetches
  - cache summaries briefly to reduce API churn

### `jira_buffer_issue_picker`

- Purpose: list issue keys found in current buffer with line context.
- Behavior:
  - `Enter` opens selected issue detail
  - when `close_on_select = true`, picker closes after selection
  - when picker remains open, closing detail popup returns focus to picker

### `jira_assigned_list`

- Purpose: unresolved issues assigned to configured user.
- Layout: key columns include at least key, summary, status, and priority.
- Paging: must provide paging controls when results exceed `max_results`.

### `jira_created_list`

- Purpose: unresolved issues reported by configured user.
- Layout and paging contract matches `jira_assigned_list`.

### `jira_recently_viewed_list`

- Purpose: list recently viewed issues for current user.
- Layout and paging contract matches `jira_assigned_list`.

### `jira_jql_search`

- Prompt:
  - input for JQL text
  - history sidebar controlled by `history_size`
  - supports loading all entries from entered JQL
- Completion:
  - server-backed suggestions for fields, keywords, common values
  - completion must remain non-blocking
- Keys:
  - `Esc` enters Normal mode for editing/yanking
  - `Ctrl+n`/`Ctrl+p` navigate history or completion by context
  - submit with `Enter` (Normal mode) or `Ctrl+y`
  - exit with `Ctrl+c Ctrl+c` or `q`/`Esc`
- Results:
  - table of matching issues
  - show totals and visible range
  - paging with `Ctrl+f`/`Ctrl+b`

### `jira_filter_search`

- Prompt:
  - input expects numeric Jira filter id
  - history sidebar shows filter id and name (`history_size` limited)
- Keys:
  - `Esc` enters Normal mode
  - submit with `Enter` in Normal or Insert mode
  - exit with `Ctrl+c Ctrl+c` or `q`/`Esc`
- Results:
  - issue table for filter JQL
  - right-side preview updates with current selection
  - paging with `Ctrl+f`/`Ctrl+b`
  - opening detail and closing it returns to list state
- Errors:
  - invalid/unknown filter id shows error inline and keeps prompt open

### `jira_saved_filters`

- Purpose: display accessible filters, favorites first.
- Layout: include favorite marker (`*`), filter id, name, owner.
- Behavior:
  - favorites sorted before non-favorites
  - selecting row routes into filter search flow with selected id

### `jira_viewed_history`

- Purpose: persisted deduped list of viewed issues.
- Behavior:
  - new views append or refresh existing entry recency
  - total entries capped by `history_size`

## Persistence Contracts

- Viewed issue history file:
  - `stdpath("data")/jira.nvim/issue_history.json`
- Filter search history file:
  - `stdpath("data")/jira.nvim/filter_history.json`

## Error Message Conventions

Errors should be actionable and point to config or environment variable.

- Missing base URL: suggest `config.api.base_url` or `JIRA_BASE_URL`
- Missing email: suggest `config.api.email` or `JIRA_API_EMAIL`
- Missing token: suggest `config.api.token` or `JIRA_API_TOKEN`/`JIRA_API_KEY`

## Planned Surfaces

- `jira_issue_metrics`: define once requirements are finalized.
- `jira_filter_metrics`: define once requirements are finalized.

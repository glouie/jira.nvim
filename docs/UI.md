# UI / UX Specification — jira.nvim

This document describes the intended user-facing UI surfaces in `jira.nvim`, their layout, interactions, and states.

The goal is to make UI changes predictable and reviewable:

- when behavior changes, update this file
- new UI surfaces must be added here

## Surfaces (what the plugin renders)

1. **Issue details popup** (`<leader>ji`) (open issue under cursor)
2. **Hover summary output** (command area / statusline / lualine)
3. **Buffer issue picker** (`<leader>jb`) — issue keys detected in current buffer
4. **Assigned-to-me list** (`<leader>ja`) — unresolved issues assigned to current user
5. **Created-by-me list** (`<leader>jc`) — unresolved issues reported by current user
6. **Recently viewed list** (`<leader>jr`) — recently viewed issues for current user
7. **JQL search prompt + results** (`<leader>js`) — prompt with history + server-backed suggestions and paged results
8. **Filter search prompt + results** (`<leader>jf`) — prompt for filter id with history + results list with detail preview
9. **Saved filters list** (`<leader>jj`) — list of saved filters (favorites first) with owner details
10. **Viewed issue history** (`<leader>jh`) — persisted list of recently viewed issues
11. Issue metrics popup (TBD)
12. Filter metrics popup (TBD)

## Global UX principles

- **Fast by default:** avoid blocking UI on cursor movement.
- **Safe credentials:** never display or log tokens.
- **Keyboard-first:** all flows must be possible without mouse.
- **Graceful degradation:** missing fields/permissions should not crash UI.
- **Consistency:** keybindings and focus behavior should match across popups.

## Layout contracts (invariants)

### Popup sizing

- Popup `width`/`height` are configured as proportions (0..1) unless explicitly fixed.
- Borders default to `rounded` where supported.
- All popups must:
  - fit on screen
  - handle resizing without errors

### Pane model

Where a popup has multiple panes (e.g., issue view with details sidebar):

- panes are independently scrollable
- focus changes do not reset scroll position
- `Tab` / `<S-Tab>` cycles focus between panes or panes within a popup.

## Interaction model (common controls)

These keys should behave consistently across all list/table popups:

- `j` / `k` move selection/cursor
- `gg` jump to top
- `G` jump to bottom
- `v` select char in visual/normal mode (where supported)
- V select line in visual/normal mode (where supported)
- `/` enter search mode (where supported)
- `n` / `N` repeat search (where supported)
- `<C-f>` / `<C-b>` page forward/back where paging exists
- `<CR>` open selected issue / open selected link
- `q` or `Esc` closes popup

Mouse support (optional but nice):

- Cmd+click (macOS) / Ctrl+click (Windows/Linux) on URLs should open them.

## Surface specs

### 1) Issue details popup

**Entry**

- Triggered by the configured keymap (default `<leader>ji`) when cursor is on an issue key match.

**Layout**

- Main pane: issue content (summary, description, activity/comments as applicable)
- Sidebar: key metadata rows (configurable via `popup.details_fields`)
- URL bar/pane (if present): shows Jira URL and allows opening

**Focus + navigation**

- On open: focus starts in the main pane.
- `Tab` cycles focus between main ↔ sidebar ↔ URL bar (if URL bar is present).
- `<C-n>` / `<C-p>` jumps between other issue matches in the source buffer without leaving the popup.
- `yk` copies the issue key to clipboard.
- `ys` copies the issue summary to clipboard.
- `yd` copies the issue description to clipboard.
- `yl` copies the issue URL to clipboard.
- `y` in visual mode copies the selected text.

**Actions**

- `o` opens the issue in the default browser.
- Cursor on a URL + `<CR>` opens that URL.
- When opened from a list popup, `q`/`Esc` returns to that list in the same state.

**States**

- Loading: show a clear loading state while fetching details.
- Error: show a non-throwing error view when the fetch fails.
- Partial: if some fields are missing (permissions/custom fields), render placeholders rather than failing.

### 2) Hover summary output

**Behavior**

- When cursor rests on an issue key, fetch a lightweight summary and display:
  - `<KEY>: <summary>`
  - cached for a short time to avoid rate limits

**Output modes**

- `message` (command area)
- `statusline` (built-in statusline injection)
- `lualine` (component export)

**Performance**

- Must be debounced to avoid firing on every small cursor move.
- Should cache recent summaries briefly to avoid rate limits.

### 3) Buffer issue picker (`<leader>jb`)

**Purpose**

- Show all detected issue keys in the current buffer with line context.
- highlight issue keys in the buffer.

**Layout**

- Table/list of issues with line numbers/context.

**Actions**

- `<CR>` opens issue details for selected entry.
- When `close_on_select = true`, picker closes after opening; otherwise it stays open.
- Closing issue details returns focus to the picker when it remains open.

### 4) Assigned-to-me list (`<leader>ja`)

**Purpose**

- Show unresolved issues assigned to the configured user.

**Layout**

- Table/list with columns sufficient to choose the right issue quickly (key, summary, status, priority, etc.).

**Paging**

- If more than `max_results`, provide paging controls.

### 5) Created-by-me list (`<leader>jc`)

**Purpose**

- Show unresolved issues reported by the current user.

**Layout**

- Table/list with columns sufficient to choose the right issue quickly (key, summary, status, priority, etc.).

**Paging**

- If more than `max_results`, provide paging controls.

### 6) Recently viewed list (`<leader>jr`)

**Purpose**

- Show issues recently viewed by the current user.

**Layout**

- Table/list with columns sufficient to choose the right issue quickly (key, summary, status, priority, etc.).

**Paging**

- If more than `max_results`, provide paging controls.

### 7) JQL search prompt + results (`<leader>js`)

**Prompt UI**

- Input area for JQL.
- Sidebar for query history (size controlled by `history_size`).
- Support loading all entries from the JQL.

**Completion**

- Server-backed suggestions when appropriate.
- Completion must never freeze the UI.
- completion supports JQL keywords, field names, and common values (statuses, priorities, etc.).

**Key behavior**

- `Esc` enters Normal mode in the prompt for editing/yanking.
- `<C-n>` / `<C-p>` navigates history or completion results depending on context.
- Submit with `<CR>` in Normal mode or `<C-y>`.
- Exit with `<C-c><C-c>` or `q`/`Esc`.

**Results UI**

- Table of matching issues.
- Show totals and the current visible range.
- Provide paging (`<C-f>` / `<C-b>`).

### 8) Filter search prompt + results (`<leader>jf`)

**Prompt UI**

- Input area for a numeric Jira filter id.
- Sidebar for filter history (id + name), size controlled by `history_size`.

**Key behavior**

- `Esc` enters Normal mode in the prompt for editing/yanking.
- Submit with `<CR>` in Normal or Insert mode.
- Exit with `<C-c><C-c>` or `q`/`Esc`.

**Results UI**

- Table of matching issues for the filter's JQL.
- Right-side preview pane shows full issue details for the selected row.
- Moving the selection updates the preview pane without leaving the list.
- Provide paging (`<C-f>` / `<C-b>`).
- Opening an issue detail popup from the list returns you to the list on close.
- When the filter id is invalid or not found, show the error in the prompt and keep it open for edits.

### 9) Saved filters list (`<leader>jj`)

**Purpose**

- List saved filters the user can access, with favorites first.

**Layout**

- Table of filters showing a favorite marker (*), filter id, name, and owner.

**Behavior**

- Favorites appear first, followed by the remaining filters owned by the user.
- Selecting a filter submits its id to the filter search flow.

### 10) Viewed issue history (`<leader>jh`)

**Purpose**

- Persist a deduped list of viewed issues for quick reopening.

**Behavior**

- New views add/refresh entries.
- Size limited by `history_size`.

**Storage**

- History should be stored in `stdpath("data")/jira.nvim/issue_history.json`.

### Filter history storage

- Filter search history should be stored in `stdpath("data")/jira.nvim/filter_history.json`.

## Error messaging conventions

- Errors should be actionable and mention the relevant config/env var:
  - missing base URL: suggest `config.api.base_url` or `$JIRA_BASE_URL`
  - missing email: suggest `config.api.email` or `$JIRA_API_EMAIL`
  - missing token: suggest `config.api.token` or `$JIRA_API_TOKEN`/`$JIRA_API_KEY`

## Acceptance checklist (manual)

- [ ] Issue keys underline in a file containing `ABC-123`.
- [ ] Hover shows `<KEY>: <summary>` without noticeable lag.
- [ ] Opening issue popup works; `Tab` cycles panes; `q`/`Esc` closes.
- [ ] `o` opens the issue in a browser.
- [ ] URLs inside the popup open with `<CR>` (and Cmd/Ctrl+click if supported).
- [ ] Buffer picker/assigned list/JQL results allow selecting an issue and opening it.
- [ ] JQL history persists and respects configured size.
- [ ] No secrets appear in logs or UI.

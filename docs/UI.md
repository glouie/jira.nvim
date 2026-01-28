# UI / UX Specification — jira.nvim

This document describes the intended user-facing UI surfaces in `jira.nvim`, their layout, interactions, and states.

The goal is to make UI changes predictable and reviewable:
- when behavior changes, update this file
- new UI surfaces must be added here

## Surfaces (what the plugin renders)

1) **Issue details popup** (open issue under cursor)
2) **Hover summary output** (command area / statusline / lualine)
3) **Buffer issue picker** (`<leader>jb`) — issue keys detected in current buffer
4) **Assigned-to-me list** (`<leader>ja`) — unresolved issues assigned to current user
5) **JQL search prompt + results** (`<leader>js`) — prompt with history + server-backed suggestions and paged results
6) **Viewed issue history** (`<leader>jh`) — persisted list of recently viewed issues

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
- `Tab` / `<S-Tab>` cycles focus between panes

## Interaction model (common controls)

These keys should behave consistently across all list/table popups:
- `j` / `k` move selection/cursor
- `gg` jump to top
- `G` jump to bottom
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

**Actions**
- `o` opens the issue in the default browser.
- Cursor on a URL + `<CR>` opens that URL.

**States**
- Loading: show a clear loading state while fetching details.
- Error: show a non-throwing error view when the fetch fails.
- Partial: if some fields are missing (permissions/custom fields), render placeholders rather than failing.

### 2) Hover summary output

**Behavior**
- When cursor rests on an issue key, fetch a lightweight summary and display:
  - `<KEY>: <summary>`

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

**Layout**
- Table/list of issues with line numbers/context.

**Actions**
- `<CR>` opens issue details for selected entry.
- When `close_on_select = true`, picker closes after opening; otherwise it stays open.

### 4) Assigned-to-me list (`<leader>ja`)

**Purpose**
- Show unresolved issues assigned to the configured user.

**Layout**
- Table/list with columns sufficient to choose the right issue quickly (key, summary, status, priority, etc.).

**Paging**
- If more than `max_results`, provide paging controls.

### 5) JQL search prompt + results (`<leader>js`)

**Prompt UI**
- Input area for JQL.
- Sidebar for query history (size controlled by `history_size`).

**Completion**
- Server-backed suggestions when appropriate.
- Completion must never freeze the UI.

**Key behavior**
- `Esc` enters Normal mode in the prompt for editing/yanking.
- `<C-n>` / `<C-p>` navigates history or completion results depending on context.
- Submit with `<CR>` in Normal mode or `<C-y>`.
- Exit with `<C-c>` or `q`/`Esc`.

**Results UI**
- Table of matching issues.
- Show totals and the current visible range.
- Provide paging (`<C-f>` / `<C-b>`).

### 6) Viewed issue history (`<leader>jh`)

**Purpose**
- Persist a deduped list of viewed issues for quick reopening.

**Behavior**
- New views add/refresh entries.
- Size limited by `history_size`.

**Storage**
- History should be stored in `stdpath("data")/jira.nvim/issue_history.json`.

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

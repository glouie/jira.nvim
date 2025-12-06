# jira.nvim

A lightweight Neovim companion for browsing Atlassian JIRA issues without
leaving the editor. jira.nvim scans the current buffer for strings that
resemble issue keys (for example `SPL-12345` or `CINC-54`), underlines
them, and lets you inspect the full issue details directly in a floating
popup.

## Features

- Automatically underlines issue keys that match `%u+-%d+`.
- Opens a floating popup with the issue summary, description, and recent
  activity.
- Sidebar highlights important metadata like status, priority, resolution,
  and assignee.
- When your cursor rests on an issue key, the command area (below your
  statusline) shows `<KEY>: <issue summary>`. The hover text sticks around
  until you move the cursor to another issue key or leave the window. You can
  opt into statusline/lualine placement instead.
- Press `o` inside the popup to jump to the issue in your browser, or
  `Esc`/`q` to close it.
- Popups support `/` search, `n`/`N` to repeat, `Tab`/`<S-Tab>` to swap
  panes, and `<C-n>`/`<C-p>` to hop between other issue matches in the
  buffer without leaving the view.
- `<leader>jb` opens a fzf-style list of issue keys in the current buffer with
  line context so you can jump straight into their details.
- `<leader>ja` shows a quick table of unresolved issues assigned to you so
  you can jump straight into the one you care about.
- `<leader>js` opens a highlighted JQL prompt with inline help and
  server-backed suggestions, then displays the matching issues with paging
  controls and totals.
- `<leader>jh` opens a persisted list of issues you've viewed, deduped and
  ready to reopen with `<CR>`.
- Uses your Atlassian Cloud API token, sourced from environment variables,
  so credentials never touch the repo.

## Installation

Use your favourite plugin manager. Example with
[`lazy.nvim`](https://github.com/folke/lazy.nvim):

```lua
{
  "glouie/jira.nvim",
  opts = {
    keymap = "<leader>ji",
    popup = {
      width = 0.6,
      height = 0.7,
    },
  },
}
```

## Configuration

jira.nvim reads your credentials from environment variables by default:

- `JIRA_BASE_URL` (e.g. `https://your-domain.atlassian.net`)
- `JIRA_API_EMAIL` (the Atlassian account email)
- `JIRA_API_TOKEN` (or `JIRA_API_KEY`) – create one at
  <https://id.atlassian.com/manage-profile/security/api-tokens>

You can override any of these (plus visual behaviour) via
`require("jira").setup({ ... })`. Available options:

```lua
require("jira").setup({
  keymap = "<leader>ji",
  -- key used to open the popup for the issue under the cursor
  debug = false,
  -- set true to log when the cursor lands on an issue key
  issue_pattern = "%u+-%d+",
  -- Lua pattern for matching issue keys
  highlight_group = "JiraIssue",
  -- highlight used to underline matches
  max_lines = -1,
  -- number of lines to scan for issue keys (-1 scans the whole buffer)
  ignored_projects = { "SEV" },
  -- project keys to skip when scanning for issue matches
  statusline = {
    enabled = true,
    -- set to false to leave your statusline untouched
    output = "message",
    -- "message" shows in the command area; use "statusline" or "lualine" to embed it there
    max_length = 80,
    -- truncate long summaries to avoid crowding the bar (0 means no limit)
    loading_text = "Loading...",
    -- shown while jira.nvim fetches the summary
    error_text = "Unable to load issue",
    -- shown when the summary request fails
    empty_text = "No summary",
    -- fallback when an issue has a blank summary
    message_highlight = nil,
    -- highlight group used when output = "message" (for color/bold/italic)
  },
  assigned_popup = {
    keymap = "<leader>ja",
    -- opens the assigned-issues list popup
    width = 0.55,
    height = 0.5,
    max_results = 50,
  },
  search_popup = {
    keymap = "<leader>js",
    -- prompts for JQL and shows the result list
    width = 0.6,
    height = 0.6,
    max_results = 50,
    history_size = 50,
    -- how many past searches to show in the prompt sidebar
  },
  history_popup = {
    keymap = "<leader>jh",
    -- opens the recently-viewed issues table
    width = 0.55,
    height = 0.5,
    history_size = 200,
    -- how many unique issues to keep (oldest drop off)
  },
  buffer_popup = {
    keymap = "<leader>jb",
    -- lists all detected issue keys in the current buffer
    width = 0.55,
    height = 0.5,
    border = "rounded",
    close_on_select = true,
    -- close the picker after opening an issue from it
  },
  popup = {
    width = 0.6,
    height = 0.7,
    border = "rounded",
    details_fields = { "key", "status", "priority", "assignee", "reporter", "labels" },
    -- choose which fields render in the Details sidebar and their order
  },
  api = {
    base_url = os.getenv("JIRA_BASE_URL"),
    email = os.getenv("JIRA_API_EMAIL"),
    token = os.getenv("JIRA_API_TOKEN")
      or os.getenv("JIRA_API_KEY"),
  },
})
```
Set `ignored_projects` to a list of project prefixes (defaults to `{ "SEV" }`)
when you need to avoid false positives such as severity labels that resemble
issue keys. JQL search history is stored at
`stdpath("data")/jira.nvim/search_history.json` and respects `history_size`
(set it to `0` to skip saving and showing history). Viewed issue history lives
beside it in `issue_history.json` and is deduplicated by key; set
`history_popup.history_size` to `0` to disable it. Use `max_lines` to cap how
many lines in the current buffer are scanned for issue keys when you only want
to underline the top of very large files. Customize `assigned_popup` to tweak
the keybinding, size, or number of issues returned by the "assigned to me"
list, `search_popup` for the JQL prompt/table layout, and `buffer_popup` to
control the in-buffer picker (size, border, and whether it closes after
selection). Issue tables show the total result count, the range currently
visible, and let you move between rows with `j`/`k` (or `<S-N>/<S-P>`), page
with `<C-f>/<C-b>`, and hit `<CR>` to open the selected issue without
dismissing the list.

The Details sidebar rows follow `popup.details_fields`, which accepts a list to
set both the fields and their order (defaults keep labels at the bottom). Use it
to hide entries you do not care about or to elevate the ones you check often.

Hovering over an issue key triggers a lightweight summary fetch and surfaces
`<KEY>: <summary>` in the command area by default (under your statusline).
Set `statusline.output = "statusline"` to use the built-in statusline layout,
or `statusline.output = "lualine"` to feed the built-in lualine component
without touching `vim.o.statusline`. If you already manage your own
statusline layout, keep `statusline.enabled = false` and embed
`%{v:lua.require('jira').statusline_message()}` (or add
`require("jira").lualine_component` to your lualine config) wherever you want
the Jira hover text to appear. Setting `statusline = false` behaves the same
as `statusline.enabled = false` while still keeping the hover text available
for manual placement. When `output = "message"`, set `statusline.message_highlight`
to a highlight group name if you want colored/bold/italic hover text in the
command area.

Example lualine component:

```lua
require("lualine").setup({
  sections = {
    lualine_c = {
      require("jira").lualine_component,
    },
  },
})
```

## Usage

1. Make sure your env vars are exported before launching Neovim.
2. Open any buffer that contains JIRA issue keys.
3. The matches are underlined automatically. Place your cursor on one and
   press the configured keymap (default `<leader>ji`).
4. Inspect the popup. Use `j`/`k`, `gg`, or `G` to move around; `/` plus
   `n`/`N` to search inside the popup; `Tab`/`<S-Tab>` to swap focus between
   the main pane, sidebar, and URL bar; `<C-n>`/`<C-p>` to jump to the next or
   previous issue match in the buffer; `o` to open the issue in a browser;
   place the cursor on any URL and press `<CR>` or Cmd+click (macOS)/Ctrl+click
   (Windows) to open it; `Esc` or `q` to close it.
5. Press `<leader>jb` to list every issue key in the current buffer (with line
   numbers) and open one with `<CR>`. Press `<leader>ja` to see unresolved
   issues assigned to you, `<leader>js` to enter a JQL query and page through
   the matches, or `<leader>jh` to reopen something you viewed recently
   (history is deduped and persisted between sessions). Use `j`/`k` (or
   `<S-N>/<S-P>`) to move through the list, `<CR>` to open an issue (the buffer
   picker closes by default; other lists stay open so you can come right back),
   `<C-f>/<C-b>` to change pages, and `q`/`Esc` to close the popup(s).

Inside the JQL prompt, `Esc` drops you into Normal mode so you can
edit/yank/clear text with your usual motions. The left sidebar lists your
recent queries (latest at the bottom); browse it with `<C-n>/<C-p>`, preview
entries in the input as you highlight them, press `<CR>` to load one without
submitting, and press `<Tab>` in Normal mode to swap focus between the input
and history pane (in Insert mode `<Tab>` still cancels a preview). Submit with
`<CR>` in Normal mode or `<C-y>`, and when the completion menu is visible
`<C-n>/<C-p>` still cycle suggestions. Exit with `<C-c>` (insert or normal) or
`q` (normal).

## Roadmap

- Better formatting for rich text / description content.
- Caching and offline support.
- Inline commands for transitioning or commenting on issues.

## License

Released under the [MIT License](LICENSE).

PRs and suggestions are welcome!

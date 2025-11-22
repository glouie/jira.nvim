# jira.nvim

A lightweight Neovim companion for browsing Atlassian JIRA issues without leaving the editor. jira.nvim scans the current buffer for strings that resemble issue keys (for example `SPL-12345` or `CINC-54`), underlines them, and lets you inspect the full issue details directly in a floating popup.

## Features

- Automatically underlines issue keys that match `%u+-%d+`.
- Opens a floating popup with the issue summary, description, and recent activity.
- Sidebar highlights important metadata like status, priority, resolution, and assignee.
- Press `o` inside the popup to jump to the issue in your browser, or `Esc`/`q` to close it.
- Popups support `/` search, `n`/`N` to repeat, `Tab`/`<S-Tab>` to swap panes, and `<C-n>`/`<C-p>` to hop between other issue matches in the buffer without leaving the view.
- `<leader>ja` shows a quick table of unresolved issues assigned to you so you can jump straight into the one you care about.
- `<leader>js` opens a highlighted JQL prompt with inline help and server-backed suggestions, then displays the matching issues with paging controls and totals.
- Uses your Atlassian Cloud API token, sourced from environment variables, so credentials never touch the repo.

## Installation

Use your favourite plugin manager. Example with [`lazy.nvim`](https://github.com/folke/lazy.nvim):

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
- `JIRA_API_TOKEN` (or `JIRA_API_KEY`) – create one at <https://id.atlassian.com/manage-profile/security/api-tokens>

You can override any of these (plus visual behaviour) via `require("jira").setup({ ... })`. Available options:

```lua
require("jira").setup({
  keymap = "<leader>ji", -- key used to open the popup for the issue under the cursor
  issue_pattern = "%u+-%d+", -- Lua pattern for matching issue keys
  highlight_group = "JiraIssue", -- highlight used to underline matches
  max_lines = -1, -- number of lines to scan for issue keys (-1 scans the whole buffer)
  ignored_projects = { "SEV" }, -- project keys to skip when scanning for issue matches
  assigned_popup = {
    keymap = "<leader>ja", -- opens the assigned-issues list popup
    width = 0.55,
    height = 0.5,
    max_results = 50,
  },
  search_popup = {
    keymap = "<leader>js", -- prompts for JQL and shows the result list
    width = 0.6,
    height = 0.6,
    max_results = 50,
  },
  popup = {
    width = 0.6,
    height = 0.7,
    border = "rounded",
  },
  api = {
    base_url = os.getenv("JIRA_BASE_URL"),
    email = os.getenv("JIRA_API_EMAIL"),
    token = os.getenv("JIRA_API_TOKEN") or os.getenv("JIRA_API_KEY"),
  },
})
```
Set `ignored_projects` to a list of project prefixes (defaults to `{ "SEV" }`) when you need to avoid false positives such as severity labels that resemble issue keys.
Use `max_lines` to cap how many lines in the current buffer are scanned for issue keys when you only want to underline the top of very large files.
Customize `assigned_popup` to tweak the keybinding, size, or number of issues returned by the "assigned to me" list, and `search_popup` for the JQL prompt/table layout. Issue tables show the total result count, the range currently visible, and let you move between rows with `j`/`k` (or `<S-N>/<S-P>`), page with `<C-f>/<C-b>`, and hit `<CR>` to open the selected issue without dismissing the list.

## Usage

1. Make sure your env vars are exported before launching Neovim.
2. Open any buffer that contains JIRA issue keys.
3. The matches are underlined automatically. Place your cursor on one and press the configured keymap (default `<leader>ji`).
4. Inspect the popup. Use `j`/`k`, `gg`, or `G` to move around; `/` plus `n`/`N` to search inside the popup; `Tab`/`<S-Tab>` to swap focus between the main pane, sidebar, and URL bar; `<C-n>`/`<C-p>` to jump to the next or previous issue match in the buffer; `o` to open the issue in a browser; place the cursor on any URL and press `<CR>` or Cmd+click (macOS)/Ctrl+click (Windows) to open it; `Esc` or `q` to close it.
5. Press `<leader>ja` to see unresolved issues assigned to you, or `<leader>js` to enter a JQL query and page through the matches. Use `j`/`k` (or `<S-N>/<S-P>`) to move through the list, `<CR>` to open an issue (the list stays open so you can come right back), `<C-f>/<C-b>` to change pages, and `q`/`Esc` to close the popup(s).

Inside the JQL prompt, `Esc` drops you into Normal mode so you can edit/yank/clear text with your usual motions. Submit with `<CR>` or `<C-y>`, navigate completion items with `<C-n>/<C-p>`, and exit with `<C-c>` (insert or normal) or `q` (normal).

## Roadmap

- Better formatting for rich text / description content.
- Caching and offline support.
- Inline commands for transitioning or commenting on issues.

## License

Released under the [MIT License](LICENSE).

PRs and suggestions are welcome!

# jira.nvim

A lightweight Neovim companion for browsing Atlassian JIRA issues without leaving the editor. jira.nvim scans the current buffer for strings that resemble issue keys (for example `SPL-12345` or `CINC-54`), underlines them, and lets you inspect the full issue details directly in a floating popup.

## Features

- Automatically underlines issue keys that match `%u+-%d+`.
- Opens a floating popup with the issue summary, description, and recent activity.
- Sidebar highlights important metadata like status, priority, resolution, and assignee.
- Press `o` inside the popup to jump to the issue in your browser, or `Esc`/`q` to close it.
- Uses your Atlassian Cloud API token, sourced from environment variables, so credentials never touch the repo.

## Installation

Use your favourite plugin manager. Example with [`lazy.nvim`](https://github.com/folke/lazy.nvim):

```lua
{
  "jira.nvim",
  dir = "/path/to/jira.nvim",
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
  ignored_projects = { "SEV" }, -- project keys to skip when scanning for issue matches
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

## Usage

1. Make sure your env vars are exported before launching Neovim.
2. Open any buffer that contains JIRA issue keys.
3. The matches are underlined automatically. Place your cursor on one and press the configured keymap (default `<leader>ji`).
4. Inspect the popup. Use `j`/`k` to scroll, `o` to open the issue in a browser, `Esc` or `q` to close it.

## Roadmap

- Better formatting for rich text / description content.
- Caching and offline support.
- Inline commands for transitioning or commenting on issues.

PRs and suggestions are welcome!

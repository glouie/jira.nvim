# jira.nvim

Browse Jira issues without leaving Neovim.

jira.nvim highlights issue keys in your buffers, fetches summaries on hover, and
provides floating popups for searching, navigating, and inspecting issues — all
driven by the Jira REST API over plain `curl`.

---

## Features

- **Hover preview** — when your cursor rests on an issue key (e.g. `ABC-123`),
  the issue summary is shown in the statusline, as a lualine component, or in
  the echo area.
- **Floating issue popup** — open a detailed view of any issue with a full
  details pane; navigate forward and backward through issues without closing the
  popup.
- **JQL search with history** — enter any JQL query from a prompt; previous
  queries are saved and offered as a selectable history list.
- **Assigned issues list** — one keymap to see all unresolved issues currently
  assigned to you.
- **Created issues list** — browse issues you reported.
- **Recently-viewed issues list** — server-side recency pulled from Jira's own
  activity log.
- **Filter search by ID** — open issues returned by a saved Jira filter using
  its numeric ID; filter IDs are remembered in a local history.
- **Saved-filters browser** — list and select from all of your saved Jira
  filters by name.
- **Local issue history popup** — a client-side log of every issue you have
  opened in jira.nvim, separate from Jira's server-side recency, persisted
  between sessions.
- **Buffer issue list** — list every issue key found in the current buffer and
  open any of them without leaving the window.
- **`:checkhealth jira`** — built-in health check that verifies Neovim version,
  `curl` availability, API credentials, and optional lualine integration.

---

## Requirements

| Requirement | Notes |
|---|---|
| Neovim >= 0.10 | `vim.system` is used for async HTTP requests |
| `curl` in `PATH` | All API calls are made via `curl` |
| Jira API email | The email address of your Atlassian account |
| Jira API token | Generated from your Atlassian account settings |

**Generating an API token**

1. Go to <https://id.atlassian.com/manage-profile/security/api-tokens>.
2. Click **Create API token**, give it a label, and copy the value immediately
   (it is not shown again).
3. Export it in your shell profile as `JIRA_API_TOKEN` (see Configuration).

---

## Installation

### lazy.nvim

Minimal setup — credentials from environment variables:

```lua
{
  "glouie/jira.nvim",
  event = "VeryLazy",
  opts = {
    api = {
      base_url = os.getenv("JIRA_BASE_URL") or "",
      email    = os.getenv("JIRA_API_EMAIL") or "",
      token    = os.getenv("JIRA_API_TOKEN") or "",
    },
  },
}
```

Full configuration (see all options in the [Configuration](#configuration) section):

```lua
{
  "glouie/jira.nvim",
  event = "VeryLazy",
  config = function()
    require("jira").setup({
      keymap           = "<leader>ji",
      debug            = false,
      issue_pattern    = "%u+-%d+",
      highlight_group  = "JiraIssue",
      max_lines        = -1,
      ignored_projects = { "SEV" },
      statusline = {
        enabled      = true,
        output       = "lualine",
        max_length   = 80,
        loading_text = "Loading...",
        error_text   = "Unable to load issue",
        empty_text   = "No summary",
      },
      api = {
        base_url = os.getenv("JIRA_BASE_URL") or "",
        email    = os.getenv("JIRA_API_EMAIL") or "",
        token    = os.getenv("JIRA_API_TOKEN") or "",
      },
    })
  end,
}
```

### packer.nvim

```lua
use {
  "glouie/jira.nvim",
  config = function()
    require("jira").setup({
      api = {
        base_url = os.getenv("JIRA_BASE_URL") or "",
        email    = os.getenv("JIRA_API_EMAIL") or "",
        token    = os.getenv("JIRA_API_TOKEN") or "",
      },
    })
  end,
}
```

### vim-plug

```vim
Plug 'glouie/jira.nvim'
```

Then in your `init.lua` (or inside a `lua` heredoc in `init.vim`):

```lua
require("jira").setup({
  api = {
    base_url = os.getenv("JIRA_BASE_URL") or "",
    email    = os.getenv("JIRA_API_EMAIL") or "",
    token    = os.getenv("JIRA_API_TOKEN") or "",
  },
})
```

---

## Configuration

All keys are optional. Values shown are the defaults.

```lua
require("jira").setup({

  -- Keymap to open the issue detail popup for the key under the cursor.
  keymap = "<leader>ji",

  -- Write API request/response logs to
  -- ~/.cache/nvim/jira.nvim/api_access.log when true.
  debug = false,

  -- Lua pattern used to identify issue keys in buffer text.
  issue_pattern = "%u+-%d+",

  -- Highlight group applied to matched issue keys.
  highlight_group = "JiraIssue",

  -- Maximum number of buffer lines scanned for issue keys. -1 = unlimited.
  max_lines = -1,

  -- Project prefixes that are never treated as issue keys.
  ignored_projects = { "SEV" },

  -- Controls how the hover summary is displayed.
  statusline = {
    enabled           = true,
    -- Output mode: "message" | "statusline" | "lualine"
    output            = "message",
    -- Maximum display width of the summary (0 = no limit).
    max_length        = 80,
    loading_text      = "Loading...",
    error_text        = "Unable to load issue",
    empty_text        = "No summary",
    -- Optional highlight group for message-mode output (color/bold/italic).
    message_highlight = nil,
  },

  -- Issue detail popup (opened by keymap or :JiraOpenIssue).
  popup = {
    width  = 0.65,   -- fraction of editor width
    height = 0.75,   -- fraction of editor height
    border = "rounded",
    -- Fields rendered in the details pane, in order.
    -- Remove entries you don't need or reorder to surface what matters most.
    details_fields = {
      "key", "status", "resolution", "priority", "severity",
      "assignee", "reporter", "created", "updated", "due",
      "fix_versions", "affects_versions", "open_duration",
      "comments", "changes", "assignees", "labels",
    },
  },

  -- Popup listing unresolved issues assigned to the current user.
  assigned_popup = {
    keymap      = "<leader>ja",
    width       = 0.55,
    height      = 0.5,
    border      = "rounded",
    max_results = 50,
    -- Optional: override the JQL used to fetch assigned issues.
    -- jql = "assignee = currentUser() AND resolution = Unresolved ORDER BY updated DESC",
  },

  -- Popup listing issues created/reported by the current user.
  created_popup = {
    keymap      = "<leader>jc",
    width       = 0.55,
    height      = 0.5,
    border      = "rounded",
    max_results = 50,
  },

  -- Popup listing recently-viewed issues (Jira server-side activity).
  recent_popup = {
    keymap      = "<leader>jr",
    width       = 0.55,
    height      = 0.5,
    border      = "rounded",
    max_results = 50,
  },

  -- Popup with a JQL search prompt and saved query history.
  search_popup = {
    keymap       = "<leader>js",
    width        = 0.6,
    height       = 0.6,
    border       = "rounded",
    max_results  = 50,
    history_size = 50,  -- number of past queries to retain on disk
  },

  -- Popup for opening issues via a saved Jira filter ID.
  filter_popup = {
    keymap       = "<leader>jf",
    width        = 0.6,
    height       = 0.6,
    border       = "rounded",
    max_results  = 50,
    history_size = 50,  -- number of past filter IDs to retain on disk
  },

  -- Popup that lists your saved Jira filters by name.
  filter_list_popup = {
    keymap      = "<leader>jj",
    width       = 0.6,
    height      = 0.6,
    border      = "rounded",
    max_results = 100,
  },

  -- Popup showing locally-tracked issue open history (client-side log).
  history_popup = {
    keymap       = "<leader>jh",
    width        = 0.55,
    height       = 0.5,
    border       = "rounded",
    history_size = 200,  -- max entries kept on disk; oldest drop off
  },

  -- Popup listing every issue key found in the current buffer.
  buffer_popup = {
    keymap          = "<leader>jb",
    width           = 0.55,
    height          = 0.5,
    border          = "rounded",
    close_on_select = false,  -- keep list open after opening an issue
  },

  -- Jira API credentials.
  -- Prefer environment variables; never commit tokens to version control.
  api = {
    base_url = os.getenv("JIRA_BASE_URL") or "",  -- https://your-domain.atlassian.net
    email    = os.getenv("JIRA_API_EMAIL") or "",
    token    = os.getenv("JIRA_API_TOKEN") or os.getenv("JIRA_API_KEY") or "",
  },

})
```

### Full option reference

| Key | Type | Default | Description |
|---|---|---|---|
| `keymap` | string | `"<leader>ji"` | Open detail popup for key under cursor |
| `debug` | boolean | `false` | Enable API request/response logging |
| `issue_pattern` | string | `"%u+-%d+"` | Lua pattern for matching issue keys |
| `highlight_group` | string | `"JiraIssue"` | Highlight group applied to matched keys |
| `max_lines` | integer | `-1` | Lines scanned per buffer; `-1` = all |
| `ignored_projects` | string[] | `{ "SEV" }` | Project prefixes excluded from scanning |
| `statusline.enabled` | boolean | `true` | Enable hover summary display |
| `statusline.output` | string | `"message"` | `"message"`, `"statusline"`, or `"lualine"` |
| `statusline.max_length` | integer | `80` | Max display width of the summary (0 = no limit) |
| `statusline.loading_text` | string | `"Loading..."` | Shown while the API request is in flight |
| `statusline.error_text` | string | `"Unable to load issue"` | Shown on API error |
| `statusline.empty_text` | string | `"No summary"` | Shown when the issue has no summary field |
| `statusline.message_highlight` | string\|nil | `nil` | Highlight group for message-mode output |
| `popup.width` | number | `0.65` | Detail popup width as fraction of editor width |
| `popup.height` | number | `0.75` | Detail popup height as fraction of editor height |
| `popup.border` | string | `"rounded"` | Border style (any `nvim_open_win` value) |
| `popup.details_fields` | string[] | *(see above)* | Fields shown in the details pane, in order |
| `assigned_popup.keymap` | string | `"<leader>ja"` | Open assigned-issues list |
| `assigned_popup.max_results` | integer | `50` | Max results fetched from the API |
| `created_popup.keymap` | string | `"<leader>jc"` | Open created-issues list |
| `created_popup.max_results` | integer | `50` | Max results fetched from the API |
| `recent_popup.keymap` | string | `"<leader>jr"` | Open recently-viewed issues list |
| `recent_popup.max_results` | integer | `50` | Max results fetched from the API |
| `search_popup.keymap` | string | `"<leader>js"` | Open JQL search prompt |
| `search_popup.max_results` | integer | `50` | Max results per query |
| `search_popup.history_size` | integer | `50` | Saved query entries retained on disk |
| `filter_popup.keymap` | string | `"<leader>jf"` | Open filter-by-ID prompt |
| `filter_popup.max_results` | integer | `50` | Max results per filter |
| `filter_popup.history_size` | integer | `50` | Saved filter ID entries retained on disk |
| `filter_list_popup.keymap` | string | `"<leader>jj"` | Open saved-filters browser |
| `filter_list_popup.max_results` | integer | `100` | Max filters fetched from the API |
| `history_popup.keymap` | string | `"<leader>jh"` | Open local issue history |
| `history_popup.history_size` | integer | `200` | Max entries kept in local history |
| `buffer_popup.keymap` | string | `"<leader>jb"` | Open buffer issue list |
| `buffer_popup.close_on_select` | boolean | `false` | Close list popup when an issue is opened |
| `api.base_url` | string | `""` | Your Atlassian domain, e.g. `https://acme.atlassian.net` |
| `api.email` | string | `""` | Atlassian account email |
| `api.token` | string | `""` | API token (or `JIRA_API_KEY` legacy alias) |

All popup tables also accept `width`, `height`, and `border` keys with the same
meaning as `popup.width`, `popup.height`, and `popup.border`.

### Environment variables

Credentials can be supplied entirely via environment variables without touching
the `api` table:

| Variable | Maps to |
|---|---|
| `JIRA_BASE_URL` | `api.base_url` |
| `JIRA_API_EMAIL` | `api.email` |
| `JIRA_API_TOKEN` | `api.token` |
| `JIRA_API_KEY` | `api.token` (legacy alias) |

---

## Default keymaps

| Key | Action |
|---|---|
| `<leader>ji` | Open the issue detail popup for the key under the cursor |
| `<leader>ja` | Open the assigned-issues list popup |
| `<leader>jc` | Open the created-issues list popup |
| `<leader>jr` | Open the recently-viewed issues list popup (server-side) |
| `<leader>js` | Open the JQL search prompt popup |
| `<leader>jf` | Open the filter-by-ID prompt popup |
| `<leader>jj` | Open the saved-filters browser popup |
| `<leader>jh` | Open the local issue history popup (client-side) |
| `<leader>jb` | Open the buffer issue list popup |

All keymaps are configurable via the `keymap` field of the corresponding popup
table. Set a `keymap` field to `nil` or `""` to disable that binding.

---

## Commands

| Command | Description |
|---|---|
| `:JiraOpenIssue [KEY]` | Open the detail popup for KEY, or the key under the cursor when no argument is given |
| `:JiraOpenCursor` | Open the detail popup for the issue key under the cursor |
| `:JiraSearch` | Open the JQL search prompt popup |
| `:JiraAssigned` | Open the assigned-issues list popup |
| `:JiraCreated` | Open the created-issues list popup |
| `:JiraRecent` | Open the recently-viewed issues list popup |
| `:JiraHistory` | Open the local issue history popup |
| `:JiraFilter` | Open the filter-by-ID prompt popup |
| `:JiraFilters` | Open the saved-filters browser popup |
| `:JiraBuffer` | Open the buffer issue list popup |

---

## Statusline integration

jira.nvim supports three output modes controlled by `statusline.output`.

### `"message"` (default)

The issue summary is echoed to the command area using `vim.api.nvim_echo`. No
statusline string is modified. This is the safest option and works with any
statusline plugin.

```lua
statusline = { output = "message" }
```

### `"statusline"`

jira.nvim takes ownership of `vim.o.statusline` and injects the hover summary
into a custom layout string. The original value is saved and restored when the
summary is cleared. Use this if you do not have a statusline plugin and want the
summary in the bar itself.

```lua
statusline = { output = "statusline" }
```

You can also embed the summary manually in your own statusline string:

```vim
set statusline+=%{v:lua.require('jira').statusline_message()}
```

### `"lualine"`

jira.nvim calls `lualine.refresh()` after updating the summary and exposes a
component function you place anywhere in your lualine layout. lualine must be
installed.

```lua
statusline = { output = "lualine" }
```

Add the component to your lualine configuration:

```lua
require("lualine").setup({
  sections = {
    lualine_c = {
      -- your other components,
      {
        function()
          return require("jira").lualine_component()
        end,
        cond = function()
          return require("jira").lualine_component() ~= ""
        end,
      },
    },
  },
})
```

`lualine_component()` returns the current hover summary as a plain string, or
`""` when nothing is active.

---

## Health check

Run the built-in health check at any time:

```vim
:checkhealth jira
```

The health check covers:

- **Neovim version** — confirms `vim.system` is available (>= 0.10); warns if
  on 0.8–0.9 where a `vim.fn.jobstart` fallback is used; errors below 0.8.
- **curl** — locates `curl` in `PATH` and reports its version string.
- **Credentials** — verifies that `api.base_url`, `api.email`, and `api.token`
  are all non-empty; warns if `base_url` uses `http://` instead of `https://`.
- **lualine** (optional) — reports whether lualine is present for statusline
  integration.

If `setup()` has not been called yet, the check falls back to inspecting
`JIRA_BASE_URL`, `JIRA_API_EMAIL`, and `JIRA_API_TOKEN` directly.

---

## License

MIT

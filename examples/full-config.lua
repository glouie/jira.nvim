-- Example: full configuration for jira.nvim
-- Drop this into your Neovim config and adjust values as needed.
-- Run :checkhealth jira to verify your setup.

require("jira").setup({
  -- Key used to open the popup for the issue under the cursor.
  keymap = "<leader>ji",

  -- Enable debug mode: writes API request/response logs to
  -- ~/.cache/nvim/jira.nvim/api_access.log (off by default).
  debug = false,

  -- Lua pattern for matching issue keys, e.g. ABC-123. Change to match your org.
  issue_pattern = "%u+-%d+",

  -- Highlight used to underline matches in your buffers.
  highlight_group = "JiraIssue",

  -- Limit how many lines are scanned for matches; -1 scans the whole buffer.
  max_lines = -1,

  -- Project prefixes to ignore during scanning to avoid false positives.
  ignored_projects = { "SEV" },

  -- Statusline integration: "message" (vim.notify echo area), "statusline"
  -- (injects into vim.o.statusline), or "lualine" (auto-detected).
  statusline = {
    enabled = true,
    output = "message",
    max_length = 80,
    loading_text = "Loading...",
    error_text = "Unable to load issue",
    empty_text = "No summary",
  },

  -- Popup for the current issue under the cursor.
  popup = {
    width = 0.65,
    height = 0.75,
    border = "rounded",
    -- Reorder or remove fields shown in the details pane:
    details_fields = {
      "key", "status", "resolution", "priority", "severity",
      "assignee", "reporter", "created", "updated", "due",
      "fix_versions", "affects_versions", "open_duration",
      "comments", "changes", "assignees", "labels",
    },
  },

  -- Popup that lists unresolved issues assigned to you (<leader>ja).
  assigned_popup = {
    keymap = "<leader>ja",
    width = 0.55,
    height = 0.5,
    border = "rounded",
    max_results = 50,
    -- Optional custom JQL for the assigned list:
    -- jql = "assignee = currentUser() AND resolution = Unresolved ORDER BY updated DESC",
  },

  -- Popup that lists issues you reported (<leader>jc).
  created_popup = {
    keymap = "<leader>jc",
    width = 0.55,
    height = 0.5,
    border = "rounded",
    max_results = 50,
  },

  -- Popup that lists recently viewed issues (Jira server-side) (<leader>jr).
  recent_popup = {
    keymap = "<leader>jr",
    width = 0.55,
    height = 0.5,
    border = "rounded",
    max_results = 50,
  },

  -- Popup for a JQL search prompt (<leader>js).
  search_popup = {
    keymap = "<leader>js",
    width = 0.6,
    height = 0.6,
    border = "rounded",
    max_results = 50,
    history_size = 50, -- max number of saved search queries
  },

  -- Popup for opening issues by saved filter ID (<leader>jf).
  filter_popup = {
    keymap = "<leader>jf",
    width = 0.6,
    height = 0.6,
    border = "rounded",
    max_results = 50,
    history_size = 50,
  },

  -- Popup that lists your saved Jira filters by name (<leader>jj).
  filter_list_popup = {
    keymap = "<leader>jj",
    width = 0.6,
    height = 0.6,
    border = "rounded",
    max_results = 100,
  },

  -- Popup that shows locally-tracked opened issue history (<leader>jh).
  -- (Different from <leader>jr which is Jira's server-side recency.)
  history_popup = {
    keymap = "<leader>jh",
    width = 0.55,
    height = 0.5,
    border = "rounded",
    history_size = 200,
  },

  -- Popup that lists all issue keys referenced in the current buffer (<leader>jb).
  buffer_popup = {
    keymap = "<leader>jb",
    width = 0.55,
    height = 0.5,
    border = "rounded",
    close_on_select = false,
  },

  -- Jira API credentials — read from environment variables by default.
  -- Never hardcode tokens here; use env vars or a secrets manager.
  api = {
    base_url = os.getenv("JIRA_BASE_URL") or "", -- e.g. https://your-domain.atlassian.net
    email    = os.getenv("JIRA_API_EMAIL") or "",
    token    = os.getenv("JIRA_API_TOKEN") or os.getenv("JIRA_API_KEY") or "",
  },
})

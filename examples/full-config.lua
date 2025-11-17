-- Example: full configuration for jira.nvim
-- Drop this into your Neovim config and adjust values as needed.

require("jira").setup({
  -- Key used to open the popup for the issue under the cursor.
  keymap = "<leader>ji",

  -- Lua pattern for matching issue keys, e.g. ABC-123. Change to match your org.
  issue_pattern = "%u+-%d+",

  -- Highlight used to underline matches in your buffers.
  highlight_group = "JiraIssue",

  -- Limit how many lines are scanned for matches; -1 scans the whole buffer.
  max_lines = -1,

  -- Project prefixes to ignore during scanning to avoid false positives.
  ignored_projects = { "SEV" },

  -- Popup for the current issue under the cursor.
  popup = {
    width = 0.65,
    height = 0.75,
    border = "rounded",
  },

  -- Popup that lists unresolved issues assigned to you.
  assigned_popup = {
    keymap = "<leader>ja",
    width = 0.55,
    height = 0.5,
    border = "rounded",
    max_results = 50, -- page size when listing your assigned issues
    -- Optional custom JQL for the assigned list:
    -- jql = "assignee = currentUser() AND resolution = Unresolved ORDER BY updated DESC",
  },

  -- Popup that lists issues from an arbitrary JQL query.
  search_popup = {
    keymap = "<leader>js",
    width = 0.6,
    height = 0.6,
    border = "rounded",
    max_results = 50, -- page size for search results
  },

  -- Jira API credentials; by default these are read from environment variables.
  api = {
    base_url = os.getenv("JIRA_BASE_URL") or "", -- e.g. https://your-domain.atlassian.net
    email = os.getenv("JIRA_API_EMAIL") or "",
    token = os.getenv("JIRA_API_TOKEN") or os.getenv("JIRA_API_KEY") or "",
  },
})

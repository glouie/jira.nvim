local api = require("jira.api")
local popup = require("jira.popup")

local M = {}

local default_config = {
  keymap = "<leader>ji",
  issue_pattern = "%u+-%d+",
  highlight_group = "JiraIssue",
  max_lines = 5000,
  popup = {
    width = 0.65,
    height = 0.75,
    border = "rounded",
  },
  api = {
    base_url = vim.env.JIRA_BASE_URL or "",
    email = vim.env.JIRA_API_EMAIL or "",
    token = vim.env.JIRA_API_TOKEN or vim.env.JIRA_API_KEY or "",
  },
}

local config = vim.deepcopy(default_config)
local ns = vim.api.nvim_create_namespace("jira.nvim")
local group = vim.api.nvim_create_augroup("jira.nvim", { clear = true })

local function ensure_highlight()
  local ok = pcall(vim.api.nvim_get_hl, 0, { name = config.highlight_group })
  if ok then
    return
  end
  vim.api.nvim_set_hl(0, config.highlight_group, { underline = true })
end

local function scan_line(line, col)
  local pattern = config.issue_pattern
  local start = 1
  while true do
    local s, e = line:find(pattern, start)
    if not s then
      break
    end
    if col and col >= (s - 1) and col <= (e - 1) then
      return line:sub(s, e)
    end
    start = e + 1
  end
  return nil
end

local function highlight_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end
  local max_lines = config.max_lines or -1
  local total_lines = vim.api.nvim_buf_line_count(bufnr)
  local last_line = total_lines
  if max_lines > 0 then
    last_line = math.min(total_lines, max_lines)
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, last_line, false)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  for idx, line in ipairs(lines) do
    local start = 1
    while true do
      local s, e = line:find(config.issue_pattern, start)
      if not s then
        break
      end
      vim.api.nvim_buf_add_highlight(bufnr, ns, config.highlight_group, idx - 1, s - 1, e)
      start = e + 1
    end
  end
end

local function schedule_highlight(buf)
  vim.schedule(function()
    if vim.api.nvim_buf_is_valid(buf) then
      highlight_buffer(buf)
    end
  end)
end

local function attach_autocmds()
  vim.api.nvim_clear_autocmds({ group = group })
  vim.api.nvim_create_autocmd({ "BufEnter", "TextChanged", "InsertLeave", "BufWritePost" }, {
    group = group,
    callback = function(args)
      schedule_highlight(args.buf)
    end,
  })
end

function M.get_config()
  return config
end

function M.setup(opts)
  opts = opts or {}
  config = vim.tbl_deep_extend("force", vim.deepcopy(default_config), opts)
  config.api = vim.tbl_deep_extend("force", vim.deepcopy(default_config.api), opts.api or {})
  config.popup = vim.tbl_deep_extend("force", vim.deepcopy(default_config.popup), opts.popup or {})
  ensure_highlight()
  attach_autocmds()
  if config.keymap and config.keymap ~= "" then
    vim.keymap.set("n", config.keymap, function()
      M.open_issue_under_cursor()
    end, { desc = "jira.nvim: open issue details" })
  end
  highlight_buffer(vim.api.nvim_get_current_buf())
end

function M.find_issue_under_cursor()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_get_current_line()
  return scan_line(line, cursor[2])
end

function M.open_issue(issue_key)
  if not issue_key or issue_key == "" then
    vim.notify("jira.nvim: missing issue key", vim.log.levels.WARN)
    return
  end
  api.fetch_issue(issue_key, config, function(issue, err)
    vim.schedule(function()
      if err then
        vim.notify(string.format("jira.nvim: %s", err), vim.log.levels.ERROR)
        return
      end
      popup.render(issue, config)
    end)
  end)
end

function M.open_issue_under_cursor()
  local issue = M.find_issue_under_cursor()
  if not issue then
    vim.notify("jira.nvim: cursor is not on an issue key", vim.log.levels.INFO)
    return
  end
  M.open_issue(issue)
end

function M.refresh(bufnr)
  highlight_buffer(bufnr or vim.api.nvim_get_current_buf())
end

return M

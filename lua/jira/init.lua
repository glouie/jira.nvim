local api = require("jira.api")
local popup = require("jira.popup")

local M = {}

local default_config = {
  keymap = "<leader>ji",
  issue_pattern = "%u+-%d+",
  highlight_group = "JiraIssue",
  max_lines = -1,
  ignored_projects = { "SEV" },
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
local navigation_state
local move_navigation
local function rebuild_ignored_project_map()
  local map = {}
  for _, project in ipairs(config.ignored_projects or {}) do
    if type(project) == "string" and project ~= "" then
      map[project:upper()] = true
    end
  end
  config._ignored_project_map = map
end

rebuild_ignored_project_map()

local function should_ignore_issue_key(issue_key)
  if not issue_key or issue_key == "" then
    return false
  end
  local project = issue_key:match("^([%a%d]+)%-%d+$")
  if not project then
    return false
  end
  local map = config._ignored_project_map
  if not map then
    return false
  end
  return map[project:upper()] == true
end

local function collect_buffer_issues(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return {}
  end
  local pattern = config.issue_pattern or default_config.issue_pattern
  if not pattern or pattern == "" then
    return {}
  end
  local issues = {}
  local seen = {}
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for _, line in ipairs(lines) do
    local start = 1
    while true do
      local s, e = line:find(pattern, start)
      if not s then
        break
      end
      local key = line:sub(s, e)
      if key ~= "" and not seen[key] and not should_ignore_issue_key(key) then
        seen[key] = true
        table.insert(issues, { key = key })
      end
      start = e + 1
    end
  end
  return issues
end

local function issue_index(issues, issue_key)
  if not issues or not issue_key or issue_key == "" then
    return nil
  end
  for idx, item in ipairs(issues) do
    if item.key == issue_key then
      return idx
    end
  end
  return nil
end

local function update_navigation_from_buffer(bufnr, issue_key)
  local issues = collect_buffer_issues(bufnr)
  if issue_key and issue_key ~= "" then
    local idx = issue_index(issues, issue_key)
    if not idx then
      table.insert(issues, { key = issue_key })
      idx = #issues
    end
    navigation_state = {
      bufnr = bufnr,
      issues = issues,
      index = idx,
    }
  elseif #issues > 0 then
    navigation_state = {
      bufnr = bufnr,
      issues = issues,
      index = 1,
    }
  else
    navigation_state = nil
  end
  return navigation_state
end

local function navigation_payload()
  local nav = navigation_state
  if not nav or not nav.issues or not nav.index then
    return nil
  end
  local total = #nav.issues
  if total == 0 then
    return nil
  end
  if nav.index < 1 then
    nav.index = 1
  elseif nav.index > total then
    nav.index = total
  end
  local payload = {
    total = total,
    index = nav.index,
  }
  if nav.index > 1 then
    payload.has_prev = true
    payload.goto_prev = function()
      move_navigation(-1)
    end
  end
  if nav.index < total then
    payload.has_next = true
    payload.goto_next = function()
      move_navigation(1)
    end
  end
  return payload
end

move_navigation = function(delta)
  local nav = navigation_state
  if not nav or not nav.issues then
    return
  end
  local total = #nav.issues
  if total == 0 then
    return
  end
  local target = (nav.index or 1) + delta
  if target < 1 or target > total then
    return
  end
  nav.index = target
  local entry = nav.issues[target]
  if not entry or not entry.key or entry.key == "" then
    return
  end
  M.open_issue(entry.key, { navigation = nav })
end

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
    local key = line:sub(s, e)
    if not should_ignore_issue_key(key) and col and col >= (s - 1) and col <= (e - 1) then
      return key
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
      local key = line:sub(s, e)
      if not should_ignore_issue_key(key) then
        vim.api.nvim_buf_add_highlight(bufnr, ns, config.highlight_group, idx - 1, s - 1, e)
      end
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
  rebuild_ignored_project_map()
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

function M.open_issue(issue_key, opts)
  if not issue_key or issue_key == "" then
    vim.notify("jira.nvim: missing issue key", vim.log.levels.WARN)
    return
  end
  opts = opts or {}
  if opts.navigation ~= nil then
    navigation_state = opts.navigation
  else
    navigation_state = nil
  end
  api.fetch_issue(issue_key, config, function(issue, err)
    vim.schedule(function()
      if err then
        vim.notify(string.format("jira.nvim: %s", err), vim.log.levels.ERROR)
        return
      end
      local nav_context = nil
      if navigation_state then
        local idx = issue_index(navigation_state.issues, issue.key)
        if idx then
          navigation_state.index = idx
        end
        nav_context = navigation_payload()
      end
      popup.render(issue, config, { navigation = nav_context })
    end)
  end)
end

function M.open_issue_under_cursor()
  local issue = M.find_issue_under_cursor()
  if not issue then
    vim.notify("jira.nvim: cursor is not on an issue key", vim.log.levels.INFO)
    return
  end
  local bufnr = vim.api.nvim_get_current_buf()
  local nav = update_navigation_from_buffer(bufnr, issue)
  M.open_issue(issue, { navigation = nav })
end

function M.refresh(bufnr)
  highlight_buffer(bufnr or vim.api.nvim_get_current_buf())
end

return M

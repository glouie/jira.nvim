---Core entrypoint for jira.nvim.
-- Handles configuration, keymaps, highlighting, navigation, and popup orchestration.

local api = require("jira.api")
local popup = require("jira.popup")
local utils = require("jira.utils")
local jql_prompt = require("jira.jql_prompt")

local M = {}

---Deep copy a Lua value without relying on vim.deepcopy on older versions.
---@param value any Value to clone.
---@param seen table|nil Tracking table for circular references.
---@return any clone Copied value.
local function deepcopy(value, seen)
  if vim.deepcopy then
    return vim.deepcopy(value)
  end
  if type(value) ~= "table" then
    return value
  end
  if seen and seen[value] then
    return seen[value]
  end
  local shadow = {}
  seen = seen or {}
  seen[value] = shadow
  for k, v in pairs(value) do
    shadow[deepcopy(k, seen)] = deepcopy(v, seen)
  end
  return shadow
end

---Check whether a highlight group exists.
---@param name string Highlight group name.
---@return boolean exists True if the highlight group is defined.
local function highlight_exists(name)
  if vim.api.nvim_get_hl then
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name })
    return ok and type(hl) == "table" and next(hl) ~= nil
  end
  if not vim.api.nvim_get_hl_by_name then
    return false
  end
  local ok, hl = pcall(vim.api.nvim_get_hl_by_name, name, true)
  return ok and type(hl) == "table" and next(hl) ~= nil
end

---Collapse a potentially multi-line JQL string into a trimmed single line.
---@param jql string|nil Raw JQL text.
---@return string collapsed Single-line trimmed JQL.
local function collapse_jql_single_line(jql)
  if not jql or jql == "" then
    return ""
  end
  local collapsed = tostring(jql):gsub("[%s\r\n]+", " ")
  return utils.trim(collapsed)
end

local default_config = {
  keymap = "<leader>ji",
  issue_pattern = "%u+-%d+",
  highlight_group = "JiraIssue",
  max_lines = -1,
  ignored_projects = { "SEV" },
  assigned_popup = {
    keymap = "<leader>ja",
    width = 0.55,
    height = 0.5,
    border = "rounded",
    max_results = 50,
  },
  search_popup = {
    keymap = "<leader>js",
    width = 0.6,
    height = 0.6,
    border = "rounded",
    max_results = 50,
    history_size = 50,
  },
  history_popup = {
    keymap = "<leader>jh",
    width = 0.55,
    height = 0.5,
    border = "rounded",
    history_size = 200,
  },
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

local config = deepcopy(default_config)
local ns = vim.api.nvim_create_namespace("jira.nvim")
local group = vim.api.nvim_create_augroup("jira.nvim", { clear = true })
local navigation_state
local move_navigation
local last_jql_query
local search_history = {}
local issue_history = {}

---Join filesystem path segments with a forward slash fallback.
---@param ... string Path segments.
---@return string path Joined path.
local function join_path(...)
  local parts = { ... }
  if vim.fs and vim.fs.joinpath then
    local unpack_fn = table.unpack or unpack
    return vim.fs.joinpath(unpack_fn(parts))
  end
  local path = ""
  for _, part in ipairs(parts) do
    if part and part ~= "" then
      if path ~= "" and not path:match("/$") then
        path = path .. "/"
      end
      path = path .. part
    end
  end
  return path
end

---Resolve the on-disk path used to store JQL history.
---@return string|nil path Absolute file path or nil when stdpath is unavailable.
local function history_store_path()
  local ok, data_dir = pcall(vim.fn.stdpath, "data")
  if not ok or not data_dir or data_dir == "" then
    return nil
  end
  return join_path(data_dir, "jira.nvim", "search_history.json")
end

---Resolve the on-disk path used to store opened issue history.
---@return string|nil path Absolute file path or nil when stdpath is unavailable.
local function issue_history_store_path()
  local ok, data_dir = pcall(vim.fn.stdpath, "data")
  if not ok or not data_dir or data_dir == "" then
    return nil
  end
  return join_path(data_dir, "jira.nvim", "issue_history.json")
end

---Return the configured history size limit for the JQL prompt.
---@return integer limit Maximum number of entries to keep.
local function history_limit()
  local limit = default_config.search_popup.history_size or 0
  local configured = config.search_popup and config.search_popup.history_size
  if configured ~= nil then
    limit = configured
  end
  limit = tonumber(limit) or 0
  if limit < 0 then
    limit = 0
  end
  return math.floor(limit)
end

---Return the configured history size limit for opened issues.
---@return integer limit Maximum number of entries to keep.
local function issue_history_limit()
  local limit = default_config.history_popup.history_size or 0
  local configured = config.history_popup and config.history_popup.history_size
  if configured ~= nil then
    limit = configured
  end
  limit = tonumber(limit) or 0
  if limit < 0 then
    limit = 0
  end
  return math.floor(limit)
end

---Persist the current search history to disk.
---@return nil
local function save_search_history()
  local limit = history_limit()
  if limit <= 0 then
    return
  end
  local path = history_store_path()
  if not path then
    return
  end
  local dir = path:match("^(.*)/[^/]+$")
  if dir and dir ~= "" then
    pcall(vim.fn.mkdir, dir, "p")
  end
  local ok_encode, payload = pcall(utils.json_encode, search_history)
  if not ok_encode or not payload then
    return
  end
  local file = io.open(path, "w")
  if not file then
    return
  end
  file:write(payload)
  file:close()
end

---Persist the current issue history to disk.
---@return nil
local function save_issue_history()
  local limit = issue_history_limit()
  if limit <= 0 then
    return
  end
  local path = issue_history_store_path()
  if not path then
    return
  end
  local dir = path:match("^(.*)/[^/]+$")
  if dir and dir ~= "" then
    pcall(vim.fn.mkdir, dir, "p")
  end
  local ok_encode, payload = pcall(utils.json_encode, issue_history)
  if not ok_encode or not payload then
    return
  end
  local file = io.open(path, "w")
  if not file then
    return
  end
  file:write(payload)
  file:close()
end

---Trim stored JQL history to the configured limit.
---@param opts table|nil Additional options.
---@return nil
local function trim_search_history(opts)
  local limit = history_limit()
  if limit <= 0 then
    search_history = {}
    if opts and opts.persist then
      save_search_history()
    end
    return
  end
  while #search_history > limit do
    table.remove(search_history, 1)
  end
  if opts and opts.persist then
    save_search_history()
  end
end

---Trim stored opened-issue history to the configured limit.
---@param opts table|nil Additional options.
---@return nil
local function trim_issue_history(opts)
  local limit = issue_history_limit()
  if limit <= 0 then
    issue_history = {}
    if opts and opts.persist then
      save_issue_history()
    end
    return
  end
  while #issue_history > limit do
    table.remove(issue_history, 1)
  end
  if opts and opts.persist then
    save_issue_history()
  end
end

---Insert a search history entry, ensuring the most recent copy is kept.
---@param value string Cleaned JQL string.
---@return nil
local function push_search_history(value)
  if value == "" then
    return
  end
  for idx = #search_history, 1, -1 do
    if search_history[idx] == value then
      table.remove(search_history, idx)
    end
  end
  table.insert(search_history, value)
end

---Insert an issue history entry, ensuring the most recent copy is kept.
---@param entry table Issue data containing `key` and optional `summary`.
---@return nil
local function push_issue_history(entry)
  if not entry or not entry.key or entry.key == "" then
    return
  end
  for idx = #issue_history, 1, -1 do
    if issue_history[idx] and issue_history[idx].key == entry.key then
      table.remove(issue_history, idx)
    end
  end
  entry.summary = utils.trim(entry.summary or "")
  table.insert(issue_history, entry)
end

---Load saved JQL history from disk.
---@return nil
local function load_search_history()
  search_history = {}
  local path = history_store_path()
  if not path then
    return
  end
  local file = io.open(path, "r")
  if not file then
    return
  end
  local ok_read, contents = pcall(file.read, file, "*a")
  file:close()
  if not ok_read or not contents or contents == "" then
    return
  end
  local decoded = utils.json_decode(contents)
  if type(decoded) ~= "table" then
    return
  end
  for _, entry in ipairs(decoded) do
    if type(entry) == "string" then
      local cleaned = utils.trim(entry)
      if cleaned ~= "" then
        push_search_history(cleaned)
      end
    end
  end
  trim_search_history({ persist = true })
end

---Load saved issue history from disk.
---@return nil
local function load_issue_history()
  issue_history = {}
  local path = issue_history_store_path()
  if not path then
    return
  end
  local file = io.open(path, "r")
  if not file then
    return
  end
  local ok_read, contents = pcall(file.read, file, "*a")
  file:close()
  if not ok_read or not contents or contents == "" then
    return
  end
  local decoded = utils.json_decode(contents)
  if type(decoded) ~= "table" then
    return
  end
  for _, entry in ipairs(decoded) do
    if type(entry) == "table" and type(entry.key) == "string" then
      push_issue_history({
        key = entry.key,
        summary = utils.trim(entry.summary or ""),
      })
    elseif type(entry) == "string" then
      push_issue_history({ key = entry, summary = "" })
    end
  end
  trim_issue_history({ persist = true })
end

---Record a submitted JQL query in the history ring.
---@param query string|nil JQL text to store.
---@return nil
local function record_search_history(query)
  local cleaned = utils.trim(query or "")
  if cleaned == "" then
    return
  end
  push_search_history(cleaned)
  trim_search_history({ persist = true })
end

---Record a successfully opened issue in the history store.
---@param issue table|nil Jira issue payload containing `key` and fields.
---@return nil
local function record_issue_history(issue)
  if not issue or not issue.key or issue.key == "" then
    return
  end
  local summary = ""
  local fields = issue.fields
  if type(fields) == "table" then
    summary = utils.trim(fields.summary or fields.title or "")
  end
  push_issue_history({
    key = issue.key,
    summary = summary,
  })
  trim_issue_history({ persist = true })
end

---Rebuild a lookup map for ignored project keys from config.
---@return nil
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

---Determine whether an issue key should be ignored based on configuration.
---@param issue_key string|nil Issue key such as "ABC-123".
---@return boolean ignore True when the issue belongs to an ignored project.
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

---Collect all Jira issue keys present in a buffer.
---@param bufnr number Buffer handle.
---@return table issues List of tables containing `key` fields.
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

---Find the index of a specific issue key in a list of issues.
---@param issues table List of issue entries with `key`.
---@param issue_key string Issue key to find.
---@return integer|nil index Position in the list or nil.
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

---Build navigation state from a buffer and optional active issue.
---@param bufnr number Buffer handle.
---@param issue_key string|nil Issue key to anchor navigation.
---@return table|nil nav Navigation state or nil when no issues found.
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

---Create a navigation payload describing previous/next issue availability.
---@return table|nil nav Navigation helpers for the popup, or nil when not available.
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

---Move the issue navigation pointer and open the target issue.
---@param delta integer Direction to move (+1 next, -1 previous).
---@return nil
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

---Ensure the configured highlight group exists, creating a default style if missing.
---@return nil
local function ensure_highlight()
  local ok = pcall(vim.api.nvim_get_hl, 0, { name = config.highlight_group })
  if ok then
    return
  end
  if highlight_exists(config.highlight_group) then
    return
  end
  vim.api.nvim_set_hl(0, config.highlight_group, { underline = true })
end

---Find an issue key on a line that covers the given column.
---@param line string Line text.
---@param col number 0-based column index.
---@return string|nil issue_key Issue under the cursor or nil.
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

---Apply highlights for issue keys in a buffer.
---@param bufnr number Buffer handle.
---@return nil
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

---Schedule highlighting work on the main loop.
---@param buf number Buffer handle.
---@return nil
local function schedule_highlight(buf)
  vim.schedule(function()
    if vim.api.nvim_buf_is_valid(buf) then
      highlight_buffer(buf)
    end
  end)
end

---Create autocmds that keep issue highlighting up to date.
---@return nil
local function attach_autocmds()
  vim.api.nvim_clear_autocmds({ group = group })
  vim.api.nvim_create_autocmd({ "BufEnter", "TextChanged", "InsertLeave", "BufWritePost" }, {
    group = group,
    callback = function(args)
      schedule_highlight(args.buf)
    end,
  })
end

---Return the current effective configuration table.
---@return table config Merged user and default configuration.
function M.get_config()
  return config
end

---Configure jira.nvim, set keymaps, and attach highlighting autocmds.
---@param opts table|nil User configuration overrides.
---@return nil
function M.setup(opts)
  opts = opts or {}
  config = vim.tbl_deep_extend("force", deepcopy(default_config), opts)
  config.api = vim.tbl_deep_extend("force", deepcopy(default_config.api), opts.api or {})
  config.popup = vim.tbl_deep_extend("force", deepcopy(default_config.popup), opts.popup or {})
  config.assigned_popup = vim.tbl_deep_extend("force", deepcopy(default_config.assigned_popup), opts.assigned_popup or {})
  config.search_popup = vim.tbl_deep_extend("force", deepcopy(default_config.search_popup), opts.search_popup or {})
  config.history_popup = vim.tbl_deep_extend("force", deepcopy(default_config.history_popup), opts.history_popup or {})
  load_search_history()
  load_issue_history()
  trim_search_history({ persist = true })
  trim_issue_history({ persist = true })
  rebuild_ignored_project_map()
  ensure_highlight()
  attach_autocmds()
  if config.keymap and config.keymap ~= "" then
    vim.keymap.set("n", config.keymap, function()
      M.open_issue_under_cursor()
    end, { desc = "jira.nvim: open issue details" })
  end
  local assigned_keymap = config.assigned_popup and config.assigned_popup.keymap
  if assigned_keymap and assigned_keymap ~= "" then
    vim.keymap.set("n", assigned_keymap, function()
      M.open_assigned_issues()
    end, { desc = "jira.nvim: list assigned issues" })
  end
  local search_keymap = config.search_popup and config.search_popup.keymap
  if search_keymap and search_keymap ~= "" then
    vim.keymap.set("n", search_keymap, function()
      M.open_jql_search()
    end, { desc = "jira.nvim: search Jira via JQL" })
  end
  local history_keymap = config.history_popup and config.history_popup.keymap
  if history_keymap and history_keymap ~= "" then
    vim.keymap.set("n", history_keymap, function()
      M.open_issue_history()
    end, { desc = "jira.nvim: open viewed issue history" })
  end
  highlight_buffer(vim.api.nvim_get_current_buf())
end

---Find an issue key under the current cursor position.
---@return string|nil issue_key Matching issue key or nil when none is found.
function M.find_issue_under_cursor()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_get_current_line()
  return scan_line(line, cursor[2])
end

---Open a popup for the given issue key.
---@param issue_key string Issue key such as "ABC-123".
---@param opts table|nil Options like navigation context and whether to return focus.
---@return nil
function M.open_issue(issue_key, opts)
  if not issue_key or issue_key == "" then
    vim.notify("jira.nvim: missing issue key", vim.log.levels.WARN)
    return
  end
  opts = opts or {}
  local return_focus = opts.return_focus
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
      record_issue_history(issue)
      local nav_context = nil
      if navigation_state then
        local idx = issue_index(navigation_state.issues, issue.key)
        if idx then
          navigation_state.index = idx
        end
        nav_context = navigation_payload()
      end
      popup.render(issue, config, { navigation = nav_context, return_focus = return_focus })
    end)
  end)
end

---Open the issue popup for the key located under the cursor.
---@return nil
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

---Re-run highlighting for Jira issue keys in the target buffer.
---@param bufnr number|nil Buffer handle; defaults to current buffer.
---@return nil
function M.refresh(bufnr)
  highlight_buffer(bufnr or vim.api.nvim_get_current_buf())
end

---Open an issue from a list selection, preserving focus where possible.
---@param issue table|nil Issue entry with `key`.
---@param ctx table|nil Context containing originating window.
---@return nil
local function open_issue_from_list(issue, ctx)
  if not issue or not issue.key then
    return
  end
  local win = ctx and ctx.win
  if win and vim.api.nvim_win_is_valid(win) then
    M.open_issue(issue.key, { return_focus = win })
  else
    M.open_issue(issue.key)
  end
end

---Render the assigned issues popup page for a given offset.
---@param start_at number Starting index for pagination.
---@return nil
local function render_assigned_page(start_at)
  api.fetch_assigned_issues(config, { start_at = start_at }, function(result, err)
    vim.schedule(function()
      if err then
        vim.notify(string.format("jira.nvim: %s", err), vim.log.levels.ERROR)
        return
      end
      result = result or {}
      local issues = result.issues or {}
      local page_size = math.max(1, tonumber(result.max_results) or config.assigned_popup.max_results or 50)
      local start_idx = math.max(0, tonumber(result.start_at) or start_at or 0)
      local total = tonumber(result.total)
      if not total or total <= 0 then
        total = start_idx + #issues
      end
      local pagination = {
        total = total,
        start_at = start_idx,
        page_size = page_size,
      }
      local has_prev = start_idx > 0
      local has_next = (#issues == page_size) and ((not result.total) or (start_idx + #issues < result.total))
      local handlers = {}
      if has_next then
        handlers.next_page = function()
          render_assigned_page(start_idx + page_size)
        end
      end
      if has_prev then
        handlers.prev_page = function()
          render_assigned_page(math.max(0, start_idx - page_size))
        end
      end
      popup.render_issue_list(issues, config, {
        title = "Assigned Issues",
        empty_message = "No unresolved issues assigned to you.",
        pagination = pagination,
        pagination_handlers = handlers,
        on_select = open_issue_from_list,
      })
    end)
  end)
end

---Render a JQL search popup for the specified query and page options.
---@param jql string JQL query string.
---@param opts table|nil Pagination state and next page tokens.
---@return nil
local function render_jql_page(jql, opts)
  opts = opts or {}
  local page_state = opts.page_state or { tokens = { [1] = opts.next_page_token } }
  local page_number = opts.page or 1
  local page_tokens = page_state.tokens or {}
  local active_token = page_tokens[page_number]
  api.search_issues(config, {
    jql = jql,
    max_results = config.search_popup and config.search_popup.max_results,
    next_page_token = active_token,
  }, function(result, err)
    vim.schedule(function()
      if err then
        vim.notify(string.format("jira.nvim: %s", err), vim.log.levels.ERROR)
        return
      end
      result = result or {}
      local issues = result.issues or {}
      local page_size = math.max(1, tonumber(result.max_results) or (config.search_popup and config.search_popup.max_results) or 50)
      local start_idx = tonumber(result.start_at)
      if not start_idx then
        start_idx = (page_number - 1) * page_size
      else
        start_idx = math.max(0, start_idx)
      end
      local total = tonumber(result.total)
      if not total or total <= 0 then
        total = start_idx + #issues
      end
      local total_pages
      if page_size > 0 and total > 0 then
        total_pages = math.floor((total + page_size - 1) / page_size)
      end
      local pagination = {
        total = total,
        start_at = start_idx,
        page_size = page_size,
        page = page_number,
        total_pages = total_pages or page_number,
      }
      local handlers = {}
      local next_token = result.next_page_token
      if next_token and next_token ~= "" then
        handlers.next_page = function()
          page_state.tokens = page_state.tokens or {}
          page_state.tokens[page_number + 1] = next_token
          render_jql_page(jql, {
            page = page_number + 1,
            page_state = page_state,
          })
        end
      end
      if page_number > 1 then
        handlers.prev_page = function()
          render_jql_page(jql, {
            page = page_number - 1,
            page_state = page_state,
          })
        end
      end
      popup.render_issue_list(issues, config, {
        title = "JQL Search",
        empty_message = string.format("No issues match JQL: %s", collapse_jql_single_line(jql)),
        pagination = pagination,
        pagination_handlers = handlers,
        layout = config.search_popup,
        on_select = open_issue_from_list,
        source = "jql",
      })
    end)
  end)
end

---Open a popup showing unresolved issues assigned to the current user.
---@return nil
function M.open_assigned_issues()
  render_assigned_page(0)
end

---Open an interactive JQL prompt and render results in a popup.
---@return nil
function M.open_jql_search()
  local default_query = last_jql_query or ""
  local help = "Example: project = ABC AND status in ('In Progress', 'To Do') ORDER BY updated DESC"
  local function submit(input)
    local query = utils.trim(input or "")
    if query == "" then
      return
    end
    last_jql_query = input or query
    record_search_history(input or query)
    render_jql_page(query)
  end
  local history_snapshot = deepcopy(search_history)
  local ok = jql_prompt.open({
    default = default_query,
    help = help,
    config = config,
    history = history_snapshot,
    on_submit = submit,
    on_change = function(value)
      if value ~= nil then
        last_jql_query = value
      end
    end,
    on_close = function(value)
      if value ~= nil then
        last_jql_query = value
      end
    end,
  })
  if not ok then
    if vim.ui and vim.ui.input then
      vim.ui.input({ prompt = "JQL query: ", default = default_query }, submit)
    else
      local ok_input, value = pcall(vim.fn.input, "JQL query: ", default_query)
      if ok_input then
        submit(value)
      end
    end
  end
end

---Open a popup listing previously viewed issues from history.
---@return nil
function M.open_issue_history()
  local issues = {}
  for idx = #issue_history, 1, -1 do
    table.insert(issues, issue_history[idx])
  end
  popup.render_issue_list(issues, config, {
    title = "Viewed Issues",
    subtitle = string.format("%d unique issues", #issues),
    empty_message = "No issues viewed yet.",
    layout = config.history_popup,
    on_select = open_issue_from_list,
  })
end

return M

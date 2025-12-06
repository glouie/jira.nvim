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
  debug = false,
  issue_pattern = "%u+-%d+",
  highlight_group = "JiraIssue",
  max_lines = -1,
  ignored_projects = { "SEV" },
  statusline = {
    enabled = true,
    output = "message",
    max_length = 80,
    loading_text = "Loading...",
    error_text = "Unable to load issue",
    empty_text = "No summary",
    message_highlight = nil,
  },
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
  buffer_popup = {
    keymap = "<leader>jb",
    width = 0.55,
    height = 0.5,
    border = "rounded",
    close_on_select = true,
  },
  popup = {
    width = 0.65,
    height = 0.75,
    border = "rounded",
    details_fields = {
      "key",
      "status",
      "resolution",
      "priority",
      "severity",
      "assignee",
      "reporter",
      "created",
      "updated",
      "due",
      "fix_versions",
      "affects_versions",
      "open_duration",
      "comments",
      "changes",
      "assignees",
      "labels",
    },
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
local debug_state = {
  hover_issue = nil,
}

---Emit debug logs when enabled to help trace cursor behaviour.
---@param message string Text to log.
---@return nil
local function debug_log(message)
  if not config.debug then
    return
  end
  pcall(vim.notify, string.format("jira.nvim debug: %s", message), vim.log.levels.DEBUG)
end

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

---Check whether lualine is available (loaded or loadable).
---@return boolean available True when lualine can be required.
local function lualine_available()
  if package.loaded["lualine"] then
    return true
  end
  local ok = pcall(require, "lualine")
  return ok
end

local statusline_state = {
  cache = {},
  pending = {},
  current_key = nil,
  message = "",
  applied = false,
  original = nil,
  template = nil,
}

---Build the jira.nvim-owned statusline layout string.
---@return string template Statusline format string.
local function build_statusline_template()
  return table.concat({
    "%<%f %h%m%r ",
    "%-14.(%l,%c%V%) %P",
    "%=",
    "%{v:lua.require'jira'.statusline_message()}",
    "%=",
    "%{mode()}",
  })
end

---Determine how hover feedback should be displayed.
---@return string mode Either "statusline", "lualine", or "message".
local function statusline_output_mode()
  local cfg = config.statusline
  local mode = cfg and cfg.output
  if type(mode) == "string" then
    local lowered = mode:lower():gsub("[_%s-]+", "")
    if lowered == "message" then
      return "message"
    end
    if lowered == "lualine" then
      return "lualine"
    end
  end
  return "statusline"
end

---Check whether hover-driven statusline updates should run.
---@return boolean enabled True when statusline text should be refreshed.
local function statusline_updates_enabled()
  return config.statusline ~= false
end

---Check whether jira.nvim should apply its built-in statusline template.
---@return boolean enabled True when the plugin owns the statusline layout.
local function statusline_template_enabled()
  local cfg = config.statusline
  return statusline_updates_enabled()
    and statusline_output_mode() == "statusline"
    and not (cfg and cfg.enabled == false)
end

---Resolve a statusline configuration value with a fallback to defaults.
---@param key string Config field name.
---@return any value Effective value for the requested option.
local function statusline_config_value(key)
  local cfg = config.statusline or {}
  if cfg[key] ~= nil then
    return cfg[key]
  end
  local defaults = default_config.statusline or {}
  return defaults[key]
end

---Clamp and sanitize the maximum summary length shown in the statusline.
---@return integer limit Non-negative character limit (0 means no limit).
local function statusline_max_length()
  local max_len = tonumber(statusline_config_value("max_length")) or 0
  if max_len < 0 then
    max_len = 0
  end
  return math.floor(max_len)
end

---Calculate how much horizontal space the summary may occupy.
---@param reserved_width integer|nil Width already consumed by fixed text.
---@return integer limit Maximum allowed width for the summary before truncation.
local function statusline_summary_limit(reserved_width)
  local columns = tonumber(vim.o.columns) or 0
  local taken = math.max(0, tonumber(reserved_width) or 0)
  local available = math.max(0, columns - taken)
  if available > 0 then
    return available
  end
  return statusline_max_length()
end

---Escape percent characters for safe statusline interpolation.
---@param text string|nil Raw text.
---@return string escaped Escaped text suitable for statusline.
local function escape_statusline_component(text)
  return (text or ""):gsub("%%", "%%%%")
end

---Expose the raw hover text for reuse in statusline/lualine components.
---@return string message Unescaped hover text.
local function statusline_message_text()
  return statusline_state.message or ""
end

---Refresh lualine without touching vim.o.statusline to avoid flicker.
---@return boolean refreshed True when lualine refresh ran.
local function refresh_lualine_statusline()
  if not package.loaded["lualine"] then
    return false
  end
  local ok, lualine = pcall(require, "lualine")
  if not ok or type(lualine) ~= "table" then
    return false
  end
  local refresh = lualine.refresh
  if type(refresh) ~= "function" then
    return false
  end
  refresh({ place = { "statusline" }, trigger = "jira.nvim" })
  return true
end

---Post hover text to the command area instead of the statusline.
---@param message string Hover text to display.
---@return nil
local function echo_hover_message(message)
  local cleaned = utils.trim(message or "")
  local highlight = statusline_config_value("message_highlight")
  if highlight and not highlight_exists(highlight) then
    highlight = nil
  end
  if cleaned == "" then
    pcall(vim.api.nvim_echo, {}, false, {})
    return
  end
  pcall(vim.api.nvim_echo, { { cleaned, highlight } }, false, {})
end

---Apply the custom statusline layout if requested.
---@return nil
local function apply_statusline_template()
  if not statusline_template_enabled() then
    return
  end
  if not statusline_state.original then
    statusline_state.original = vim.o.statusline
  end
  local template = build_statusline_template()
  statusline_state.template = template
  if vim.o.statusline ~= template then
    vim.o.statusline = template
  end
  statusline_state.applied = true
end

---Read a cached summary from viewed issue history.
---@param issue_key string Issue key to look up.
---@return string|nil summary Previously seen summary if present.
local function statusline_summary_from_history(issue_key)
  if not issue_key or issue_key == "" then
    return nil
  end
  for idx = #issue_history, 1, -1 do
    local entry = issue_history[idx]
    if entry and entry.key == issue_key and entry.summary and entry.summary ~= "" then
      return entry.summary
    end
  end
  return nil
end

---Format a summary for statusline display, applying truncation.
---@param summary string|nil Raw summary text.
---@param max_width integer|nil Maximum width available for the summary.
---@return string formatted Trimmed and truncated summary.
local function format_statusline_summary(summary, max_width)
  local text = utils.trim(summary or "")
  local limit = tonumber(max_width) or 0
  if limit <= 0 then
    limit = statusline_max_length()
  end
  if limit <= 0 then
    return text
  end
  local width = vim.api.nvim_strwidth(text)
  if width <= limit then
    return text
  end
  local suffix = "..."
  local suffix_width = vim.api.nvim_strwidth(suffix)
  if limit <= suffix_width then
    return suffix:sub(1, limit)
  end
  local target = limit - suffix_width
  local shortened = text
  while vim.api.nvim_strwidth(shortened) > target and vim.fn.strchars(shortened) > 0 do
    shortened = vim.fn.strcharpart(shortened, 0, vim.fn.strchars(shortened) - 1)
  end
  return shortened .. suffix
end

---Build the statusline text for a given issue key and summary.
---@param issue_key string Issue key such as "ABC-123".
---@param summary string|table|nil Issue summary text or detail table.
---@return string text Composed statusline snippet.
local function format_statusline_text(issue_key, summary)
  if not issue_key or issue_key == "" then
    return ""
  end
  local details = {}
  if type(summary) == "table" then
    details = summary
  elseif summary ~= nil then
    details.summary = summary
  end

  local status = utils.trim(details.status or "")
  local resolution = utils.trim(details.resolution or "")
  local assignee = utils.trim(details.assignee or "")
  local reporter = utils.trim(details.reporter or "")

  local status_label = status ~= "" and status or "Unknown"
  local resolution_label = resolution ~= "" and resolution or "Unresolved"
  local assignee_label = assignee ~= "" and assignee or "Unassigned"
  local reporter_label = reporter ~= "" and reporter or "Unknown"

  local prefix = string.format("JIRA: [%s] ", issue_key)
  local suffix = string.format(" [%s][%s] assignee: %s reporter: %s", status_label, resolution_label, assignee_label, reporter_label)

  local reserved_width = vim.api.nvim_strwidth(prefix .. suffix)

  local clean_summary = utils.trim(details.summary or "")
  if clean_summary == "" then
    clean_summary = utils.trim(statusline_config_value("empty_text") or "")
  end

  clean_summary = format_statusline_summary(clean_summary, statusline_summary_limit(reserved_width))

  return string.format(
    "%s%s%s",
    prefix,
    clean_summary,
    suffix
  )
end

---Update the active statusline message and refresh the UI when needed.
---@param message string|nil New statusline content.
---@return nil
local function set_statusline_message(message)
  local cleaned = utils.trim(message or "")
  local mode = statusline_output_mode()
  local unchanged = statusline_state.message == cleaned
  statusline_state.message = cleaned
  if not statusline_updates_enabled() then
    return
  end
  if mode == "message" then
    echo_hover_message(cleaned)
    return
  end
  if mode == "lualine" then
    if unchanged then
      return
    end
    if not refresh_lualine_statusline() then
      pcall(vim.cmd, "redrawstatus")
    end
    return
  end

  local template_needed = statusline_template_enabled()
    and (not statusline_state.applied or not statusline_state.template or vim.o.statusline ~= statusline_state.template)

  if template_needed then
    apply_statusline_template()
  end

  if unchanged and not template_needed then
    return
  end

  pcall(vim.cmd, "redrawstatus")
end

---Clear the active hover statusline state.
---@return nil
local function clear_statusline_message()
  statusline_state.current_key = nil
  debug_state.hover_issue = nil
  set_statusline_message("")
end

---Expose the statusline message for use in statusline templates.
---@return string message Escaped statusline content.
function M.statusline_message()
  return escape_statusline_component(statusline_message_text())
end

---Expose the hover message for consumption by lualine components.
---@return string message Raw hover text without statusline escaping.
function M.lualine_component()
  local ok, message = pcall(statusline_message_text)
  if not ok or message == nil then
    return "jira.nvim lualine error"
  end
  return message or ""
end

---Refresh the hover-driven statusline message for the current cursor position.
---@param opts table|nil Behaviour flags such as `fetch`.
---@return nil
local function update_hover_statusline(opts)
  if not statusline_updates_enabled() then
    return
  end
  opts = opts or {}
  local issue_key = M.find_issue_under_cursor()
  if not issue_key or should_ignore_issue_key(issue_key) then
    return
  end

  if issue_key ~= debug_state.hover_issue then
    debug_log(string.format("cursor on issue %s%s", issue_key, opts.fetch and " (fetching)" or ""))
    debug_state.hover_issue = issue_key
  end

  statusline_state.current_key = issue_key

  local cached = statusline_state.cache[issue_key]
  local cached_complete = type(cached) == "table" and cached._complete
  if cached then
    set_statusline_message(format_statusline_text(issue_key, cached))
    if cached_complete or not opts.fetch then
      return
    end
  end

  if statusline_state.pending[issue_key] then
    local loading_details = cached or { summary = statusline_config_value("loading_text") or "" }
    set_statusline_message(format_statusline_text(issue_key, loading_details))
    return
  end

  local history_summary = statusline_summary_from_history(issue_key)
  if history_summary and history_summary ~= "" and not cached then
    cached = { summary = utils.trim(history_summary), _complete = false }
    statusline_state.cache[issue_key] = cached
    set_statusline_message(format_statusline_text(issue_key, cached))
    if not opts.fetch then
      return
    end
  end

  if not opts.fetch then
    set_statusline_message(issue_key)
    return
  end

  statusline_state.pending[issue_key] = true
  set_statusline_message(format_statusline_text(issue_key, { summary = statusline_config_value("loading_text") or "" }))

  api.fetch_issue_summary(issue_key, config, function(issue, err)
    vim.schedule(function()
      statusline_state.pending[issue_key] = nil
      if err then
        if statusline_state.current_key == issue_key then
          set_statusline_message(format_statusline_text(issue_key, statusline_config_value("error_text")))
        end
        return
      end
      statusline_state.cache[issue_key] = {
        summary = utils.trim(issue and issue.summary or ""),
        status = issue and issue.status or "",
        resolution = issue and issue.resolution or "",
        assignee = issue and issue.assignee or "",
        reporter = issue and issue.reporter or "",
        _complete = true,
      }
      if statusline_state.current_key == issue_key then
        set_statusline_message(format_statusline_text(issue_key, statusline_state.cache[issue_key]))
      end
    end)
  end)
end

---Collect all Jira issue keys present in a buffer.
---@param bufnr number Buffer handle.
---@return table issues List of issue entries containing `key`, `line`, `col`, and `preview`.
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
  for line_idx, line in ipairs(lines) do
    local start = 1
    while true do
      local s, e = line:find(pattern, start)
      if not s then
        break
      end
      local key = line:sub(s, e)
      if key ~= "" and not seen[key] and not should_ignore_issue_key(key) then
        seen[key] = true
        table.insert(issues, {
          key = key,
          line = line_idx,
          col = s,
          preview = utils.trim(line),
        })
      end
      start = e + 1
    end
  end
  return issues
end

---Build a single-line preview with location for a buffer issue entry.
---@param issue table Issue entry containing key, line, col, and preview.
---@return string summary Human-readable summary with line/col context.
local function buffer_issue_summary(issue)
  if not issue then
    return ""
  end
  local preview = issue.preview or issue.line_text or ""
  preview = utils.trim(preview:gsub("%s+", " "))
  if issue.key and issue.key ~= "" and preview ~= "" then
    local escaped = (vim and vim.pesc and vim.pesc(issue.key)) or issue.key:gsub("(%W)", "%%%1")
    preview = utils.trim(preview:gsub(escaped, ""))
    preview = utils.trim(preview:gsub("%s+", " "))
  end
  if preview ~= "" then
    return preview
  end
  if issue.line and issue.col then
    return string.format("L%d:%d", issue.line, issue.col)
  elseif issue.line then
    return string.format("L%d", issue.line)
  end
  return ""
end

---Fetch summaries for a collection of issue keys via Jira search.
---@param issue_keys string[] List of issue keys to hydrate.
---@param callback fun(map:table|nil, err:string|nil) Invoked with map[key]=summary or an error.
---@return nil
local function fetch_issue_summaries(issue_keys, callback)
  if not issue_keys or #issue_keys == 0 then
    callback({}, nil)
    return
  end
  local keys = {}
  local seen = {}
  for _, key in ipairs(issue_keys) do
    if type(key) == "string" and key ~= "" and not seen[key] then
      table.insert(keys, key)
      seen[key] = true
    end
  end
  if #keys == 0 then
    callback({}, nil)
    return
  end
  local jql = string.format("issuekey in (%s)", table.concat(keys, ", "))
  api.search_issues(config, {
    jql = jql,
    max_results = math.min(#keys, 200),
    fields = { "key", "summary", "status" },
  }, function(result, err)
    if err or not result then
      callback(nil, err or "Unable to fetch Jira issue summaries.")
      return
    end
    local map = {}
    for _, issue in ipairs(result.issues or {}) do
      if issue and issue.key then
        map[issue.key] = utils.trim(issue.summary or "")
      end
    end
    callback(map, nil)
  end)
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
  if statusline_updates_enabled() then
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
      group = group,
      callback = function()
        update_hover_statusline()
      end,
    })
    vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
      group = group,
      callback = function()
        update_hover_statusline({ fetch = true })
      end,
    })
    vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
      group = group,
      callback = function()
        update_hover_statusline()
      end,
    })
    vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
      group = group,
      callback = function()
        clear_statusline_message()
      end,
    })
  end
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
  local requested_output = opts.statusline and opts.statusline.output
  local statusline_opts = opts.statusline
  if statusline_opts == false then
    statusline_opts = { enabled = false }
  end
  config = vim.tbl_deep_extend("force", deepcopy(default_config), opts)
  config.api = vim.tbl_deep_extend("force", deepcopy(default_config.api), opts.api or {})
  config.popup = vim.tbl_deep_extend("force", deepcopy(default_config.popup), opts.popup or {})
  config.assigned_popup = vim.tbl_deep_extend("force", deepcopy(default_config.assigned_popup), opts.assigned_popup or {})
  config.search_popup = vim.tbl_deep_extend("force", deepcopy(default_config.search_popup), opts.search_popup or {})
  config.history_popup = vim.tbl_deep_extend("force", deepcopy(default_config.history_popup), opts.history_popup or {})
  config.buffer_popup = vim.tbl_deep_extend("force", deepcopy(default_config.buffer_popup), opts.buffer_popup or {})
  config.statusline = vim.tbl_deep_extend("force", deepcopy(default_config.statusline), statusline_opts or {})
  if not requested_output and statusline_output_mode() == "statusline" and lualine_available() then
    config.statusline.output = "lualine"
  end
  if not statusline_template_enabled() and statusline_state.applied and statusline_state.original then
    vim.o.statusline = statusline_state.original
  end
  statusline_state.cache = {}
  statusline_state.pending = {}
  statusline_state.current_key = nil
  statusline_state.message = ""
  statusline_state.applied = statusline_template_enabled() and statusline_state.applied or false
  statusline_state.template = statusline_template_enabled() and statusline_state.template or nil
  debug_state.hover_issue = nil
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
  local buffer_keymap = config.buffer_popup and config.buffer_popup.keymap
  if buffer_keymap and buffer_keymap ~= "" then
    vim.keymap.set("n", buffer_keymap, function()
      M.open_buffer_issue_list()
    end, { desc = "jira.nvim: list buffer issues" })
  end
  local history_keymap = config.history_popup and config.history_popup.keymap
  if history_keymap and history_keymap ~= "" then
    vim.keymap.set("n", history_keymap, function()
      M.open_issue_history()
    end, { desc = "jira.nvim: open viewed issue history" })
  end
  if statusline_updates_enabled() then
    if statusline_template_enabled() then
      apply_statusline_template()
    end
    update_hover_statusline()
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

---List all Jira issue keys found in the current buffer.
---@return nil
function M.open_buffer_issue_list()
  local bufnr = vim.api.nvim_get_current_buf()
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local origin_win = vim.api.nvim_get_current_win()
  local issues = collect_buffer_issues(bufnr)
  local entries = {}
  local issue_keys = {}
  for _, item in ipairs(issues) do
    table.insert(issue_keys, item.key)
    table.insert(entries, {
      key = item.key,
      summary = buffer_issue_summary(item),
      line = item.line,
      col = item.col,
    })
  end

  local function render_list(render_entries)
    popup.render_issue_list(render_entries, config, {
      title = "Issues in Buffer",
      subtitle = string.format("%d matches in buffer", #render_entries),
      empty_message = "No Jira issue keys found in this buffer.",
      layout = config.buffer_popup,
      preview = { bufnr = bufnr },
      close_on_select = config.buffer_popup and config.buffer_popup.close_on_select,
      on_select = function(issue)
        local nav = update_navigation_from_buffer(bufnr, issue.key)
        local opts = { navigation = nav }
        if origin_win and vim.api.nvim_win_is_valid(origin_win) then
          opts.return_focus = origin_win
        end
        M.open_issue(issue.key, opts)
      end,
    })
  end

  if #issue_keys == 0 then
    render_list(entries)
    return
  end

  fetch_issue_summaries(issue_keys, function(summary_map, err)
    local enriched = {}
    for _, entry in ipairs(entries) do
      local summary = summary_map and summary_map[entry.key]
      local final_summary = entry.summary
      if summary and summary ~= "" then
        final_summary = summary
      end
      table.insert(enriched, {
        key = entry.key,
        summary = final_summary,
        line = entry.line,
        col = entry.col,
      })
    end
    vim.schedule(function()
      if err then
        vim.notify(
          string.format("jira.nvim: failed to load Jira summaries for buffer issues: %s", err),
          vim.log.levels.WARN
        )
      end
      render_list(enriched)
    end)
  end)
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

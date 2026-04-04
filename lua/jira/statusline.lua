---Statusline integration for jira.nvim.
-- Manages hover-driven statusline updates, lualine refresh, and debouncing.
-- Call M.setup(config, callbacks) from init.lua after each config change.
-- Callbacks break the circular dependency on require("jira").

local utils = require("jira.utils")
local api = require("jira.api")

local M = {}

---@type table Active plugin configuration (set via setup).
local config = {}

---@type table Injected callbacks: find_cursor_issue, is_ignored.
local callbacks = {}

local statusline_defaults = {
  enabled = true,
  output = "message",
  max_length = 80,
  loading_text = "Loading...",
  error_text = "Unable to load issue",
  empty_text = "No summary",
  message_highlight = nil,
}

local statusline_state = {
  cache = {},
  _cache_keys = {},
  pending = {},
  current_key = nil,
  message = "",
  applied = false,
  original = nil,
  template = nil,
}

local hover_debounce_timer = nil
local hover_debounce_ms = 120
local last_hover_issue = nil -- tracks last logged key to avoid duplicate debug spam

-- ── Internal helpers ──────────────────────────────────────────────────────────

---Emit debug logs when enabled.
---@param message string Text to log.
---@return nil
local function debug_log(message)
  if not config.debug then return end
  pcall(vim.notify, string.format("jira.nvim debug: %s", message), vim.log.levels.DEBUG)
end

---Check whether a highlight group exists.
---@param name string Highlight group name.
---@return boolean exists True when the group is defined.
local function highlight_exists(name)
  if vim.api.nvim_get_hl then
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name })
    return ok and type(hl) == "table" and next(hl) ~= nil
  end
  if not vim.api.nvim_get_hl_by_name then return false end
  local ok, hl = pcall(vim.api.nvim_get_hl_by_name, name, true)
  return ok and type(hl) == "table" and next(hl) ~= nil
end

---Check whether lualine is available (loaded or loadable).
---@return boolean available True when lualine can be required.
local function lualine_available()
  if package.loaded["lualine"] then return true end
  local ok = pcall(require, "lualine")
  return ok
end

---Resolve a statusline configuration value with a fallback to the built-in defaults.
---@param key string Config field name.
---@return any value Effective value for the requested option.
local function cfg_value(key)
  local cfg = config.statusline or {}
  if cfg[key] ~= nil then return cfg[key] end
  return statusline_defaults[key]
end

-- ── Output-mode helpers ───────────────────────────────────────────────────────

---Determine how hover feedback should be displayed.
---@return string mode Either "statusline", "lualine", or "message".
local function output_mode()
  local mode = cfg_value("output")
  if type(mode) == "string" then
    local lowered = mode:lower():gsub("[_%s-]+", "")
    if lowered == "message" then return "message" end
    if lowered == "lualine" then return "lualine" end
  end
  return "statusline"
end

---Check whether hover-driven updates are enabled at all.
---@return boolean enabled
local function updates_enabled()
  return config.statusline ~= false
end

---Check whether the plugin should own the statusline template.
---@return boolean enabled
local function template_enabled()
  local cfg = config.statusline
  return updates_enabled()
    and output_mode() == "statusline"
    and not (cfg and cfg.enabled == false)
end

-- ── Public update-mode queries (called from init.lua) ─────────────────────────

---Check whether hover statusline updates should run.
---@return boolean enabled
function M.updates_enabled()
  return updates_enabled()
end

---Check whether the plugin should apply its own statusline template.
---@return boolean enabled
function M.template_enabled()
  return template_enabled()
end

---Return true when lualine should be used based on config and availability.
---@return boolean use_lualine
function M.should_use_lualine()
  return output_mode() == "lualine" or lualine_available()
end

-- ── Rendering helpers ─────────────────────────────────────────────────────────

---Build the plugin-owned statusline layout string.
---@return string template Statusline format string.
local function build_template()
  return table.concat({
    "%<%f %h%m%r ",
    "%-14.(%l,%c%V%) %P",
    "%=",
    "%{v:lua.require'jira'.statusline_message()}",
    "%=",
    "%{mode()}",
  })
end

---Clamp and sanitise the maximum summary length.
---@return integer limit Non-negative character limit (0 means no limit).
local function max_length()
  local v = tonumber(cfg_value("max_length")) or 0
  return math.floor(math.max(0, v))
end

---Calculate the usable horizontal space for the summary.
---@param reserved_width integer|nil Width already consumed by fixed text.
---@return integer limit
local function summary_limit(reserved_width)
  local columns = tonumber(vim.o.columns) or 0
  local taken = math.max(0, tonumber(reserved_width) or 0)
  local available = math.max(0, columns - taken)
  if available > 0 then return available end
  return max_length()
end

---Escape percent characters for safe statusline interpolation.
---@param text string|nil Raw text.
---@return string escaped
local function escape_component(text)
  return (text or ""):gsub("%%", "%%%%")
end

---Format a summary, applying terminal-width-aware truncation.
---@param summary string|nil Raw summary text.
---@param max_width integer|nil Maximum display width.
---@return string formatted
local function format_summary(summary, max_width)
  local text = utils.trim(summary or "")
  local limit = tonumber(max_width) or 0
  if limit <= 0 then limit = max_length() end
  if limit <= 0 then return text end
  local width = vim.api.nvim_strwidth(text)
  if width <= limit then return text end
  local suffix = "..."
  local suffix_width = vim.api.nvim_strwidth(suffix)
  if limit <= suffix_width then return suffix:sub(1, limit) end
  local target = limit - suffix_width
  -- Binary search: largest char count whose display width fits target.
  local char_count = vim.fn.strchars(text)
  local lo, hi = 0, char_count
  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    if vim.api.nvim_strwidth(vim.fn.strcharpart(text, 0, mid)) <= target then
      lo = mid
    else
      hi = mid - 1
    end
  end
  return vim.fn.strcharpart(text, 0, lo) .. suffix
end

---Compose the full statusline snippet for a key + summary.
---@param issue_key string Issue key.
---@param summary string|table|nil Summary text or {summary = ...} table.
---@return string text
local function format_text(issue_key, summary)
  if not issue_key or issue_key == "" then return "" end
  local summary_text = ""
  if type(summary) == "table" then
    summary_text = utils.trim(summary.summary or "")
  else
    summary_text = utils.trim(summary or "")
  end
  if summary_text == "" then
    summary_text = utils.trim(cfg_value("empty_text") or "")
  end
  if summary_text == "" then return issue_key end
  local prefix = string.format("%s: ", issue_key)
  local reserved = vim.api.nvim_strwidth(prefix)
  summary_text = format_summary(summary_text, summary_limit(reserved))
  return string.format("%s%s", prefix, summary_text)
end

---Look up a cached summary from the issue history store.
---@param issue_key string Issue key to look up.
---@return string|nil summary Previously seen summary or nil.
local function summary_from_history(issue_key)
  if not issue_key or issue_key == "" then return nil end
  local get_issue = callbacks.get_issue_history
  if type(get_issue) ~= "function" then return nil end
  local hist = get_issue()
  for idx = #hist, 1, -1 do
    local entry = hist[idx]
    if entry and entry.key == issue_key and entry.summary and entry.summary ~= "" then
      return entry.summary
    end
  end
  return nil
end

-- ── Refresh helpers ───────────────────────────────────────────────────────────

---Post hover text to the command area.
---@param message string Hover text to display.
---@return nil
local function echo_message(message)
  local cleaned = utils.trim(message or "")
  local highlight = cfg_value("message_highlight")
  if highlight and not highlight_exists(highlight) then highlight = nil end
  if cleaned == "" then
    pcall(vim.api.nvim_echo, {}, false, {})
    return
  end
  pcall(vim.api.nvim_echo, { { cleaned, highlight } }, false, {})
end

---Refresh lualine without touching vim.o.statusline.
---@return boolean refreshed
local function refresh_lualine()
  if not package.loaded["lualine"] then return false end
  local ok, lualine = pcall(require, "lualine")
  if not ok or type(lualine) ~= "table" then return false end
  local refresh = lualine.refresh
  if type(refresh) ~= "function" then return false end
  refresh({ place = { "statusline" }, trigger = "jira.nvim" })
  return true
end

---Update the active statusline message and refresh the UI as needed.
---@param message string|nil New statusline content.
---@return nil
local function set_message(message)
  local cleaned = utils.trim(message or "")
  local mode = output_mode()
  local unchanged = statusline_state.message == cleaned
  statusline_state.message = cleaned
  if not updates_enabled() then return end
  if mode == "message" then
    echo_message(cleaned)
    return
  end
  if mode == "lualine" then
    if unchanged then return end
    if not refresh_lualine() then pcall(vim.cmd, "redrawstatus") end
    return
  end
  -- statusline mode
  local template_needed = template_enabled()
    and (not statusline_state.applied
      or not statusline_state.template
      or vim.o.statusline ~= statusline_state.template)
  if template_needed then
    M.apply_template()
  end
  if unchanged and not template_needed then return end
  pcall(vim.cmd, "redrawstatus")
end

-- ── Public API ────────────────────────────────────────────────────────────────

---Apply the custom statusline layout if configured.
---@return nil
function M.apply_template()
  if not template_enabled() then return end
  if not statusline_state.original then
    statusline_state.original = vim.o.statusline
  end
  local tmpl = build_template()
  statusline_state.template = tmpl
  if vim.o.statusline ~= tmpl then
    vim.o.statusline = tmpl
  end
  statusline_state.applied = true
end

---Expose the statusline message for use in statusline templates.
---Called by `%{v:lua.require'jira'.statusline_message()}`.
---@return string message Escaped statusline content.
function M.statusline_message()
  return escape_component(statusline_state.message or "")
end

---Expose the hover message for lualine components without escaping.
---@return string message Raw hover text.
function M.lualine_component()
  return statusline_state.message or ""
end

---Clear the active hover statusline state.
---@return nil
function M.clear_message()
  statusline_state.current_key = nil
  last_hover_issue = nil
  set_message("")
end

---Refresh the hover-driven statusline message for the current cursor position.
---@param opts table|nil Behaviour flags: `fetch` triggers an API call when true.
---@return nil
function M.update_hover(opts)
  if not updates_enabled() then return end
  opts = opts or {}
  local find = callbacks.find_cursor_issue
  local is_ignored = callbacks.is_ignored
  if type(find) ~= "function" then return end
  local issue_key = find()
  if not issue_key then return end
  if type(is_ignored) == "function" and is_ignored(issue_key) then return end

  if issue_key ~= last_hover_issue then
    debug_log(string.format("cursor on issue %s%s", issue_key, opts.fetch and " (fetching)" or ""))
    last_hover_issue = issue_key
  end

  statusline_state.current_key = issue_key

  local cached = statusline_state.cache[issue_key]
  local cached_complete = type(cached) == "table" and cached._complete
  if cached then
    set_message(format_text(issue_key, cached))
    if cached_complete or not opts.fetch then return end
  end

  if statusline_state.pending[issue_key] then
    local loading = cached or { summary = cfg_value("loading_text") or "" }
    set_message(format_text(issue_key, loading))
    return
  end

  local hist_summary = summary_from_history(issue_key)
  if hist_summary and hist_summary ~= "" and not cached then
    cached = { summary = utils.trim(hist_summary), _complete = false }
    statusline_state.cache[issue_key] = cached
    set_message(format_text(issue_key, cached))
    if not opts.fetch then return end
  end

  if not opts.fetch then
    set_message(format_text(issue_key, cfg_value("loading_text") or ""))
    return
  end

  statusline_state.pending[issue_key] = true
  set_message(format_text(issue_key, { summary = cfg_value("loading_text") or "" }))

  api.fetch_issue_summary(issue_key, config, function(issue, err)
    vim.schedule(function()
      statusline_state.pending[issue_key] = nil
      if err then
        if statusline_state.current_key == issue_key then
          set_message(format_text(issue_key, cfg_value("error_text")))
        end
        return
      end
      -- Evict oldest entry when cache exceeds 200 keys.
      local cache_limit = 200
      if #statusline_state._cache_keys >= cache_limit then
        local oldest = table.remove(statusline_state._cache_keys, 1)
        statusline_state.cache[oldest] = nil
      end
      if not statusline_state.cache[issue_key] then
        table.insert(statusline_state._cache_keys, issue_key)
      end
      statusline_state.cache[issue_key] = {
        summary = utils.trim(issue and issue.summary or ""),
        _complete = true,
      }
      if statusline_state.current_key == issue_key then
        set_message(format_text(issue_key, statusline_state.cache[issue_key]))
      end
    end)
  end)
end

---Schedule a debounced hover statusline update.
---@return nil
function M.schedule_hover_update()
  if not updates_enabled() then return end
  local uv = vim.uv or vim.loop
  if hover_debounce_timer then
    hover_debounce_timer:stop()
  else
    hover_debounce_timer = uv.new_timer()
  end
  hover_debounce_timer:start(
    hover_debounce_ms,
    0,
    vim.schedule_wrap(function()
      M.update_hover()
    end)
  )
end

---Initialise the statusline module for the current plugin configuration.
---@param cfg table Merged plugin config.
---@param cbs table Callbacks: find_cursor_issue(), is_ignored(key), get_issue_history().
---@return nil
function M.setup(cfg, cbs)
  config = cfg or {}
  callbacks = cbs or {}
  -- Stop and release the debounce timer from a previous setup call.
  if hover_debounce_timer then
    hover_debounce_timer:stop()
    hover_debounce_timer:close()
    hover_debounce_timer = nil
  end
  last_hover_issue = nil
  -- Restore the original statusline when the template mode is disabled.
  if not template_enabled() and statusline_state.applied and statusline_state.original then
    vim.o.statusline = statusline_state.original
  end
  statusline_state.cache = {}
  statusline_state._cache_keys = {}
  statusline_state.pending = {}
  statusline_state.current_key = nil
  statusline_state.message = ""
  statusline_state.applied = template_enabled() and statusline_state.applied or false
  statusline_state.template = template_enabled() and statusline_state.template or nil
end

---Detect lualine and auto-set the output mode when not explicitly configured.
---Call this from init.lua after config is merged but before setup().
---@param requested_output string|nil The output mode explicitly set by the user.
---@return string|nil detected "lualine" when auto-detected, nil otherwise.
function M.detect_lualine(requested_output)
  if not requested_output and output_mode() == "statusline" and lualine_available() then
    return "lualine"
  end
  return nil
end

return M

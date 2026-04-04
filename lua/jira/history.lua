---Persistent history management for jira.nvim.
-- Owns all three history stores (search, issue, filter) and their disk I/O.
-- Call M.setup(config) from init.lua after each config change.

local utils = require("jira.utils")

local M = {}

---@type table Active configuration (set via setup).
local config = {}

---@type string[] JQL search history (newest last).
local search_history = {}
---@type table[] Issue history entries {key, summary} (newest last).
local issue_history = {}
---@type table[] Filter history entries {id, name} (newest last).
local filter_history = {}

-- ── Path helpers ──────────────────────────────────────────────────────────────

local function join_path(...)
  local parts = { ... }
  if vim.fs and vim.fs.joinpath then
    return vim.fs.joinpath(table.unpack(parts))
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

local function search_history_path()
  local ok, data_dir = pcall(vim.fn.stdpath, "data")
  if not ok or not data_dir or data_dir == "" then return nil end
  return join_path(data_dir, "jira.nvim", "search_history.json")
end

local function issue_history_path()
  local ok, data_dir = pcall(vim.fn.stdpath, "data")
  if not ok or not data_dir or data_dir == "" then return nil end
  return join_path(data_dir, "jira.nvim", "issue_history.json")
end

local function filter_history_path()
  local ok, data_dir = pcall(vim.fn.stdpath, "data")
  if not ok or not data_dir or data_dir == "" then return nil end
  return join_path(data_dir, "jira.nvim", "filter_history.json")
end

-- ── Async write ───────────────────────────────────────────────────────────────

local function write_file_async(path, payload)
  local dir = path:match("^(.*)/[^/]+$")
  vim.schedule(function()
    if dir and dir ~= "" then pcall(vim.fn.mkdir, dir, "p") end
    local file = io.open(path, "w")
    if not file then return end
    file:write(payload)
    file:close()
  end)
end

-- ── Limit helpers ─────────────────────────────────────────────────────────────

local function get_limit(key)
  local cfg = config[key] or {}
  local limit = tonumber(cfg.history_size) or 0
  return math.max(0, math.floor(limit))
end

-- ── Push (dedup, newest-last) ─────────────────────────────────────────────────

local function push_search(value)
  if value == "" then return end
  for i = #search_history, 1, -1 do
    if search_history[i] == value then table.remove(search_history, i) end
  end
  table.insert(search_history, value)
end

local function push_issue(entry)
  if not entry or not entry.key or entry.key == "" then return end
  for i = #issue_history, 1, -1 do
    if issue_history[i] and issue_history[i].key == entry.key then
      table.remove(issue_history, i)
    end
  end
  entry.summary = utils.trim(entry.summary or "")
  table.insert(issue_history, entry)
end

local function push_filter(entry)
  if not entry or not entry.id or entry.id == "" then return end
  local id = tostring(entry.id)
  for i = #filter_history, 1, -1 do
    if filter_history[i] and tostring(filter_history[i].id) == id then
      table.remove(filter_history, i)
    end
  end
  table.insert(filter_history, { id = id, name = utils.trim(entry.name or "") })
end

-- ── Save ──────────────────────────────────────────────────────────────────────

local function save_search()
  if get_limit("search_popup") <= 0 then return end
  local path = search_history_path()
  if not path then return end
  local ok, payload = pcall(utils.json_encode, search_history)
  if ok and payload then write_file_async(path, payload) end
end

local function save_issue()
  if get_limit("history_popup") <= 0 then return end
  local path = issue_history_path()
  if not path then return end
  local ok, payload = pcall(utils.json_encode, issue_history)
  if ok and payload then write_file_async(path, payload) end
end

local function save_filter()
  if get_limit("filter_popup") <= 0 then return end
  local path = filter_history_path()
  if not path then return end
  local ok, payload = pcall(utils.json_encode, filter_history)
  if ok and payload then write_file_async(path, payload) end
end

-- ── Trim ──────────────────────────────────────────────────────────────────────

local function trim_search(opts)
  local limit = get_limit("search_popup")
  if limit <= 0 then search_history = {} else
    while #search_history > limit do table.remove(search_history, 1) end
  end
  if opts and opts.persist then save_search() end
end

local function trim_issue(opts)
  local limit = get_limit("history_popup")
  if limit <= 0 then issue_history = {} else
    while #issue_history > limit do table.remove(issue_history, 1) end
  end
  if opts and opts.persist then save_issue() end
end

local function trim_filter(opts)
  local limit = get_limit("filter_popup")
  if limit <= 0 then filter_history = {} else
    while #filter_history > limit do table.remove(filter_history, 1) end
  end
  if opts and opts.persist then save_filter() end
end

-- ── Load ──────────────────────────────────────────────────────────────────────

local function load_search()
  search_history = {}
  local path = search_history_path()
  if not path then return end
  local file = io.open(path, "r")
  if not file then return end
  local ok, contents = pcall(file.read, file, "*a")
  file:close()
  if not ok or not contents or contents == "" then return end
  local decoded = utils.json_decode(contents)
  if type(decoded) ~= "table" then return end
  for _, entry in ipairs(decoded) do
    if type(entry) == "string" then
      local cleaned = utils.trim(entry)
      if cleaned ~= "" then push_search(cleaned) end
    end
  end
  trim_search({ persist = true })
end

local function load_issue()
  issue_history = {}
  local path = issue_history_path()
  if not path then return end
  local file = io.open(path, "r")
  if not file then return end
  local ok, contents = pcall(file.read, file, "*a")
  file:close()
  if not ok or not contents or contents == "" then return end
  local decoded = utils.json_decode(contents)
  if type(decoded) ~= "table" then return end
  for _, entry in ipairs(decoded) do
    if type(entry) == "table" and type(entry.key) == "string" then
      push_issue({ key = entry.key, summary = utils.trim(entry.summary or "") })
    elseif type(entry) == "string" then
      push_issue({ key = entry, summary = "" })
    end
  end
  trim_issue({ persist = true })
end

local function load_filter()
  filter_history = {}
  local path = filter_history_path()
  if not path then return end
  local file = io.open(path, "r")
  if not file then return end
  local ok, contents = pcall(file.read, file, "*a")
  file:close()
  if not ok or not contents or contents == "" then return end
  local decoded = utils.json_decode(contents)
  if type(decoded) ~= "table" then return end
  for _, entry in ipairs(decoded) do
    if type(entry) == "table" and entry.id then
      push_filter({ id = tostring(entry.id), name = utils.trim(entry.name or "") })
    elseif type(entry) == "string" then
      local cleaned = utils.trim(entry)
      if cleaned ~= "" then push_filter({ id = cleaned, name = "" }) end
    end
  end
  trim_filter({ persist = true })
end

-- ── Public API ────────────────────────────────────────────────────────────────

---Initialise the history module with the active plugin configuration.
---Call this from init.lua's setup() after config is merged.
---@param cfg table Merged plugin config.
---@return nil
function M.setup(cfg)
  config = cfg or {}
end

---Load all three history stores from disk and apply limits.
---@return nil
function M.load_all()
  load_search()
  load_issue()
  load_filter()
end

---Trim all three history stores to their configured limits.
---@param opts table|nil Pass { persist = true } to also save after trimming.
---@return nil
function M.trim_all(opts)
  trim_search(opts)
  trim_issue(opts)
  trim_filter(opts)
end

---Record a JQL search query in history.
---@param query string|nil JQL text.
---@return nil
function M.record_search(query)
  local cleaned = utils.trim(query or "")
  if cleaned == "" then return end
  push_search(cleaned)
  trim_search({ persist = true })
end

---Record a successfully opened issue in history.
---@param issue table|nil Jira issue payload containing key and fields.
---@return nil
function M.record_issue(issue)
  if not issue or not issue.key or issue.key == "" then return end
  local summary = ""
  local fields = issue.fields
  if type(fields) == "table" then
    summary = utils.trim(fields.summary or fields.title or "")
  end
  push_issue({ key = issue.key, summary = summary })
  trim_issue({ persist = true })
end

---Record a filter selection in history.
---@param filter table|nil Filter payload containing id and name.
---@return nil
function M.record_filter(filter)
  if not filter or not filter.id then return end
  push_filter({ id = tostring(filter.id), name = utils.trim(filter.name or "") })
  trim_filter({ persist = true })
end

---Return the current search history (newest last).
---@return string[] history
function M.get_search() return search_history end

---Return the current issue history (newest last).
---@return table[] history
function M.get_issue() return issue_history end

---Return the current filter history (newest last).
---@return table[] history
function M.get_filter() return filter_history end

return M

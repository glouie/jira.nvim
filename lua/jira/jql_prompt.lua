local api = require("jira.api")
local utils = require("jira.utils")

local JQLPrompt = {}

local prompt_ns = vim.api.nvim_create_namespace("jira.nvim.jql")
local hint_ns = vim.api.nvim_create_namespace("jira.nvim.jql.hint")
local highlight_ready = false
local default_help = "Example: project = ABC AND status in ('In Progress', 'To Do') ORDER BY updated DESC"
local default_footer = "Esc Normal | <C-c>/q exit | <C-n>/<C-p> navigate | <CR>/<C-y> submit | use normal edits to yank/clear"
local completion_group = vim.api.nvim_create_augroup("jira.nvim.jql.completion", { clear = true })
local keyword_list = {
  "AND",
  "OR",
  "NOT",
  "IN",
  "IS",
  "ORDER",
  "BY",
  "ASC",
  "DESC",
  "EMPTY",
  "NULL",
  "ON",
  "BEFORE",
  "AFTER",
}
local operator_list = { "!", "~", "!=", ">=", "<=", "=", ">", "<" }

local function buffer_text(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return ""
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  return table.concat(lines, "\n")
end

local function line_at_cursor(buf, win)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return ""
  end
  local cursor = win and vim.api.nvim_win_get_cursor(win)
  if not cursor then
    return ""
  end
  local row = math.max(0, cursor[1] - 1)
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
  return line or ""
end

local function ensure_highlights()
  if highlight_ready then
    return
  end
  vim.api.nvim_set_hl(0, "JiraJQLKeyword", {
    default = true,
    fg = "#f5c2e7",
    bold = true,
  })
  vim.api.nvim_set_hl(0, "JiraJQLString", {
    default = true,
    fg = "#a6e3a1",
  })
  vim.api.nvim_set_hl(0, "JiraJQLField", {
    default = true,
    fg = "#89b4fa",
    bold = true,
  })
  vim.api.nvim_set_hl(0, "JiraJQLOperator", {
    default = true,
    fg = "#f9e2af",
    bold = true,
  })
  highlight_ready = true
end

local function add_highlight(buf, group, line, start_col, end_col)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_add_highlight(buf, prompt_ns, group, line, start_col, end_col)
end

local function boundaries_ok(text, s, e)
  local before_ok = s == 1 or text:sub(s - 1, s - 1):match("%W")
  local after_ok = e > #text or text:sub(e, e):match("%W")
  return before_ok and after_ok
end

local function highlight_line(buf, line, line_nr, autocomplete)
  line_nr = line_nr or 0
  if not line or line == "" then
    return
  end
  for s, e in line:gmatch("()\".-\"()") do
    add_highlight(buf, "JiraJQLString", line_nr, s - 1, e - 1)
  end
  for s, e in line:gmatch("()'[^']*'()") do
    add_highlight(buf, "JiraJQLString", line_nr, s - 1, e - 1)
  end
  local upper = line:upper()
  for _, kw in ipairs(keyword_list) do
    local search_from = 1
    while true do
      local s, e = upper:find(kw, search_from, true)
      if not s then
        break
      end
      if boundaries_ok(upper, s, e) then
        add_highlight(buf, "JiraJQLKeyword", line_nr, s - 1, e)
      end
      search_from = e + 1
    end
  end
  for _, op in ipairs(operator_list) do
    local search_from = 1
    while true do
      local s, e = line:find(op, search_from, true)
      if not s then
        break
      end
      add_highlight(buf, "JiraJQLOperator", line_nr, s - 1, e)
      search_from = e + 1
    end
  end
  local field_map = {}
  if autocomplete and autocomplete.fields then
    for _, field in ipairs(autocomplete.fields) do
      if type(field) == "string" then
        field_map[field:lower()] = true
      end
    end
  end
  if next(field_map) ~= nil then
    for start_idx, name, end_idx in line:gmatch("()([%w_%.]+)()") do
      if field_map[name:lower()] then
        local remainder = line:sub(end_idx)
        if remainder:match("^%s*[!<>=~]") or remainder:match("^%s+[Ii][Nn]%s") then
          add_highlight(buf, "JiraJQLField", line_nr, start_idx - 1, end_idx - 1)
        end
      end
    end
  end
end

local function highlight_buffer(buf, autocomplete)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, prompt_ns, 0, -1)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for idx, line in ipairs(lines) do
    highlight_line(buf, line, idx - 1, autocomplete)
  end
end

local function set_help(buf, text)
  vim.api.nvim_buf_clear_namespace(buf, hint_ns, 0, -1)
  if (not text or text == "") and (not default_footer or default_footer == "") then
    return
  end
  local line = math.max(0, vim.api.nvim_buf_line_count(buf) - 1)
  local virt_lines = {}
  if text and text ~= "" then
    table.insert(virt_lines, { { text, "Comment" } })
  end
  if default_footer and default_footer ~= "" then
    table.insert(virt_lines, { { default_footer, "Comment" } })
  end
  if #virt_lines == 0 then
    return
  end
  vim.api.nvim_buf_set_extmark(buf, hint_ns, line, 0, {
    virt_lines = virt_lines,
    virt_lines_above = false,
  })
end

local function build_dimensions(config, default_value)
  local width = math.min(math.max(50, math.floor(vim.o.columns * 0.65)), vim.o.columns - 2)
  local min_height = 4
  local max_height = math.max(min_height, math.floor(vim.o.lines * 0.35))
  local default_lines = 1
  if default_value and default_value ~= "" then
    default_lines = #vim.split(default_value, "\n", { trimempty = false })
  end
  local desired = math.min(max_height, math.max(min_height, default_lines + 2))
  local height = desired
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)
  local border = (config and config.popup and config.popup.border) or "rounded"
  return {
    width = width,
    height = height,
    col = col,
    row = row,
    border = border,
  }
end

local function close_prompt(state)
  if not state or state.closed then
    return
  end
  state.closed = true
  local current_line = nil
  local buf_valid = state.buf and vim.api.nvim_buf_is_valid(state.buf)
  if buf_valid then
    current_line = buffer_text(state.buf)
  end
  if state.forced_insert then
    pcall(vim.cmd, "stopinsert")
  end
  if state.suggestion_timer then
    pcall(state.suggestion_timer.stop, state.suggestion_timer)
    pcall(state.suggestion_timer.close, state.suggestion_timer)
    state.suggestion_timer = nil
  end
  if buf_valid then
    vim.api.nvim_clear_autocmds({ group = completion_group, buffer = state.buf })
  else
    vim.api.nvim_clear_autocmds({ group = completion_group })
  end
  if state.on_close then
    pcall(state.on_close, current_line)
  end
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    pcall(vim.api.nvim_win_close, state.win, true)
  end
  if buf_valid then
    pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
  end
  state.buf = nil
  state.win = nil
end

local function parse_suggestion_response(resp)
  local items = {}
  local list = nil
  if type(resp) == "table" then
    if type(resp.suggestions) == "table" then
      list = resp.suggestions
    elseif type(resp.results) == "table" then
      list = resp.results
    end
  end
  for _, entry in ipairs(list or {}) do
    local text = nil
    if type(entry) == "string" then
      text = entry
    elseif type(entry) == "table" then
      text = entry.displayName or entry.text or entry.value or entry.name
    end
    if type(text) == "string" and text ~= "" then
      table.insert(items, text)
    end
  end
  return items
end

local function apply_completions(state, prefix, items)
  if not state or not state.win or not vim.api.nvim_win_is_valid(state.win) then
    return
  end
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end
  if #items == 0 then
    return
  end
  local mode = vim.api.nvim_get_mode().mode
  if mode ~= "i" and mode ~= "ic" then
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(state.win)
  if not cursor then
    return
  end
  local col = cursor[2] + 1
  local start_col = math.max(1, col - #prefix)
  local completions = {}
  for _, item in ipairs(items) do
    table.insert(completions, { word = item, menu = "[Jira]" })
  end
  pcall(vim.fn.complete, start_col, completions)
end

local function find_value_context(line, col)
  if not line or line == "" then
    return nil
  end
  local before = line:sub(1, col)
  local field, prefix = before:match("([%w_%.]+)%s+[Nn][Oo][Tt]%s+[Ii][Nn]%s+[%(%[]?%s*([%w%s%-%._]*)$")
  if not field then
    field, prefix = before:match("([%w_%.]+)%s+[Ii][Nn]%s+[%(%[]?%s*([%w%s%-%._]*)$")
  end
  if not field then
    field, prefix = before:match("([%w_%.]+)%s*[!<>=~]+%s*([%w%s%-%._]*)$")
  end
  if field then
    return field, utils.trim(prefix or "")
  end
  return nil
end

local function maybe_suggest_field_values(state, line)
  if not state or not state.win then
    return
  end
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(state.win)
  if not cursor then
    return
  end
  local col = cursor[2] + 1
  local field, prefix = find_value_context(line, col)
  if not field or not prefix or #prefix < 1 then
    return
  end
  local cache_key = string.format("%s::%s", field:lower(), prefix:lower())
  state.cache = state.cache or {}
  if state.cache[cache_key] then
    apply_completions(state, prefix, state.cache[cache_key])
    return
  end
  if not state.suggestion_timer then
    state.suggestion_timer = vim.loop.new_timer()
  end
  local timer = state.suggestion_timer
  if not timer then
    return
  end
  timer:stop()
  timer:start(
    200,
    0,
    vim.schedule_wrap(function()
      api.fetch_jql_suggestions(state.config, {
        field = field,
        value = prefix,
      }, function(result, err)
        vim.schedule(function()
          if err then
            vim.notify(string.format("jira.nvim: %s", err), vim.log.levels.WARN)
            return
          end
          local suggestions = parse_suggestion_response(result)
          state.cache[cache_key] = suggestions
          apply_completions(state, prefix, suggestions)
        end)
      end)
    end)
  )
end

local function maybe_suggest_fields(state, line)
  if not state or not state.autocomplete or not state.autocomplete.fields then
    return
  end
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(state.win)
  if not cursor then
    return
  end
  local col = cursor[2] + 1
  local before = line:sub(1, col)
  if before:find("[=!<>~]") then
    return
  end
  local prefix = before:match("([%w_%.]+)$")
  if not prefix or #prefix < 2 then
    return
  end
  local matches = {}
  for _, field in ipairs(state.autocomplete.fields) do
    if type(field) == "string" and field:lower():find(prefix:lower(), 1, true) == 1 then
      table.insert(matches, field)
    end
  end
  apply_completions(state, prefix, matches)
end

local function attach_listeners(state, on_submit, on_change)
  vim.api.nvim_clear_autocmds({ group = completion_group, buffer = state.buf })
  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    group = completion_group,
    buffer = state.buf,
    callback = function()
      local cursor_line = line_at_cursor(state.buf, state.win)
      highlight_buffer(state.buf, state.autocomplete)
      if on_change then
        on_change(buffer_text(state.buf))
      end
      maybe_suggest_field_values(state, cursor_line)
      maybe_suggest_fields(state, cursor_line)
    end,
  })
  vim.api.nvim_create_autocmd("BufLeave", {
    group = completion_group,
    buffer = state.buf,
    callback = function()
      close_prompt(state)
    end,
  })
  local key_opts = { buffer = state.buf, nowait = true, silent = true }
  local function submit_query()
    local text = buffer_text(state.buf)
    close_prompt(state)
    on_submit(text)
  end
  vim.keymap.set({ "i", "n" }, "<CR>", submit_query, key_opts)
  vim.keymap.set({ "i", "n" }, "<C-y>", submit_query, key_opts)
  vim.keymap.set({ "i", "n" }, "<C-c>", function()
    close_prompt(state)
  end, key_opts)
  vim.keymap.set("n", "q", function()
    close_prompt(state)
  end, key_opts)
end

local function fetch_autocomplete(state)
  api.fetch_jql_autocomplete(state.config, function(data, err)
    vim.schedule(function()
      if err then
        vim.notify(string.format("jira.nvim: %s", err), vim.log.levels.WARN)
        return
      end
      if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
        return
      end
      state.autocomplete = data or {}
      highlight_buffer(state.buf, state.autocomplete)
    end)
  end)
end

function JQLPrompt.open(opts)
  opts = opts or {}
  local default_value = opts.default or ""
  local help_text = opts.help or default_help
  local on_submit = opts.on_submit or function() end
  local on_change = opts.on_change
  local on_close = opts.on_close
  local config = opts.config or {}
  local initial_mode = vim.api.nvim_get_mode().mode
  local forced_insert = not (initial_mode == "i" or initial_mode == "ic")

  ensure_highlights()

  local buf = vim.api.nvim_create_buf(false, true)
  if not buf then
    return false
  end
  local dims = build_dimensions(config, default_value)
  local ok, win = pcall(vim.api.nvim_open_win, buf, true, {
    relative = "editor",
    width = dims.width,
    height = dims.height,
    col = dims.col,
    row = dims.row,
    style = "minimal",
    border = dims.border,
    title = "JQL Search",
    title_pos = "center",
  })
  if not ok or not win then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    return false
  end
  vim.api.nvim_win_set_option(win, "wrap", false)
  vim.api.nvim_win_set_option(win, "winhl", "Normal:JiraPopupDetailsBody,FloatBorder:JiraPopupDetailsHeader")

  local initial_lines = vim.split(default_value, "\n", { trimempty = false })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial_lines)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].buflisted = false
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].filetype = "jira_jql"
  set_help(buf, help_text)

  local state = {
    buf = buf,
    win = win,
    autocomplete = nil,
    cache = {},
    config = config,
    suggestion_timer = nil,
    on_close = on_close,
    closed = false,
    forced_insert = forced_insert,
  }

  fetch_autocomplete(state)
  highlight_buffer(buf, state.autocomplete)
  attach_listeners(state, on_submit, on_change)
  vim.cmd("startinsert")
  return true
end

return JQLPrompt

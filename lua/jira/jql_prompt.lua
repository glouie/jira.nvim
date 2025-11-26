---Interactive floating JQL prompt with autocomplete and highlighting.
-- Provides suggestion fetching, syntax highlighting, and keyboard shortcuts for composing queries.

local api = require("jira.api")
local utils = require("jira.utils")
local popup = require("jira.popup")

local JQLPrompt = {}

local prompt_ns = vim.api.nvim_create_namespace("jira.nvim.jql")
local hint_ns = vim.api.nvim_create_namespace("jira.nvim.jql.hint")
local highlight_ready = false
local default_help = "Example: project = ABC AND status in ('In Progress', 'To Do') ORDER BY updated DESC"
local default_footer = ""
local shortcut_ns = vim.api.nvim_create_namespace("jira.nvim.jql.shortcuts")
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

---Read all text from a buffer, preserving newlines.
---@param buf number Buffer handle.
---@return string contents Entire buffer contents joined by newline.
local function buffer_text(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return ""
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  return table.concat(lines, "\n")
end

---Get the current line under the cursor for a buffer/window.
---@param buf number Buffer handle.
---@param win number|nil Window handle; defaults to current window.
---@return string line Current line text or empty string.
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

---Create syntax highlight groups for the JQL prompt.
---@return nil
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

---Add a highlight entry to the prompt buffer.
---@param buf number Buffer handle.
---@param group string Highlight group name.
---@param line number Line number (0-based).
---@param start_col number Starting column (0-based).
---@param end_col number Ending column (0-based, exclusive).
---@return nil
local function add_highlight(buf, group, line, start_col, end_col)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_add_highlight(buf, prompt_ns, group, line, start_col, end_col)
end

---Verify that keyword boundaries are surrounded by non-word characters.
---@param text string Full line text.
---@param s number Start index (1-based).
---@param e number End index (1-based, exclusive).
---@return boolean ok True when the match is isolated.
local function boundaries_ok(text, s, e)
  local before_ok = s == 1 or text:sub(s - 1, s - 1):match("%W")
  local after_ok = e > #text or text:sub(e, e):match("%W")
  return before_ok and after_ok
end

---Highlight syntax tokens within a single JQL line.
---@param buf number Buffer handle.
---@param line string Line text to highlight.
---@param line_nr number 0-based line index.
---@param autocomplete table|nil Autocomplete data to highlight fields.
---@return nil
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

---Highlight every line in the prompt buffer.
---@param buf number Buffer handle.
---@param autocomplete table|nil Autocomplete payload for field highlights.
---@return nil
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

---Apply stored shortcut highlight markers to a buffer.
---@param buf number Buffer handle.
---@param highlights table Highlight descriptors with group and ranges.
---@return nil
local function apply_shortcut_highlights(buf, highlights)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, shortcut_ns, 0, -1)
  for _, mark in ipairs(highlights or {}) do
    vim.api.nvim_buf_add_highlight(buf, shortcut_ns, mark.group, mark.line, mark.start_col, mark.end_col)
  end
end

---Escape characters for safe statusline/winbar display.
---@param text string|nil Text to escape.
---@return string escaped Escaped text.
local function escape_status_component(text)
  return (text or ""):gsub("%%", "%%%%")
end

---Render contextual help text in the prompt window bar.
---@param state table Prompt state object.
---@param text string|nil Help message.
---@return nil
local function set_help(state, text)
  if not state or not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(state.buf, hint_ns, 0, -1)
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then
    return
  end
  local winbar = ""
  if text and text ~= "" then
    winbar = table.concat({ "%#Comment# ", escape_status_component(text), " %*" })
  end
  vim.api.nvim_win_set_option(state.win, "winbar", winbar)
  vim.api.nvim_win_set_option(state.win, "statusline", "")
end

---Compute dimensions for the prompt windows based on editor size and defaults.
---@param config table|nil Plugin configuration.
---@param default_value string|nil Initial query text.
---@return table dims Width/height/position/border settings.
local function build_dimensions(config, default_value)
  local width = math.min(math.max(50, math.floor(vim.o.columns * 0.65)), vim.o.columns - 2)
  local min_height = 6
  local max_height = math.max(min_height, math.floor(vim.o.lines * 0.5))
  local default_lines = 1
  if default_value and default_value ~= "" then
    default_lines = #vim.split(default_value, "\n", { trimempty = false })
  end
  local desired = math.min(max_height, math.max(min_height, default_lines + 4))
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

---Close the prompt windows and cleanup timers/autocmds.
---@param state table Prompt state object.
---@return nil
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
  if state.bar_win and vim.api.nvim_win_is_valid(state.bar_win) then
    pcall(vim.api.nvim_win_close, state.bar_win, true)
  end
  if state.container_win and vim.api.nvim_win_is_valid(state.container_win) then
    pcall(vim.api.nvim_win_close, state.container_win, true)
  end
  if buf_valid then
    pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
  end
  if state.bar_buf and vim.api.nvim_buf_is_valid(state.bar_buf) then
    pcall(vim.api.nvim_buf_delete, state.bar_buf, { force = true })
  end
  if state.container_buf and vim.api.nvim_buf_is_valid(state.container_buf) then
    pcall(vim.api.nvim_buf_delete, state.container_buf, { force = true })
  end
  state.buf = nil
  state.win = nil
  state.bar_buf = nil
  state.bar_win = nil
  state.container_buf = nil
  state.container_win = nil
end

---Parse a Jira autocomplete response into a list of suggestion strings.
---@param resp table|string[]|nil Raw suggestion response.
---@return string[] items Suggestion text entries.
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

---Feed completion candidates into Vim's completion with a prefix.
---@param state table Prompt state.
---@param prefix string Text already typed by the user.
---@param items string[] Completion entries.
---@return nil
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

---Detect the field/value context around the cursor for suggestions.
---@param line string Current line text.
---@param col number 1-based column position.
---@return string|nil field Field name when found.
---@return string|nil prefix Current partial value being typed.
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

---Request or reuse JQL value suggestions based on cursor context.
---@param state table Prompt state.
---@param line string Current cursor line text.
---@return nil
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

---Offer field name completions when typing a predicate.
---@param state table Prompt state.
---@param line string Current line text.
---@return nil
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

---Attach listeners for highlighting, completion, and lifecycle events.
---@param state table Prompt state.
---@param on_submit fun(query:string) Called when the user submits the query.
---@param on_change fun(text:string)|nil Called as text changes.
---@param help_text string|nil Help message to display.
---@return nil
local function attach_listeners(state, on_submit, on_change, help_text)
  vim.api.nvim_clear_autocmds({ group = completion_group, buffer = state.buf })
  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    group = completion_group,
    buffer = state.buf,
    callback = function()
      local cursor_line = line_at_cursor(state.buf, state.win)
      highlight_buffer(state.buf, state.autocomplete)
      if help_text then
        set_help(state, help_text)
      end
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
  local function open_help_popup()
    popup.show_help(state.config)
  end
  vim.keymap.set("n", "<CR>", submit_query, key_opts)
  vim.keymap.set({ "i", "n" }, "<C-y>", submit_query, key_opts)
  vim.keymap.set({ "i", "n" }, "<C-c>", function()
    close_prompt(state)
  end, key_opts)
  vim.keymap.set("n", "q", function()
    close_prompt(state)
  end, key_opts)
  vim.keymap.set({ "i", "n" }, "?", open_help_popup, key_opts)
end

---Fetch autocomplete metadata for fields/functions/keywords.
---@param state table Prompt state.
---@return nil
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

---Open an interactive floating window to collect a JQL query with autocomplete.
---@param opts table|nil Options such as default text, callbacks, and plugin config.
---@return boolean opened True when the prompt was successfully created.
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

  popup.ensure_highlights()

  ensure_highlights()

  local buf = vim.api.nvim_create_buf(false, true)
  if not buf then
    return false
  end
  local dims = build_dimensions(config, default_value)
  local bar_lines, bar_highlights = popup.shortcut_bar_lines("jql", dims.width)
  local bar_height = math.max(1, #bar_lines)
  local content_height = math.max(3, dims.height - bar_height)

  local container_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[container_buf].bufhidden = "wipe"
  vim.bo[container_buf].modifiable = false
  vim.bo[container_buf].filetype = "jira_popup_container"

  local ok, container_win = pcall(vim.api.nvim_open_win, container_buf, false, {
    relative = "editor",
    width = dims.width,
    height = dims.height,
    col = dims.col,
    row = dims.row,
    style = "minimal",
    border = dims.border,
    title = "JQL Search",
    title_pos = "center",
    focusable = false,
  })
  if not ok or not container_win then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    pcall(vim.api.nvim_buf_delete, container_buf, { force = true })
    return false
  end

  local ok_content, win = pcall(vim.api.nvim_open_win, buf, true, {
    relative = "win",
    win = container_win,
    width = dims.width,
    height = content_height,
    col = 0,
    row = 0,
    style = "minimal",
    border = "none",
  })
  if not ok_content or not win then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    close_prompt({ win = container_win, buf = container_buf })
    return false
  end
  vim.api.nvim_win_set_option(win, "wrap", true)
  vim.api.nvim_win_set_option(win, "winhl", "Normal:JiraPopupDetailsBody,FloatBorder:JiraPopupDetailsHeader")

  local bar_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[bar_buf].bufhidden = "wipe"
  vim.bo[bar_buf].modifiable = true
  vim.api.nvim_buf_set_lines(bar_buf, 0, -1, false, bar_lines)
  vim.bo[bar_buf].modifiable = false
  apply_shortcut_highlights(bar_buf, bar_highlights)
  local bar_win = vim.api.nvim_open_win(bar_buf, false, {
    relative = "win",
    win = container_win,
    width = dims.width,
    height = bar_height,
    col = 0,
    row = content_height,
    style = "minimal",
    border = "none",
    focusable = false,
  })
  vim.api.nvim_win_set_option(bar_win, "winhl", "Normal:JiraPopupUrlBar,NormalNC:JiraPopupUrlBar")
  vim.api.nvim_win_set_option(bar_win, "wrap", true)
  pcall(vim.api.nvim_win_set_option, container_win, "winfixheight", true)
  pcall(vim.api.nvim_win_set_option, container_win, "winfixwidth", true)
  pcall(vim.api.nvim_win_set_option, win, "winfixheight", true)
  pcall(vim.api.nvim_win_set_option, win, "winfixwidth", true)
  pcall(vim.api.nvim_win_set_option, bar_win, "winfixheight", true)
  pcall(vim.api.nvim_win_set_option, bar_win, "winfixwidth", true)

  local initial_lines = vim.split(default_value, "\n", { trimempty = false })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial_lines)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].buflisted = false
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].filetype = "jira_jql"

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
    help_text = help_text,
    container_win = container_win,
    container_buf = container_buf,
    bar_win = bar_win,
    bar_buf = bar_buf,
  }

  set_help(state, help_text)
  fetch_autocomplete(state)
  highlight_buffer(buf, state.autocomplete)
  attach_listeners(state, on_submit, on_change, help_text)
  vim.cmd("startinsert")
  return true
end

return JQLPrompt

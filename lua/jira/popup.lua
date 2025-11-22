local utils = require("jira.utils")

local Popup = {}

local popup_ns = vim.api.nvim_create_namespace("jira.nvim.popup")
local list_ns = vim.api.nvim_create_namespace("jira.nvim.popup.list")
local popup_highlights_ready = false
local nav_hint = "Nav: j/k scroll • gg top • G bottom • Tab/S-Tab switch panes • / search (n/N repeat) • <C-n>/<C-p> next/prev issue • Enter/Cmd/Ctrl+Click open URL • q/Esc close • o open URL"
local format_issue_url
local user_highlight_cache = {}
local user_highlight_counter = 0
local catppuccin = {
  base = "#1e1e2e",
  mantle = "#181825",
  crust = "#11111b",
  surface0 = "#313244",
  surface1 = "#45475a",
  surface2 = "#585b70",
  overlay0 = "#6c7086",
  overlay1 = "#7f849c",
  overlay2 = "#9399b2",
  subtext0 = "#a6adc8",
  subtext1 = "#bac2de",
  text = "#cdd6f4",
  lavender = "#b4befe",
  blue = "#89b4fa",
  sky = "#89dceb",
  teal = "#94e2d5",
  green = "#a6e3a1",
  yellow = "#f9e2af",
  peach = "#fab387",
  maroon = "#eba0ac",
  red = "#f38ba8",
  mauve = "#cba6f7",
  pink = "#f5c2e7",
  rosewater = "#f5e0dc",
}
local user_palette = {
  catppuccin.blue,
  catppuccin.teal,
  catppuccin.green,
  catppuccin.peach,
  catppuccin.sky,
  catppuccin.mauve,
  catppuccin.pink,
  catppuccin.yellow,
}
local priority_colors = {
  catppuccin.red,
  catppuccin.peach,
  catppuccin.yellow,
  catppuccin.green,
}
local severity_colors = {
  catppuccin.maroon,
  catppuccin.peach,
  catppuccin.yellow,
  catppuccin.sky,
}
local priority_rules = {
  { level = 1, keywords = { "p0", "blocker", "critical", "highest" } },
  { level = 2, keywords = { "p1", "high" } },
  { level = 3, keywords = { "p2", "medium", "major" } },
  { level = 4, keywords = { "p3", "low", "minor", "lowest" } },
}
local severity_rules = {
  { level = 1, keywords = { "sev0", "sev-0", "critical", "blocker" } },
  { level = 2, keywords = { "sev1", "sev-1", "high", "major" } },
  { level = 3, keywords = { "sev2", "sev-2", "medium" } },
  { level = 4, keywords = { "sev3", "sev-3", "low", "minor", "trivial" } },
}

local function ensure_popup_highlights()
  if popup_highlights_ready then
    return
  end
  vim.api.nvim_set_hl(0, "JiraPopupKey", {
    default = true,
    fg = catppuccin.peach,
    bold = true,
  })
  vim.api.nvim_set_hl(0, "JiraPopupUser", {
    default = true,
    fg = catppuccin.green,
    bold = true,
  })
  vim.api.nvim_set_hl(0, "JiraPopupLink", {
    default = true,
    underline = true,
    fg = catppuccin.sky,
  })
  vim.api.nvim_set_hl(0, "JiraPopupLabel", {
    default = true,
    fg = catppuccin.teal,
    bold = true,
  })
  vim.api.nvim_set_hl(0, "JiraPopupTitle", {
    default = true,
    fg = catppuccin.rosewater,
    bg = catppuccin.surface1,
    bold = true,
  })
  vim.api.nvim_set_hl(0, "JiraPopupSection", {
    default = true,
    fg = catppuccin.mauve,
    bold = true,
  })
  vim.api.nvim_set_hl(0, "JiraPopupDescription", {
    default = true,
    fg = catppuccin.subtext1,
  })
  vim.api.nvim_set_hl(0, "JiraPopupCommentHeader", {
    default = true,
    fg = catppuccin.sky,
    bold = true,
  })
  vim.api.nvim_set_hl(0, "JiraPopupCommentBody", {
    default = true,
    fg = catppuccin.subtext0,
  })
  vim.api.nvim_set_hl(0, "JiraPopupChangesHeader", {
    default = true,
    fg = catppuccin.peach,
    bold = true,
  })
  vim.api.nvim_set_hl(0, "JiraPopupChangesBody", {
    default = true,
    fg = catppuccin.yellow,
  })
  vim.api.nvim_set_hl(0, "JiraPopupTimestamp", {
    default = true,
    fg = catppuccin.yellow,
    bold = true,
  })
  vim.api.nvim_set_hl(0, "JiraPopupVersion", {
    default = true,
    fg = catppuccin.teal,
    bold = true,
  })
  vim.api.nvim_set_hl(0, "JiraPopupDetailsHeader", {
    default = true,
    fg = catppuccin.sky,
    bg = catppuccin.surface0,
    bold = true,
  })
  vim.api.nvim_set_hl(0, "JiraPopupDetailsBody", {
    default = true,
    fg = catppuccin.subtext0,
    bg = catppuccin.surface0,
  })
  vim.api.nvim_set_hl(0, "JiraPopupStatusline", {
    default = true,
    fg = catppuccin.text,
    bg = catppuccin.surface2,
    bold = true,
  })
  vim.api.nvim_set_hl(0, "JiraPopupTitleBar", {
    default = true,
    fg = catppuccin.lavender,
    bg = "NONE",
    bold = true,
  })
  vim.api.nvim_set_hl(0, "JiraPopupUserInactive", {
    default = true,
    fg = catppuccin.overlay1,
    bold = true,
  })
  vim.api.nvim_set_hl(0, "JiraPopupUrlBar", {
    default = true,
    fg = catppuccin.text,
    bg = catppuccin.surface1,
    bold = true,
  })
  vim.api.nvim_set_hl(0, "JiraPopupSummaryBackground", {
    default = true,
    fg = catppuccin.text,
    bg = catppuccin.surface1,
  })
  vim.api.nvim_set_hl(0, "JiraPopupOpenIndicator", {
    default = true,
    fg = catppuccin.yellow,
    bold = true,
  })
  vim.api.nvim_set_hl(0, "JiraPopupListTitle", {
    default = true,
    fg = catppuccin.rosewater,
    bold = true,
  })
  vim.api.nvim_set_hl(0, "JiraPopupListHeader", {
    default = true,
    fg = catppuccin.sky,
    bold = true,
  })
  vim.api.nvim_set_hl(0, "JiraPopupListSelection", {
    default = true,
    fg = catppuccin.text,
    bg = catppuccin.surface2,
    bold = true,
  })
  vim.api.nvim_set_hl(0, "JiraPopupListEmpty", {
    default = true,
    fg = catppuccin.overlay1,
  })
  for level, color in ipairs(priority_colors) do
    vim.api.nvim_set_hl(0, string.format("JiraPopupPriorityLevel%d", level), {
      default = true,
      fg = color,
      bold = true,
    })
  end
  for level, color in ipairs(severity_colors) do
    vim.api.nvim_set_hl(0, string.format("JiraPopupSeverityLevel%d", level), {
      default = true,
      fg = color,
      bold = true,
    })
  end
  popup_highlights_ready = true
end

local function add_highlight_entry(store, group, line, start_col, end_col)
  if not store or not group then
    return
  end
  if line == nil or start_col == nil or end_col == nil then
    return
  end
  if end_col <= start_col then
    return
  end
  table.insert(store, {
    group = group,
    line = line,
    start_col = start_col,
    end_col = end_col,
  })
end

local function highlight_label_portion(store, line, label)
  if not store or not label or label == "" then
    return
  end
  add_highlight_entry(store, "JiraPopupLabel", line, 0, #label + 1)
end

local function highlight_full_line(store, group, line, text)
  if not store or not group or not text or text == "" then
    return
  end
  add_highlight_entry(store, group, line, 0, #text)
end

local function append_section(target_lines, target_highlights, section_lines, section_highlights)
  if not section_lines or #section_lines == 0 then
    return
  end
  local offset = #target_lines
  for _, line in ipairs(section_lines) do
    table.insert(target_lines, line)
  end
  if not section_highlights then
    return
  end
  for _, mark in ipairs(section_highlights) do
    add_highlight_entry(target_highlights, mark.group, (mark.line or 0) + offset, mark.start_col, mark.end_col)
  end
end

local function user_display_and_status(user)
  if vim and vim.NIL and user == vim.NIL then
    return nil, false
  end
  if not user or type(user) ~= "table" then
    return nil, false
  end
  local base = user.displayName or user.name or user.emailAddress
  if base and type(base) ~= "string" then
    base = tostring(base)
  end
  if not base or base == "" then
    return nil, false
  end
  local inactive = false
  if user.active == false then
    inactive = true
  end
  local status = user.accountStatus
  if type(status) == "string" and status:lower():find("inactive") then
    inactive = true
  end
  if inactive then
    base = base .. " X"
  end
  return base, inactive
end

local function next_user_color()
  local color = user_palette[(user_highlight_counter % #user_palette) + 1]
  user_highlight_counter = user_highlight_counter + 1
  return color
end

local function highlight_group_for_user(name, inactive)
  if not name or name == "" or name == "-" then
    return nil
  end
  ensure_popup_highlights()
  if inactive then
    return "JiraPopupUserInactive"
  end
  if user_highlight_cache[name] then
    return user_highlight_cache[name]
  end
  local color = next_user_color()
  local group = string.format("JiraPopupUserColor%d", user_highlight_counter)
  vim.api.nvim_set_hl(0, group, {
    default = true,
    fg = color,
    bold = true,
  })
  user_highlight_cache[name] = group
  return group
end

local function determine_level(value, rules, default_level)
  if not value or value == "" then
    return default_level
  end
  local lower = value:lower()
  for _, rule in ipairs(rules) do
    for _, keyword in ipairs(rule.keywords or {}) do
      if lower:find(keyword, 1, true) then
        return rule.level
      end
    end
  end
  return default_level
end

local function priority_highlight_group(value)
  if not value or value == "-" then
    return nil
  end
  ensure_popup_highlights()
  local level = determine_level(value, priority_rules, #priority_colors) or #priority_colors
  level = math.max(1, math.min(level, #priority_colors))
  return string.format("JiraPopupPriorityLevel%d", level)
end

local function severity_highlight_group(value)
  if not value or value == "-" then
    return nil
  end
  ensure_popup_highlights()
  local level = determine_level(value, severity_rules, #severity_colors) or #severity_colors
  level = math.max(1, math.min(level, #severity_colors))
  return string.format("JiraPopupSeverityLevel%d", level)
end

local function escape_statusline_text(text)
  return (text or ""):gsub("%%", "%%%%")
end

local function build_statusline_text(status_text)
  ensure_popup_highlights()
  local status_display = status_text
  if not status_display or status_display == "" then
    status_display = "--"
  end
  local components = {
    "%#JiraPopupStatusline# ",
    string.format("Status: %s", escape_statusline_text(status_display)),
    " %*",
  }
  return table.concat(components)
end

local function apply_statusline(win, status_text)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end
  vim.api.nvim_win_set_option(win, "statusline", build_statusline_text(status_text))
end

local function add_buffer_highlight(buf, group, line, start_col, end_col)
  if not group then
    return
  end
  if line == nil or start_col == nil or end_col == nil then
    return
  end
  if end_col <= start_col then
    return
  end
  pcall(vim.api.nvim_buf_add_highlight, buf, popup_ns, group, line, start_col, end_col)
end

local function should_ignore_issue_key(issue_key, ignored_projects)
  if not issue_key or issue_key == "" then
    return false
  end
  if not ignored_projects then
    return false
  end
  local project = issue_key:match("^([%a%d]+)%-%d+$")
  if not project then
    return false
  end
  return ignored_projects[project:upper()] == true
end

local function add_issue_key_highlights(buf, lines, pattern, ignored_projects)
  pattern = pattern or "%u+-%d+"
  if not lines or pattern == "" then
    return
  end
  for idx, line in ipairs(lines) do
    local start = 1
    while true do
      local s, e = line:find(pattern, start)
      if not s then
        break
      end
      local issue_key = line:sub(s, e)
      if not should_ignore_issue_key(issue_key, ignored_projects) then
        add_buffer_highlight(buf, "JiraPopupKey", idx - 1, s - 1, e)
      end
      start = e + 1
    end
  end
end

local function sanitize_url_match(url)
  if not url or url == "" then
    return ""
  end
  local sanitized = url:gsub("[\"'`]+$", "")
  local pairs = {
    { "(", ")" },
    { "[", "]" },
    { "{", "}" },
    { "<", ">" },
  }
  for _, pair in ipairs(pairs) do
    local open_char, close_char = pair[1], pair[2]
    local function count_char(str, char)
      local _, count = str:gsub("%" .. char, "")
      return count
    end
    while sanitized:sub(-1) == close_char and count_char(sanitized, close_char) > count_char(sanitized, open_char) do
      sanitized = sanitized:sub(1, -2)
    end
  end
  return sanitized
end

local function add_link_highlights(buf, lines)
  if not lines then
    return
  end
  for idx, line in ipairs(lines) do
    local start = 1
    while true do
      local s, e = line:find("https?://%S+", start)
      if not s then
        break
      end
      local sanitized = sanitize_url_match(line:sub(s, e))
      if sanitized and sanitized ~= "" then
        add_buffer_highlight(buf, "JiraPopupLink", idx - 1, s - 1, s - 1 + #sanitized)
      end
      start = e + 1
    end
  end
end

local function cursor_for_buffer(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return nil, nil
  end
  local mouse_win = vim.v.mouse_win
  if mouse_win and mouse_win ~= 0 and vim.api.nvim_win_is_valid(mouse_win) and vim.api.nvim_win_get_buf(mouse_win) == buf then
    local mouse_line = tonumber(vim.v.mouse_lnum)
    local mouse_col = tonumber(vim.v.mouse_col)
    if mouse_line and mouse_col then
      return mouse_win, { mouse_line, math.max(0, mouse_col - 1) }
    end
  end
  local win = vim.api.nvim_get_current_win()
  if not win or not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= buf then
    win = vim.fn.bufwinid(buf)
  end
  if not win or win == -1 or not vim.api.nvim_win_is_valid(win) then
    return nil, nil
  end
  return win, vim.api.nvim_win_get_cursor(win)
end

local function find_url_under_cursor(buf, cursor)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return nil
  end
  if not cursor then
    return nil
  end
  local line = vim.api.nvim_buf_get_lines(buf, cursor[1] - 1, cursor[1], false)[1] or ""
  if line == "" then
    return nil
  end
  local col = cursor[2] + 1
  local first_url = nil
  local start = 1
  while true do
    local s, e = line:find("https?://%S+", start)
    if not s then
      break
    end
    local sanitized = sanitize_url_match(line:sub(s, e))
    if sanitized and sanitized ~= "" then
      if not first_url then
        first_url = sanitized
      end
      if col >= s and col <= e then
        return sanitized
      end
    end
    start = e + 1
  end
  if first_url then
    return first_url
  end
  return nil
end
local function find_issue_key_under_cursor(buf, pattern, ignored_projects, cursor)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return nil
  end
  if not cursor then
    return nil
  end
  local line = vim.api.nvim_buf_get_lines(buf, cursor[1] - 1, cursor[1], false)[1] or ""
  if line == "" then
    return nil
  end
  if not pattern or pattern == "" then
    return nil
  end
  pattern = pattern or "%u+-%d+"
  local col = cursor[2] + 1
  local first_match = nil
  local start = 1
  while true do
    local s, e = line:find(pattern, start)
    if not s then
      break
    end
    local key = line:sub(s, e)
    if not should_ignore_issue_key(key, ignored_projects) then
      if not first_match then
        first_match = key
      end
      if col >= s and col <= e then
        return key
      end
    end
    start = e + 1
  end
  return first_match
end

local function log_popup_event(event, payload)
  local ok_path, path = pcall(function()
    local info = debug.getinfo(1, "S")
    if info and info.source and info.source:sub(1, 1) == "@" then
      local script = info.source:sub(2)
      if script and script ~= "" then
        local root = vim.fn.fnamemodify(script, ":p:h:h:h")
        if root ~= "" then
          return root .. "/api_access.log"
        end
      end
    end
    return vim.fn.stdpath("cache") .. "/jira.nvim/api_access.log"
  end)
  if not ok_path or not path or path == "" then
    return
  end
  local dir = vim.fn.fnamemodify(path, ":p:h")
  if dir ~= "" then
    pcall(vim.fn.mkdir, dir, "p")
  end
  local details = payload
  if type(payload) == "table" then
    local ok_inspect, inspected = pcall(vim.inspect, payload)
    details = ok_inspect and inspected or tostring(payload)
  elseif payload == nil then
    details = ""
  else
    details = tostring(payload)
  end
  local ok_file, file = pcall(io.open, path, "a")
  if not ok_file or not file then
    return
  end
  file:write(string.format("[%s] %s: %s\n", os.date("%Y-%m-%d %H:%M:%S"), event, details))
  file:close()
end

local function open_url_under_cursor(buf, config, trigger)
  local _, cursor = cursor_for_buffer(buf)
  if not cursor then
    log_popup_event("OPEN_LINK_TRIGGER", {
      trigger = trigger or "unknown",
      buffer = buf,
      cursor = cursor,
      reason = "no_cursor",
    })
    return false
  end
  log_popup_event("OPEN_LINK_TRIGGER", {
    trigger = trigger or "unknown",
    buffer = buf,
    cursor = cursor,
  })
  local url = find_url_under_cursor(buf, cursor)
  if url and url ~= "" then
    utils.open_url(url)
    log_popup_event("OPEN_LINK_RESULT", {
      trigger = trigger or "unknown",
      buffer = buf,
      cursor = cursor,
      kind = "url",
      value = url,
      opened = true,
    })
    return true
  end
  local issue_key = find_issue_key_under_cursor(
    buf,
    config and config.issue_pattern,
    config and config._ignored_project_map,
    cursor
  )
  if issue_key and issue_key ~= "" then
    local issue_url = format_issue_url and format_issue_url(issue_key, config) or ""
    if issue_url == "" then
      vim.notify("jira.nvim: Jira base URL is not configured; cannot open browser", vim.log.levels.WARN)
      log_popup_event("OPEN_LINK_RESULT", {
        trigger = trigger or "unknown",
        buffer = buf,
        cursor = cursor,
        kind = "issue",
        value = issue_key,
        opened = false,
        reason = "missing_base_url",
      })
      return false
    end
    utils.open_url(issue_url)
    log_popup_event("OPEN_LINK_RESULT", {
      trigger = trigger or "unknown",
      buffer = buf,
      cursor = cursor,
      kind = "issue",
      value = issue_key,
      opened = true,
    })
    return true
  end
  log_popup_event("OPEN_LINK_RESULT", {
    trigger = trigger or "unknown",
    buffer = buf,
    cursor = cursor,
    opened = false,
    reason = "no_match",
  })
  return false
end

local function apply_highlights(buf, lines, highlights, issue_pattern, ignored_projects)
  ensure_popup_highlights()
  vim.api.nvim_buf_clear_namespace(buf, popup_ns, 0, -1)
  if highlights then
    for _, mark in ipairs(highlights) do
      add_buffer_highlight(buf, mark.group, mark.line, mark.start_col, mark.end_col)
    end
  end
  add_issue_key_highlights(buf, lines, issue_pattern, ignored_projects)
  add_link_highlights(buf, lines)
end

local focus_group = vim.api.nvim_create_augroup("JiraPopupGuard", { clear = true })
local size_group = vim.api.nvim_create_augroup("JiraPopupSizeGuard", { clear = true })
local list_group = vim.api.nvim_create_augroup("JiraPopupList", { clear = true })
local yank_group = vim.api.nvim_create_augroup("JiraPopupYankFeedback", { clear = true })

local state = {
  container_win = nil,
  main_win = nil,
  sidebar_win = nil,
  summary_win = nil,
  url_win = nil,
  help_win = nil,
  buffers = {},
  allowed_wins = {},
  focus_autocmd = nil,
  size_autocmd = nil,
  last_focus = nil,
  navigation = nil,
  return_focus = nil,
  search = nil,
  dimensions = nil,
}

local list_state = {
  win = nil,
  buf = nil,
  issues = {},
  selection = nil,
  data_offset = 0,
  autocmd = nil,
  on_select = nil,
  pagination = nil,
  page_handlers = nil,
  close_on_select = false,
  title = nil,
  source = nil,
  search_active = false,
  selection_before_search = nil,
}

local function clear_list_autocmd()
  if list_state.autocmd then
    pcall(vim.api.nvim_del_autocmd, list_state.autocmd)
    list_state.autocmd = nil
  end
end

local function close_issue_list()
  clear_list_autocmd()
  if list_state.win and vim.api.nvim_win_is_valid(list_state.win) then
    pcall(vim.api.nvim_win_close, list_state.win, true)
  end
  if list_state.buf and vim.api.nvim_buf_is_valid(list_state.buf) then
    pcall(vim.api.nvim_buf_delete, list_state.buf, { force = true })
  end
  list_state = {
    win = nil,
    buf = nil,
    issues = {},
    selection = nil,
    data_offset = 0,
    autocmd = nil,
    on_select = nil,
    pagination = nil,
    page_handlers = nil,
    close_on_select = false,
    title = nil,
    source = nil,
    search_active = false,
    selection_before_search = nil,
  }
end

local function refresh_issue_list_selection()
  if not list_state.buf or not vim.api.nvim_buf_is_valid(list_state.buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(list_state.buf, list_ns, 0, -1)
  local issues = list_state.issues or {}
  if not list_state.selection or #issues == 0 then
    return
  end
  if list_state.selection < 1 then
    list_state.selection = 1
  elseif list_state.selection > #issues then
    list_state.selection = #issues
  end
  local target_line = list_state.data_offset + list_state.selection - 1
  vim.api.nvim_buf_add_highlight(list_state.buf, list_ns, "JiraPopupListSelection", target_line, 0, -1)
  if list_state.win and vim.api.nvim_win_is_valid(list_state.win) then
    vim.api.nvim_win_set_cursor(list_state.win, { target_line + 1, 0 })
  end
end

local function list_row_from_cursor()
  if not list_state.win or not vim.api.nvim_win_is_valid(list_state.win) then
    return nil
  end
  local cursor = vim.api.nvim_win_get_cursor(list_state.win)
  local line = cursor[1]
  local idx = line - list_state.data_offset
  if idx < 1 or idx > #(list_state.issues or {}) then
    return nil
  end
  return idx
end

local function sync_list_selection_to_cursor()
  local idx = list_row_from_cursor()
  if not idx then
    return
  end
  if list_state.selection ~= idx then
    list_state.selection = idx
    refresh_issue_list_selection()
  end
end

local function restore_selection_before_search()
  if not list_state.selection_before_search then
    return
  end
  list_state.selection = list_state.selection_before_search
  list_state.selection_before_search = nil
  refresh_issue_list_selection()
end

local function move_issue_list_selection(delta)
  if not list_state.selection or not list_state.issues or #list_state.issues == 0 then
    return
  end
  list_state.selection = math.min(#list_state.issues, math.max(1, list_state.selection + delta))
  refresh_issue_list_selection()
end

local function list_selection_context()
  if not list_state.win or not vim.api.nvim_win_is_valid(list_state.win) then
    return nil
  end
  return {
    win = list_state.win,
    title = list_state.title,
    source = list_state.source,
    selection = list_state.selection,
    pagination = list_state.pagination,
  }
end

local function goto_issue_list_page(delta)
  local handlers = list_state.page_handlers or {}
  if delta > 0 and handlers.next_page then
    handlers.next_page()
  elseif delta < 0 and handlers.prev_page then
    handlers.prev_page()
  end
end

local function activate_current_issue()
  if not list_state.on_select or not list_state.selection or not list_state.issues then
    return
  end
  local issue = list_state.issues[list_state.selection]
  if not issue or not issue.key then
    return
  end
  local handler = list_state.on_select
  local context = list_selection_context()
  if list_state.close_on_select then
    close_issue_list()
  end
  handler(issue, context)
end

local function valid_win(win)
  return win ~= nil and vim.api.nvim_win_is_valid(win)
end

local function update_allowed_wins()
  local allowed = {}
  for _, win in ipairs({ state.main_win, state.sidebar_win, state.summary_win, state.url_win, state.help_win }) do
    if valid_win(win) then
      local ok, cfg = pcall(vim.api.nvim_win_get_config, win)
      if win ~= state.help_win or not (ok and cfg and cfg.focusable == false) then
        table.insert(allowed, win)
      end
    end
  end
  state.allowed_wins = allowed
end

local function clear_focus_guard()
  if state.focus_autocmd then
    pcall(vim.api.nvim_del_autocmd, state.focus_autocmd)
    state.focus_autocmd = nil
  end
end

local function is_allowed_win(win)
  for _, allowed in ipairs(state.allowed_wins or {}) do
    if allowed == win then
      return true
    end
  end
  return false
end

local function activate_focus_guard()
  clear_focus_guard()
  state.focus_autocmd = vim.api.nvim_create_autocmd("WinEnter", {
    group = focus_group,
    callback = function(args)
      if not valid_win(state.container_win) then
        return
      end
      if is_allowed_win(args.win) then
        state.last_focus = args.win
        return
      end
      if state.last_focus and valid_win(state.last_focus) then
        vim.schedule(function()
          if state.last_focus and valid_win(state.last_focus) then
            vim.api.nvim_set_current_win(state.last_focus)
          end
        end)
      end
    end,
  })
end

local function clear_size_guard()
  if state.size_autocmd then
    pcall(vim.api.nvim_del_autocmd, state.size_autocmd)
    state.size_autocmd = nil
  end
end
local function clone_dimension_value(value)
  if type(value) == "table" then
    return vim.deepcopy(value)
  end
  return value
end
local function record_window_dimensions(win)
  if not valid_win(win) then
    return nil
  end
  local ok, cfg = pcall(vim.api.nvim_win_get_config, win)
  if not ok or not cfg then
    return nil
  end
  return {
    width = cfg.width,
    height = cfg.height,
    row = clone_dimension_value(cfg.row),
    col = clone_dimension_value(cfg.col),
    relative = cfg.relative,
    win = cfg.win,
  }
end

local function enforce_window_dimensions(win, target)
  if not target or not valid_win(win) then
    return
  end
  local ok, cfg = pcall(vim.api.nvim_win_get_config, win)
  if not ok or not cfg then
    return
  end
  local updated = vim.deepcopy(cfg)
  local changed = false
  for _, key in ipairs({ "width", "height", "row", "col", "relative", "win" }) do
    local desired = target[key]
    if desired ~= nil and not vim.deep_equal(updated[key], desired) then
      updated[key] = vim.deepcopy(desired)
      changed = true
    end
  end
  if changed then
    pcall(vim.api.nvim_win_set_config, win, updated)
  end
end

local function restore_window_dimensions()
  if not state.dimensions then
    return
  end
  for win, target in pairs(state.dimensions) do
    enforce_window_dimensions(win, target)
  end
end

local function activate_size_guard()
  clear_size_guard()
  if not state.dimensions then
    return
  end
  state.size_autocmd = vim.api.nvim_create_autocmd({ "WinResized", "WinEnter" }, {
    group = size_group,
    callback = function(args)
      if not valid_win(state.container_win) then
        return
      end
      if args and args.win and state.dimensions[args.win] then
        enforce_window_dimensions(args.win, state.dimensions[args.win])
      else
        restore_window_dimensions()
      end
    end,
  })
  restore_window_dimensions()
end

local function normalized_base_url(config)
  if config and config.api and config.api.base_url and config.api.base_url ~= "" then
    return (config.api.base_url or ""):gsub("/*$", "")
  end
  return (vim.env.JIRA_BASE_URL or ""):gsub("/*$", "")
end

format_issue_url = function(issue_key, config)
  if not issue_key or issue_key == "" then
    return ""
  end
  local base = normalized_base_url(config)
  if base == "" then
    return ""
  end
  return string.format("%s/browse/%s", base, issue_key)
end

local function popup_content_windows()
  local wins = {}
  for _, win in ipairs({ state.main_win, state.sidebar_win, state.summary_win, state.url_win, state.help_win }) do
    if valid_win(win) then
      local ok, cfg = pcall(vim.api.nvim_win_get_config, win)
      if win ~= state.help_win or not (ok and cfg and cfg.focusable == false) then
        table.insert(wins, win)
      end
    end
  end
  return wins
end

local function focus_window(win)
  if valid_win(win) then
    vim.api.nvim_set_current_win(win)
    state.last_focus = win
  end
end

local function lock_window_size(win)
  if not valid_win(win) then
    return
  end
  pcall(vim.api.nvim_win_set_option, win, "winfixwidth", true)
  pcall(vim.api.nvim_win_set_option, win, "winfixheight", true)
end

local function find_window_index(target, windows)
  for idx, win in ipairs(windows) do
    if win == target then
      return idx
    end
  end
  return nil
end

local function focus_next_popup_window(current_win)
  local wins = popup_content_windows()
  if #wins == 0 then
    return
  end
  local idx = find_window_index(current_win, wins) or 0
  local next_idx = (idx % #wins) + 1
  focus_window(wins[next_idx])
end

local function focus_previous_popup_window(current_win)
  local wins = popup_content_windows()
  if #wins == 0 then
    return
  end
  local idx = find_window_index(current_win, wins) or 1
  local prev_idx = ((idx - 2) % #wins) + 1
  focus_window(wins[prev_idx])
end

local function record_search_pattern(pattern)
  if not pattern or pattern == "" then
    state.search = nil
    return
  end
  state.search = { pattern = pattern }
  pcall(vim.fn.setreg, "/", pattern)
end

local function search_in_window(win, pattern, opts)
  opts = opts or {}
  if not valid_win(win) or not pattern or pattern == "" then
    return false
  end
  local original_win = vim.api.nvim_get_current_win()
  if original_win ~= win then
    vim.api.nvim_set_current_win(win)
  end
  local flags = "w"
  if opts.include_current ~= false then
    flags = "c" .. flags
  end
  if opts.backward then
    flags = flags .. "b"
  end
  local ok, result = pcall(vim.fn.search, pattern, flags)
  if not ok or result == 0 then
    if original_win ~= win then
      vim.api.nvim_set_current_win(original_win)
    end
    return false
  end
  state.last_focus = win
  return true
end

local function start_popup_search(start_win)
  vim.fn.inputsave()
  local ok, pattern = pcall(vim.fn.input, "/")
  vim.fn.inputrestore()
  if not ok or not pattern or pattern == "" then
    return
  end
  record_search_pattern(pattern)
  if not search_in_window(start_win, pattern, { include_current = true }) then
    vim.notify("jira.nvim: Pattern not found inside popup", vim.log.levels.INFO)
  end
end

local function repeat_popup_search(target_win, backward)
  local search_state = state.search
  if not search_state or not search_state.pattern or search_state.pattern == "" then
    vim.notify("jira.nvim: Start a search with / first", vim.log.levels.INFO)
    return
  end
  if not search_in_window(target_win, search_state.pattern, { include_current = false, backward = backward }) then
    vim.notify("jira.nvim: Pattern not found inside popup", vim.log.levels.INFO)
  end
end

local function close_window(win)
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end

local function wipe_buffer(buf)
  if buf and vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end
end

function Popup.close()
  clear_focus_guard()
  clear_size_guard()
  close_window(state.main_win)
  close_window(state.sidebar_win)
  close_window(state.summary_win)
  close_window(state.url_win)
  close_window(state.help_win)
  close_window(state.container_win)
  for _, buf in ipairs(state.buffers) do
    wipe_buffer(buf)
  end
  local return_focus = state.return_focus
  state = {
    container_win = nil,
    main_win = nil,
    sidebar_win = nil,
    summary_win = nil,
    url_win = nil,
    help_win = nil,
    buffers = {},
    allowed_wins = {},
    focus_autocmd = nil,
    size_autocmd = nil,
    last_focus = nil,
    navigation = nil,
    return_focus = nil,
    search = nil,
    dimensions = nil,
  }
  if return_focus and vim.api.nvim_win_is_valid(return_focus) then
    pcall(vim.api.nvim_set_current_win, return_focus)
  end
end

function Popup.close_all()
  Popup.close()
  close_issue_list()
end

local function calculate_dimensions(config)
  local columns = vim.o.columns
  local lines = vim.o.lines - vim.o.cmdheight
  local width = config.popup.width or 0.65
  local height = config.popup.height or 0.75

  if width <= 1 then
    width = math.floor(columns * width)
  end
  if height <= 1 then
    height = math.floor(lines * height)
  end

  width = math.max(60, math.min(width, columns - 4))
  height = math.max(20, math.min(height, lines - 4))

  local col = math.floor((columns - width) / 2)
  local row = math.floor((lines - height) / 2)

  return {
    width = width,
    height = height,
    col = col,
    row = row,
  }
end

local function list_dimensions(config, layout)
  local columns = vim.o.columns
  local lines = vim.o.lines - vim.o.cmdheight
  local dims_config = layout or (config and config.assigned_popup) or {}
  local width = dims_config.width or 0.55
  local height = dims_config.height or 0.5
  if width <= 1 then
    width = math.floor(columns * width)
  end
  if height <= 1 then
    height = math.floor(lines * height)
  end
  width = math.max(50, math.min(width, columns - 4))
  height = math.max(10, math.min(height, lines - 4))
  local col = math.floor((columns - width) / 2)
  local row = math.floor((lines - height) / 2)
  return {
    width = width,
    height = height,
    col = col,
    row = row,
  }
end

local function display_width(text)
  if vim and vim.fn and vim.fn.strdisplaywidth then
    local ok, width = pcall(vim.fn.strdisplaywidth, text)
    if ok then
      return width
    end
  end
  return #text
end

local function slice_by_width(text, max_width)
  if max_width <= 0 then
    return ""
  end
  if vim and vim.fn and vim.fn.strcharpart then
    local ok, chunk = pcall(vim.fn.strcharpart, text, 0, max_width)
    if ok then
      return chunk
    end
  end
  return text:sub(1, max_width)
end

local function truncate_cell(text, max_width)
  text = utils.trim(text or "")
  if text == "" then
    return "-"
  end
  if max_width <= 1 then
    return slice_by_width(text, 1)
  end
  local width = display_width(text)
  if width <= max_width then
    return text
  end
  local suffix = "…"
  local safe_width = math.max(1, max_width - 1)
  return slice_by_width(text, safe_width) .. suffix
end

local function format_issue_list_summary(pagination, issue_count)
  if not pagination then
    return string.format("%d issues", issue_count)
  end
  local total = tonumber(pagination.total)
  local page_size = tonumber(pagination.page_size or pagination.max_results or pagination.limit) or issue_count
  local explicit_page = tonumber(pagination.page)
  if explicit_page and explicit_page < 1 then
    explicit_page = 1
  end
  local explicit_total_pages = tonumber(pagination.total_pages)
  if explicit_total_pages and explicit_total_pages < 1 then
    explicit_total_pages = nil
  end
  local start_at = tonumber(pagination.start_at)
  if not start_at and explicit_page and page_size and page_size > 0 then
    start_at = (explicit_page - 1) * page_size
  end
  start_at = math.max(0, start_at or 0)
  if not total or total <= 0 then
    return string.format("%d issues", issue_count)
  end
  if issue_count <= 0 then
    return string.format("No results in this page (%d total)", total)
  end
  local first = math.min(total, start_at + 1)
  local last = math.min(total, start_at + issue_count)
  local summary = string.format("Showing %d-%d of %d", first, last, total)
  local page_label
  if explicit_page and explicit_total_pages then
    page_label = string.format("Page %d/%d", explicit_page, math.max(explicit_total_pages, explicit_page))
  elseif page_size and page_size > 0 and total > page_size then
    local page = math.floor(start_at / page_size) + 1
    local total_pages = math.floor((total + page_size - 1) / page_size)
    page_label = string.format("Page %d/%d", page, math.max(total_pages, 1))
  end
  if page_label then
    summary = string.format("%s • %s", summary, page_label)
  end
  return summary
end

local function build_issue_list_lines(issues, dims, opts)
  issues = issues or {}
  opts = opts or {}
  local title = opts.title or "Issues"
  local lines = {}
  local width = math.max(40, dims.width)
  local total_count = opts.pagination and tonumber(opts.pagination.total) or #issues
  local number_width = math.max(3, #tostring(math.max(total_count or 0, #issues)))
  local key_width = math.max(10, math.min(22, math.floor(width * 0.28)))
  local summary_width = math.max(20, width - key_width - number_width - 6)
  local format_string = "%-" .. number_width .. "s │ %-" .. key_width .. "s │ %s"
  table.insert(lines, title)
  local subtitle = opts.subtitle
  if not subtitle then
    subtitle = format_issue_list_summary(opts.pagination, #issues)
  end
  if subtitle and subtitle ~= "" then
    table.insert(lines, subtitle)
  else
    table.insert(lines, string.format("%d issues", #issues))
  end
  table.insert(lines, "")
  local title_line = 1
  local summary_line = 2
  local header_line = #lines + 1
  table.insert(lines, string.format(format_string, "#", "KEY", "SUMMARY"))
  local separator_line = #lines + 1
  table.insert(lines, string.rep("─", width))
  local data_offset = #lines
  local empty_line
  if #issues == 0 then
    empty_line = #lines + 1
    table.insert(lines, opts.empty_message or "No issues found.")
  else
    for idx, issue in ipairs(issues) do
      local key = truncate_cell(issue.key or "", key_width)
      local summary = truncate_cell(issue.summary or "", summary_width)
      table.insert(lines, string.format(format_string, tostring(idx), key, summary))
    end
  end
  return {
    lines = lines,
    title_line = title_line,
    summary_line = summary_line,
    header_line = header_line,
    separator_line = separator_line,
    data_offset = data_offset,
    empty_line = empty_line,
  }
end

local function version_list_display(values)
  if (vim and vim.NIL and values == vim.NIL) or not values then
    return ""
  end
  if type(values) == "string" then
    return values
  end
  if type(values) ~= "table" then
    return ""
  end
  local names = {}
  for _, item in ipairs(values) do
    if type(item) == "string" then
      if item ~= "" then
        table.insert(names, item)
      end
    elseif type(item) == "table" then
      local name = item.name or item.value
      if type(name) == "string" and name ~= "" then
        table.insert(names, name)
      end
    end
  end
  return table.concat(names, ", ")
end

local function issue_open_duration(issue)
  local fields = issue.fields or {}
  local created_ts = utils.parse_jira_timestamp(fields.created)
  if not created_ts then
    return "-", false
  end
  local resolved_ts = utils.parse_jira_timestamp(fields.resolutiondate)
  if not resolved_ts then
    local status = fields.status
    local category_key = status and status.statusCategory and status.statusCategory.key
    if category_key and category_key:lower() == "done" then
      resolved_ts = utils.parse_jira_timestamp(fields.statuscategorychangedate)
    end
  end
  if not resolved_ts then
    return "Still Open", true
  end
  local duration = math.max(0, resolved_ts - created_ts)
  return utils.humanize_duration(duration), false
end

local function comment_count(issue)
  local comment_collection = issue.fields and issue.fields.comment
  local comments = comment_collection and comment_collection.comments
  if type(comments) == "table" then
    return #comments
  end
  if comment_collection and tonumber(comment_collection.total) then
    return tonumber(comment_collection.total)
  end
  return 0
end

local function change_count(issue)
  local histories = issue.changelog and issue.changelog.histories
  if type(histories) == "table" then
    return #histories
  end
  return 0
end

local function normalize_assignee_display(value)
  if vim and vim.NIL and value == vim.NIL then
    return nil
  end
  if value == nil then
    return nil
  end
  if type(value) == "string" then
    return value
  end
  if type(value) == "number" then
    return tostring(value)
  end
  return nil
end

local function assignee_history(issue)
  local histories = (issue.changelog and issue.changelog.histories) or {}
  local events = {}
  local sequence = 0
  for _, history in ipairs(histories) do
    local timestamp = utils.parse_jira_timestamp(history.created) or math.huge
    for _, item in ipairs(history.items or {}) do
      local field_name = (item.fieldId or item.field or ""):lower()
      if field_name:find("assignee") then
        sequence = sequence + 1
        local assignee_name = normalize_assignee_display(item.toString) or normalize_assignee_display(item.to)
        table.insert(events, {
          timestamp = timestamp,
          order = sequence,
          assignee = assignee_name,
        })
      end
    end
  end
  table.sort(events, function(a, b)
    if a.timestamp == b.timestamp then
      return a.order < b.order
    end
    return a.timestamp < b.timestamp
  end)
  local ordered = {}
  for _, event in ipairs(events) do
    if event.assignee and event.assignee ~= "" then
      table.insert(ordered, event.assignee)
    end
  end
  if #ordered == 0 then
    local fields = issue.fields or {}
    local fallback = normalize_assignee_display(
      fields.assignee and (fields.assignee.displayName or fields.assignee.name or fields.assignee.emailAddress)
    )
    if fallback and fallback ~= "" then
      ordered = { fallback }
    end
  end
  return ordered
end

local function format_assignee_history(users)
  if not users or #users == 0 then
    return "-", nil
  end
  local parts = {}
  local segments = {}
  local cursor = 0
  for idx, name in ipairs(users) do
    table.insert(parts, name)
    table.insert(segments, { name = name, start = cursor, finish = cursor + #name })
    cursor = cursor + #name
    if idx < #users then
      local arrow = " -> "
      table.insert(parts, arrow)
      cursor = cursor + #arrow
    end
  end
  return table.concat(parts), segments
end

local function sidebar_lines(issue, width)
  local fields = issue.fields or {}
  local resolution = fields.resolution
  if vim and vim.NIL and resolution == vim.NIL then
    resolution = nil
  end
  local resolution_name
  if type(resolution) == "table" then
    resolution_name = resolution.name
  elseif type(resolution) == "string" then
    resolution_name = resolution
  end
  local assignee_name, assignee_inactive = user_display_and_status(fields.assignee)
  local reporter_name, reporter_inactive = user_display_and_status(fields.reporter)
  local open_duration_value, still_open = issue_open_duration(issue)
  local total_comments = comment_count(issue)
  local total_changes = change_count(issue)
  local assignee_sequence = assignee_history(issue)
  local assignee_history_display, assignee_history_segments = format_assignee_history(assignee_sequence)
  local metadata = {
    { label = "Key", value = issue.key, highlight = "key" },
    { label = "Status", value = fields.status and fields.status.name },
    { label = "Resolution", value = resolution_name },
    { label = "Priority", value = fields.priority and fields.priority.name, highlight = "priority" },
    { label = "Severity", value = utils.get_severity(issue), highlight = "severity" },
    { label = "Assignee", value = assignee_name, highlight = "user", inactive = assignee_inactive },
    { label = "Reporter", value = reporter_name, highlight = "user", inactive = reporter_inactive },
    { label = "Created", value = utils.format_date(fields.created), timestamp = true },
    { label = "Updated", value = utils.format_date(fields.updated), timestamp = true },
    { label = "Due", value = utils.format_date(fields.duedate), timestamp = true },
    {
      label = "Fix Versions",
      value = version_list_display(fields.fixVersions),
      highlight = "version",
    },
    {
      label = "Affects Versions",
      value = version_list_display(fields.versions or fields.affectedVersions),
      highlight = "version",
    },
    {
      label = "Open Duration",
      value = open_duration_value,
      highlight = "open_duration",
      still_open = still_open,
    },
    {
      label = "Comments",
      value = tostring(total_comments),
    },
    {
      label = "Changes",
      value = tostring(total_changes),
    },
    {
      label = "Assignees",
      value = assignee_history_display,
      highlight = assignee_history_segments and "assignee_history" or nil,
      segments = assignee_history_segments,
    },
  }

  local lines = { "Details", string.rep("-", math.max(10, width - 2)) }
  local highlights = {}
  highlight_full_line(highlights, "JiraPopupDetailsHeader", 0, lines[1])
  highlight_full_line(highlights, "JiraPopupDetailsHeader", 1, lines[2])

  for _, entry in ipairs(metadata) do
    local label = entry.label
    local value = utils.blank_if_nil(entry.value)
    if type(value) ~= "string" then
      value = tostring(value)
    end
    local text = string.format("%s: %s", label, value)
    table.insert(lines, text)
    local line_idx = #lines - 1
    highlight_label_portion(highlights, line_idx, label)
    highlight_full_line(highlights, "JiraPopupDetailsBody", line_idx, text)
    local start_col = #label + 2
    if entry.timestamp and type(value) == "string" and value ~= "-" then
      add_highlight_entry(highlights, "JiraPopupTimestamp", line_idx, start_col, start_col + #value)
    elseif entry.highlight == "key" and type(value) == "string" and value ~= "-" then
      add_highlight_entry(highlights, "JiraPopupKey", line_idx, start_col, start_col + #value)
    elseif entry.highlight == "user" and type(value) == "string" and value ~= "-" then
      local group = highlight_group_for_user(value, entry.inactive) or "JiraPopupUser"
      add_highlight_entry(highlights, group, line_idx, start_col, start_col + #value)
    elseif entry.highlight == "version" and type(value) == "string" and value ~= "-" then
      add_highlight_entry(highlights, "JiraPopupVersion", line_idx, start_col, start_col + #value)
    elseif entry.highlight == "priority" and type(value) == "string" and value ~= "-" then
      local group = priority_highlight_group(value)
      if group then
        add_highlight_entry(highlights, group, line_idx, start_col, start_col + #value)
      end
    elseif entry.highlight == "severity" and type(value) == "string" and value ~= "-" then
      local group = severity_highlight_group(value)
      if group then
        add_highlight_entry(highlights, group, line_idx, start_col, start_col + #value)
      end
    elseif entry.highlight == "open_duration" and entry.still_open and type(value) == "string" then
      add_highlight_entry(highlights, "JiraPopupOpenIndicator", line_idx, start_col, start_col + #value)
    elseif entry.highlight == "assignee_history" and entry.segments then
      for _, segment in ipairs(entry.segments) do
        local group = highlight_group_for_user(segment.name, false) or "JiraPopupUser"
        add_highlight_entry(highlights, group, line_idx, start_col + segment.start, start_col + segment.finish)
      end
    end
  end
  return lines, highlights
end

local function collect_activity(issue, width)
  local lines = {}
  local highlights = {}
  local wrap_width = math.max(20, width - 2)
  local comments = issue.fields and issue.fields.comment and issue.fields.comment.comments or {}
  if comments and #comments > 0 then
    table.insert(lines, "Comments")
    highlight_full_line(highlights, "JiraPopupCommentHeader", #lines - 1, lines[#lines])
    table.insert(lines, string.rep("-", math.max(10, width)))
    highlight_full_line(highlights, "JiraPopupCommentHeader", #lines - 1, lines[#lines])
    for _, comment in ipairs(comments) do
      local author_name, author_inactive = user_display_and_status(comment.author)
      if not author_name or author_name == "" then
        author_name = (comment.author and (comment.author.displayName or comment.author.name)) or "Unknown"
      end
      local timestamp = utils.format_date(comment.updated or comment.created)
      local stamp = (timestamp ~= "" and timestamp or "--")
      local prefix = string.format("[%s]", stamp)
      local author_line = string.format("%s %s", prefix, author_name)
      table.insert(lines, author_line)
      local line_idx = #lines - 1
      add_highlight_entry(highlights, "JiraPopupTimestamp", line_idx, 0, #prefix)
      if author_name ~= "" then
        local group = highlight_group_for_user(author_name, author_inactive) or "JiraPopupUser"
        add_highlight_entry(
          highlights,
          group,
          line_idx,
          #prefix + 1,
          #prefix + 1 + #author_name
        )
      end
      for _, wrapped in ipairs(utils.wrap_text(utils.comment_body(comment), wrap_width)) do
        if wrapped ~= "" then
          local body_line = "  " .. wrapped
          table.insert(lines, body_line)
          highlight_full_line(highlights, "JiraPopupCommentBody", #lines - 1, body_line)
        else
          table.insert(lines, "")
        end
      end
      table.insert(lines, "")
    end
  end

  local histories = issue.changelog and issue.changelog.histories or {}
  if histories and #histories > 0 then
    table.insert(lines, "Changes")
    highlight_full_line(highlights, "JiraPopupChangesHeader", #lines - 1, lines[#lines])
    table.insert(lines, string.rep("-", math.max(10, width)))
    highlight_full_line(highlights, "JiraPopupChangesHeader", #lines - 1, lines[#lines])
    local total = 0
    for _, history in ipairs(histories) do
      if total >= 30 then
        break
      end
      total = total + 1
      local author_name, author_inactive = user_display_and_status(history.author)
      if not author_name or author_name == "" then
        author_name = (history.author and (history.author.displayName or history.author.name)) or "Unknown"
      end
      local timestamp = utils.format_date(history.created)
      local stamp = (timestamp ~= "" and timestamp or "--")
      local prefix = string.format("[%s]", stamp)
      local author_line = string.format("%s %s", prefix, author_name)
      table.insert(lines, author_line)
      local line_idx = #lines - 1
      add_highlight_entry(highlights, "JiraPopupTimestamp", line_idx, 0, #prefix)
      if author_name ~= "" then
        local group = highlight_group_for_user(author_name, author_inactive) or "JiraPopupUser"
        add_highlight_entry(
          highlights,
          group,
          line_idx,
          #prefix + 1,
          #prefix + 1 + #author_name
        )
      end
      for _, item in ipairs(history.items or {}) do
        local from = item.fromString or item.from or ""
        local to = item.toString or item.to or ""
        local change_line = string.format(
          "  %s: %s -> %s",
          item.field or item.fieldId or "field",
          utils.blank_if_nil(from),
          utils.blank_if_nil(to)
        )
        table.insert(lines, change_line)
        highlight_full_line(highlights, "JiraPopupChangesBody", #lines - 1, change_line)
      end
      table.insert(lines, "")
    end
  end

  if #lines == 0 then
    local text = "No recent activity."
    local no_activity = { text }
    local no_activity_highlights = {}
    highlight_full_line(no_activity_highlights, "JiraPopupSection", 0, text)
    return no_activity, no_activity_highlights
  end

  return lines, highlights
end

local function main_lines(issue, width, config)
  local fields = issue.fields or {}
  local summary = fields.summary or "(no summary)"
  local description = utils.requested_description(issue)
  if description == "" then
    description = "No description available."
  end

  local lines = {}
  local highlights = {}
  local title_line = string.format("%s — %s", issue.key, summary)
  table.insert(lines, title_line)
  highlight_full_line(highlights, "JiraPopupTitle", #lines - 1, title_line)
  local underline = string.rep("=", math.max(20, width))
  table.insert(lines, underline)
  highlight_full_line(highlights, "JiraPopupTitle", #lines - 1, underline)
  local summary_divider = string.rep("-", math.max(20, width))
  table.insert(lines, summary_divider)
  highlight_full_line(highlights, "JiraPopupSection", #lines - 1, summary_divider)
  table.insert(lines, "Description")
  highlight_full_line(highlights, "JiraPopupSection", #lines - 1, lines[#lines])
  local description_divider = string.rep("-", math.max(10, width))
  table.insert(lines, description_divider)
  highlight_full_line(highlights, "JiraPopupDescription", #lines - 1, description_divider)
  for _, line in ipairs(utils.wrap_text(description, math.max(20, width))) do
    table.insert(lines, line)
    if line ~= "" then
      highlight_full_line(highlights, "JiraPopupDescription", #lines - 1, line)
    end
  end
  table.insert(lines, "")
  table.insert(lines, "Activity")
  highlight_full_line(highlights, "JiraPopupSection", #lines - 1, lines[#lines])
  local activity_divider = string.rep("-", math.max(10, width))
  table.insert(lines, activity_divider)
  highlight_full_line(highlights, "JiraPopupSection", #lines - 1, activity_divider)
  local activity_lines, activity_highlights = collect_activity(issue, width)
  append_section(lines, highlights, activity_lines, activity_highlights)
  table.insert(lines, "")
  local footer_divider = string.rep("-", math.max(10, width))
  table.insert(lines, footer_divider)
  highlight_full_line(highlights, "JiraPopupSection", #lines - 1, footer_divider)
  return lines, highlights
end

local function summary_bar_lines(issue, width)
  local fields = issue.fields or {}
  local summary_text = fields.summary or "(no summary)"
  local title_line = string.format("%s — %s", issue.key or "Issue", summary_text)
  local divider_width = math.max(20, math.floor(width or 0))
  local divider_line = string.rep("=", divider_width)
  local lines = { title_line, divider_line }
  local highlights = {}
  highlight_full_line(highlights, "JiraPopupTitle", 0, title_line)
  highlight_full_line(highlights, "JiraPopupTitle", 1, divider_line)
  return lines, highlights
end

local function url_bar_lines(issue, config, width)
  local url_value = format_issue_url(issue.key, config)
  if url_value == "" then
    url_value = "URL unavailable (set config.api.base_url or $JIRA_BASE_URL)"
  end
  local lines = {}
  local highlights = {}
  local label = "URL"
  local url_line = string.format("%s: %s", label, url_value)
  table.insert(lines, url_line)
  highlight_full_line(highlights, "JiraPopupUrlBar", #lines - 1, url_line)
  highlight_label_portion(highlights, #lines - 1, label)
  local value_start = #label + 2
  add_highlight_entry(highlights, "JiraPopupLink", #lines - 1, value_start, value_start + #url_value)
  return lines, highlights
end

local function help_bar_lines(width)
  local lines = {}
  local highlights = {}
  local wrap_width = math.max(20, width or 20)
  for _, line in ipairs(utils.wrap_text(nav_hint, wrap_width)) do
    table.insert(lines, line)
    highlight_full_line(highlights, "JiraPopupUrlBar", #lines - 1, line)
  end
  if #lines == 0 then
    table.insert(lines, nav_hint)
    highlight_full_line(highlights, "JiraPopupUrlBar", 0, nav_hint)
  end
  return lines, highlights
end

local function format_popup_title(issue_key, nav)
  local suffix = ""
  if nav and nav.index and nav.total then
    suffix = string.format(" (%d/%d)", nav.index, nav.total)
  end
  local title = string.format(" JIRA %s%s ", issue_key, suffix)
  if nav and nav.has_prev then
    title = "< " .. title
  end
  if nav and nav.has_next then
    title = title .. " >"
  end
  return title
end

local function sanitize_lines(lines)
  -- nvim_buf_set_lines rejects entries containing newline characters
  local sanitized = {}
  for _, line in ipairs(lines or {}) do
    if type(line) ~= "string" then
      line = tostring(line)
    end
    if line:find("[\r\n]") then
      line = line:gsub("[\r\n]", " ")
    end
    table.insert(sanitized, line)
  end
  return sanitized
end

local function fill_buffer(buf, lines, opts)
  opts = opts or {}
  lines = sanitize_lines(lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = opts.filetype or "jira_popup"
  vim.bo[buf].swapfile = false

  local function start_highlighter(lang, allow_syntax_option)
    if not lang or lang == "" then
      return
    end
    local ok = false
    if vim.treesitter and vim.treesitter.start then
      ok = pcall(vim.treesitter.start, buf, lang)
    end
    if not ok and allow_syntax_option then
      pcall(vim.api.nvim_buf_set_option, buf, "syntax", lang)
    end
  end

  if opts.syntax then
    if type(opts.syntax) == "table" then
      for idx, lang in ipairs(opts.syntax) do
        start_highlighter(lang, idx == 1)
      end
    else
      start_highlighter(opts.syntax, true)
    end
  end
end

local function enable_yank_feedback(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  if not (vim.highlight and vim.highlight.on_yank) then
    return
  end
  vim.api.nvim_clear_autocmds({ group = yank_group, buffer = buf })
  vim.api.nvim_create_autocmd("TextYankPost", {
    group = yank_group,
    buffer = buf,
    callback = function()
      vim.highlight.on_yank({ higroup = "IncSearch", timeout = 150 })
    end,
  })
end

local function map_popup_keys(buf, issue, config, nav_controls)
  local opts = { buffer = buf, nowait = true, silent = true }
  local function close_popup()
    Popup.close()
  end
  local function open_in_browser()
    local url = format_issue_url(issue.key, config)
    if url == "" then
      vim.notify("jira.nvim: Jira base URL is not configured; cannot open browser", vim.log.levels.WARN)
      return
    end
    utils.open_url(url)
  end
  local function search_popup()
    start_popup_search(vim.api.nvim_get_current_win())
  end
  local function repeat_search_forward()
    repeat_popup_search(vim.api.nvim_get_current_win(), false)
  end
  local function repeat_search_backward()
    repeat_popup_search(vim.api.nvim_get_current_win(), true)
  end
  local function focus_next()
    focus_next_popup_window(vim.api.nvim_get_current_win())
  end
  local function focus_prev()
    focus_previous_popup_window(vim.api.nvim_get_current_win())
  end
  local function open_link_at_cursor(trigger)
    open_url_under_cursor(buf, config, trigger)
  end
  vim.keymap.set("n", "q", close_popup, opts)
  vim.keymap.set("n", "<Esc>", close_popup, opts)
  vim.keymap.set("n", "o", open_in_browser, opts)
  vim.keymap.set("n", "<CR>", function()
    open_link_at_cursor("<CR>")
  end, opts)
  vim.keymap.set("n", "/", search_popup, opts)
  vim.keymap.set("n", "n", repeat_search_forward, opts)
  vim.keymap.set("n", "N", repeat_search_backward, opts)
  vim.keymap.set("n", "<Tab>", focus_next, opts)
  vim.keymap.set("n", "<S-Tab>", focus_prev, opts)
  if vim.fn.has("mac") == 1 then
    vim.keymap.set("n", "<D-LeftMouse>", function()
      open_link_at_cursor("<D-LeftMouse>")
    end, opts)
  end
  vim.keymap.set("n", "<C-LeftMouse>", function()
    open_link_at_cursor("<C-LeftMouse>")
  end, opts)
  if nav_controls and nav_controls.next_issue then
    vim.keymap.set("n", "<C-n>", nav_controls.next_issue, opts)
  end
  if nav_controls and nav_controls.prev_issue then
    vim.keymap.set("n", "<C-p>", nav_controls.prev_issue, opts)
  end
  for _, seq in ipairs({
    "<C-w><Left>",
    "<C-w><Right>",
    "<C-w><Up>",
    "<C-w><Down>",
    "<C-w><",
    "<C-w>>",
    "<C-w>+",
    "<C-w>-",
    "<C-w>|",
    "<C-w>_",
    "<C-w>=",
    "<C-w>H",
    "<C-w>L",
    "<C-w>K",
    "<C-w>J",
  }) do
    vim.keymap.set("n", seq, function() end, opts)
  end
end

local function show_render_error(message)
  local buf = vim.api.nvim_create_buf(false, true)
  local msg = message or "Unknown error"
  local msg_lines
  if type(msg) == "string" then
    msg_lines = vim.split(msg, "\n", { plain = true })
  else
    msg_lines = { vim.inspect(msg) }
  end
  if #msg_lines == 0 then
    msg_lines = { "Unknown error" }
  end

  local lines = { "jira.nvim: failed to render issue popup" }
  vim.list_extend(lines, msg_lines)
  table.insert(lines, "")
  table.insert(lines, "Press <Esc> or q to close")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "jira_popup_error"
  vim.bo[buf].swapfile = false
  local width = 0
  for _, line in ipairs(lines) do
    width = math.max(width, #line)
  end
  width = math.min(math.max(30, width + 4), vim.o.columns - 2)
  local height = #lines + 2
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
    title = "jira.nvim error",
    title_pos = "center",
  })
  local close_opts = { buffer = buf, nowait = true, silent = true }
  local function close()
    close_window(win)
    wipe_buffer(buf)
  end
  vim.keymap.set("n", "<Esc>", close, close_opts)
  vim.keymap.set("n", "q", close, close_opts)
end

function Popup.render_issue_list(issues, config, opts)
  Popup.close()
  close_issue_list()
  ensure_popup_highlights()
  config = config or {}
  opts = opts or {}
  issues = issues or {}

  local layout_cfg = opts.layout or (config and config.assigned_popup) or {}
  local dims = list_dimensions(config, layout_cfg)
  local border = layout_cfg.border or (config.popup and config.popup.border) or "rounded"
  local title = opts.title or layout_cfg.title or "Assigned Issues"

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "jiraissue-list"

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = dims.width,
    height = dims.height,
    col = dims.col,
    row = dims.row,
    style = "minimal",
    border = border,
  })

  vim.api.nvim_win_set_option(win, "wrap", false)
  vim.api.nvim_win_set_option(win, "winhl", "Normal:JiraPopupDetailsBody,FloatBorder:JiraPopupDetailsHeader")

  local layout = build_issue_list_lines(issues, dims, {
    title = title,
    pagination = opts.pagination,
    subtitle = opts.subtitle,
    empty_message = opts.empty_message,
  })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, layout.lines)
  vim.bo[buf].modifiable = false

  if layout.title_line then
    vim.api.nvim_buf_add_highlight(buf, popup_ns, "JiraPopupListTitle", layout.title_line - 1, 0, -1)
  end
  if layout.summary_line then
    vim.api.nvim_buf_add_highlight(buf, popup_ns, "JiraPopupListTitle", layout.summary_line - 1, 0, -1)
  end
  if layout.header_line then
    vim.api.nvim_buf_add_highlight(buf, popup_ns, "JiraPopupListHeader", layout.header_line - 1, 0, -1)
  end
  if layout.empty_line then
    vim.api.nvim_buf_add_highlight(buf, popup_ns, "JiraPopupListEmpty", layout.empty_line - 1, 0, -1)
  end

  list_state = {
    win = win,
    buf = buf,
    issues = issues,
    selection = (#issues > 0) and 1 or nil,
    data_offset = layout.data_offset,
    autocmd = nil,
    on_select = opts.on_select,
    pagination = opts.pagination,
    page_handlers = opts.pagination_handlers,
    close_on_select = opts.close_on_select == true,
    title = title,
    source = opts.source,
    search_active = false,
    selection_before_search = nil,
  }

  if list_state.selection then
    refresh_issue_list_selection()
  end

  vim.api.nvim_clear_autocmds({ group = list_group })
  list_state.autocmd = vim.api.nvim_create_autocmd("WinClosed", {
    group = list_group,
    callback = function(args)
      local closed = tonumber(args.match)
      if closed and list_state.win and closed == list_state.win then
        close_issue_list()
      end
    end,
  })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = list_group,
    buffer = buf,
    callback = function()
      sync_list_selection_to_cursor()
    end,
  })
  vim.api.nvim_create_autocmd("CmdlineEnter", {
    group = list_group,
    pattern = { "/", "?" },
    callback = function()
      if not list_state.win or not vim.api.nvim_win_is_valid(list_state.win) then
        return
      end
      if vim.api.nvim_get_current_win() ~= list_state.win then
        return
      end
      list_state.search_active = true
      list_state.selection_before_search = list_state.selection
    end,
  })
  vim.api.nvim_create_autocmd("CmdlineLeave", {
    group = list_group,
    pattern = { "/", "?" },
    callback = function()
      if not list_state.search_active then
        return
      end
      if vim.v.event and vim.v.event.abort then
        restore_selection_before_search()
      else
        sync_list_selection_to_cursor()
        list_state.selection_before_search = nil
      end
      list_state.search_active = false
    end,
  })

  local key_opts = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set("n", "q", Popup.close_all, key_opts)
  vim.keymap.set("n", "<Esc>", Popup.close_all, key_opts)
  vim.keymap.set("n", "j", function()
    move_issue_list_selection(1)
  end, key_opts)
  vim.keymap.set("n", "k", function()
    move_issue_list_selection(-1)
  end, key_opts)
  vim.keymap.set("n", "<Down>", function()
    move_issue_list_selection(1)
  end, key_opts)
  vim.keymap.set("n", "<Up>", function()
    move_issue_list_selection(-1)
  end, key_opts)
  vim.keymap.set("n", "<S-N>", function()
    move_issue_list_selection(1)
  end, key_opts)
  vim.keymap.set("n", "<S-P>", function()
    move_issue_list_selection(-1)
  end, key_opts)
  vim.keymap.set("n", "<C-f>", function()
    goto_issue_list_page(1)
  end, key_opts)
  vim.keymap.set("n", "<C-b>", function()
    goto_issue_list_page(-1)
  end, key_opts)
  vim.keymap.set("n", "<CR>", activate_current_issue, key_opts)

  return win
end

function Popup.render(issue, config, context)
  Popup.close()
  local created_bufs = {}
  local created_wins = {}
  local function track_buf(buf)
    if buf then
      table.insert(created_bufs, buf)
    end
  end
  local function track_win(win)
    if win then
      table.insert(created_wins, win)
    end
  end
  local function cleanup_partials()
    for _, win in ipairs(created_wins) do
      close_window(win)
    end
    for _, buf in ipairs(created_bufs) do
      wipe_buffer(buf)
    end
  end

  local ok, err = xpcall(function()
    config = config or {}
    config.popup = config.popup or {}
    context = context or {}
    ensure_popup_highlights()

    local nav_context = context.navigation
    state.navigation = nav_context
    state.return_focus = context.return_focus
    local nav_controls = nil
    if nav_context then
      nav_controls = {
        next_issue = nav_context.goto_next,
        prev_issue = nav_context.goto_prev,
      }
    end

    local dims = calculate_dimensions(config)
    local pane_gap = 2
    local vertical_gap = 0
    local min_inner_width = 56
    local min_content_height = 8
    local inner_width = math.max(min_inner_width, dims.width)
    local summary_margin_left = 1
    local main_margin_left = 1
    local sidebar_margin_left = 1
    local url_margin_left = 1

    local sidebar_width = math.max(24, math.floor(inner_width * 0.32))
    local max_sidebar = inner_width - pane_gap - 30
    if sidebar_width > max_sidebar then
      sidebar_width = math.max(24, max_sidebar)
    end
    if sidebar_width < 24 then
      sidebar_width = 24
    end
    local main_width = inner_width - sidebar_width - pane_gap
    if main_width < 30 then
      main_width = math.max(30, main_width)
      sidebar_width = inner_width - main_width - pane_gap
    end
    if sidebar_width < 24 then
      sidebar_width = 24
      main_width = inner_width - sidebar_width - pane_gap
    end

    local summary_width = math.max(1, inner_width - summary_margin_left)
    local main_width_with_margin = math.max(1, main_width - main_margin_left)
    local sidebar_width_with_margin = math.max(1, sidebar_width - sidebar_margin_left)
    local url_width = math.max(1, inner_width - url_margin_left)

    local container_buf = vim.api.nvim_create_buf(false, true)
    track_buf(container_buf)
    vim.api.nvim_buf_set_lines(container_buf, 0, -1, false, { "" })
    vim.bo[container_buf].bufhidden = "wipe"
    vim.bo[container_buf].filetype = "jira_popup_container"
    vim.bo[container_buf].modifiable = false

    local container_win = vim.api.nvim_open_win(container_buf, false, {
      relative = "editor",
      width = dims.width,
      height = dims.height,
      col = dims.col,
      row = dims.row,
      style = "minimal",
      border = "double",
      title = format_popup_title(issue.key, nav_context),
      title_pos = "center",
      zindex = 50,
      focusable = false,
    })
    track_win(container_win)
    vim.api.nvim_win_set_option(container_win, "winhl", "FloatTitle:JiraPopupTitleBar")

    local summary_buf = vim.api.nvim_create_buf(false, true)
    local main_buf = vim.api.nvim_create_buf(false, true)
    local sidebar_buf = vim.api.nvim_create_buf(false, true)
    local url_buf = vim.api.nvim_create_buf(false, true)
    local help_buf = vim.api.nvim_create_buf(false, true)
    track_buf(summary_buf)
    track_buf(main_buf)
    track_buf(sidebar_buf)
    track_buf(url_buf)
    track_buf(help_buf)

    local main_content, main_highlights = main_lines(issue, math.max(20, main_width_with_margin - 1), config)
    local sidebar_content, sidebar_highlights = sidebar_lines(issue, math.max(20, sidebar_width_with_margin - 1))
    local url_content, url_highlights = url_bar_lines(issue, config, url_width)
    local help_content, help_highlights = help_bar_lines(url_width)
    local summary_lines, summary_highlights = summary_bar_lines(issue, summary_width)
    local url_bar_height = math.max(1, #url_content)
    local help_bar_height = math.max(1, #help_content)
    local content_height = math.max(min_content_height, dims.height - url_bar_height - help_bar_height - vertical_gap)
    local summary_line_count = math.min(#main_content, 2)
    local main_body_lines = {}
    local main_body_highlights = {}
    for idx, line in ipairs(main_content) do
      if idx > summary_line_count then
        table.insert(main_body_lines, line)
      end
    end
    for _, mark in ipairs(main_highlights) do
      if mark.line >= summary_line_count then
        table.insert(main_body_highlights, {
          group = mark.group,
          line = mark.line - summary_line_count,
          start_col = mark.start_col,
          end_col = mark.end_col,
        })
      end
    end
    if not summary_lines or #summary_lines == 0 then
      summary_lines = { "" }
      summary_highlights = {}
    end
    local summary_height = #summary_lines
    local scrollable_height = content_height - summary_height
    if scrollable_height < 4 then
      scrollable_height = math.max(4, content_height - 1)
      summary_height = math.max(1, content_height - scrollable_height)
    end

    -- Keymaps are set before rendering so Esc/q can close even if later steps fail.
    map_popup_keys(summary_buf, issue, config, nav_controls)
    map_popup_keys(main_buf, issue, config, nav_controls)
    map_popup_keys(sidebar_buf, issue, config, nav_controls)
    map_popup_keys(url_buf, issue, config, nav_controls)
    map_popup_keys(help_buf, issue, config, nav_controls)

    enable_yank_feedback(summary_buf)
    enable_yank_feedback(main_buf)
    enable_yank_feedback(sidebar_buf)
    enable_yank_feedback(url_buf)
    enable_yank_feedback(help_buf)

    fill_buffer(summary_buf, summary_lines)
    fill_buffer(main_buf, main_body_lines, { syntax = { "markdown", "markdown_inline" } })
    fill_buffer(sidebar_buf, sidebar_content)
    fill_buffer(url_buf, url_content)
    fill_buffer(help_buf, help_content)

    local ignored_projects = config._ignored_project_map
    apply_highlights(summary_buf, summary_lines, summary_highlights, config.issue_pattern, ignored_projects)
    apply_highlights(main_buf, main_body_lines, main_body_highlights, config.issue_pattern, ignored_projects)
    apply_highlights(sidebar_buf, sidebar_content, sidebar_highlights, config.issue_pattern, ignored_projects)
    apply_highlights(url_buf, url_content, url_highlights, config.issue_pattern, ignored_projects)
    apply_highlights(help_buf, help_content, help_highlights, config.issue_pattern, ignored_projects)

    local summary_win = vim.api.nvim_open_win(summary_buf, false, {
      relative = "win",
      win = container_win,
      width = summary_width,
      height = summary_height,
      col = summary_margin_left,
      row = 0,
      style = "minimal",
      border = "none",
      zindex = 60,
      focusable = false,
    })
    track_win(summary_win)
    vim.api.nvim_win_set_option(summary_win, "winhl", "Normal:JiraPopupSummaryBackground,NormalNC:JiraPopupSummaryBackground")

    local main_win = vim.api.nvim_open_win(main_buf, true, {
      relative = "win",
      win = container_win,
      width = main_width_with_margin,
      height = scrollable_height,
      col = main_margin_left,
      row = summary_height,
      style = "minimal",
      border = "none",
      zindex = 60,
    })
    track_win(main_win)
    vim.api.nvim_win_set_option(main_win, "conceallevel", 0)

    local sidebar_win = vim.api.nvim_open_win(sidebar_buf, false, {
      relative = "win",
      win = container_win,
      width = sidebar_width_with_margin,
      height = scrollable_height,
      col = main_width + pane_gap + sidebar_margin_left,
      row = summary_height,
      style = "minimal",
      border = "none",
      zindex = 60,
    })
    track_win(sidebar_win)
    vim.api.nvim_win_set_option(sidebar_win, "conceallevel", 0)
    vim.api.nvim_win_set_option(sidebar_win, "winhl", "Normal:JiraPopupDetailsBody,NormalNC:JiraPopupDetailsBody")

    local url_win = vim.api.nvim_open_win(url_buf, false, {
      relative = "win",
      win = container_win,
      width = url_width,
      height = url_bar_height,
      col = url_margin_left,
      row = content_height + vertical_gap,
      style = "minimal",
      border = "none",
      zindex = 60,
    })
    track_win(url_win)
    vim.api.nvim_win_set_option(url_win, "conceallevel", 0)
    vim.api.nvim_win_set_option(url_win, "winhl", "Normal:JiraPopupUrlBar,NormalNC:JiraPopupUrlBar")

    local help_win = vim.api.nvim_open_win(help_buf, false, {
      relative = "win",
      win = container_win,
      width = url_width,
      height = help_bar_height,
      col = url_margin_left,
      row = content_height + vertical_gap + url_bar_height,
      style = "minimal",
      border = "none",
      zindex = 60,
      focusable = false,
    })
    track_win(help_win)
    vim.api.nvim_win_set_option(help_win, "conceallevel", 0)
    vim.api.nvim_win_set_option(help_win, "winhl", "Normal:JiraPopupUrlBar,NormalNC:JiraPopupUrlBar")

    lock_window_size(summary_win)
    lock_window_size(main_win)
    lock_window_size(sidebar_win)
    lock_window_size(url_win)
    lock_window_size(help_win)

    state.dimensions = {}
    for _, details in ipairs({
      container_win,
      summary_win,
      main_win,
      sidebar_win,
      url_win,
      help_win,
    }) do
      local snapshot = record_window_dimensions(details)
      if snapshot then
        state.dimensions[details] = snapshot
      end
    end

    local fields = issue.fields or {}
    local status_name = fields.status and fields.status.name or "--"
    apply_statusline(main_win, status_name)
    apply_statusline(sidebar_win, status_name)

    state.container_win = container_win
    state.main_win = main_win
    state.sidebar_win = sidebar_win
    state.summary_win = summary_win
    state.url_win = url_win
    state.help_win = help_win
    state.buffers = { container_buf, summary_buf, main_buf, sidebar_buf, url_buf, help_buf }
    update_allowed_wins()
    activate_size_guard()
    activate_focus_guard()
    focus_window(main_win)
    created_bufs = {}
    created_wins = {}
  end, debug.traceback)

  if not ok then
    cleanup_partials()
    Popup.close()
    vim.notify("jira.nvim: popup render failed: " .. tostring(err), vim.log.levels.ERROR)
    show_render_error(err)
  end
end

return Popup

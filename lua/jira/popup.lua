local utils = require("jira.utils")

local Popup = {}

local popup_ns = vim.api.nvim_create_namespace("jira.nvim.popup")
local popup_highlights_ready = false
local nav_hint = "Nav: j/k scroll • gg top • G bottom • Tab/S-Tab switch panes • / search • <S-N>/<S-P> next/prev • q/Esc close • o open URL"
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
    bg = catppuccin.crust,
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
  if not user then
    return nil, false
  end
  local base = user.displayName or user.name or user.emailAddress
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

local function add_issue_key_highlights(buf, lines, pattern)
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
      add_buffer_highlight(buf, "JiraPopupKey", idx - 1, s - 1, e)
      start = e + 1
    end
  end
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
      add_buffer_highlight(buf, "JiraPopupLink", idx - 1, s - 1, e)
      start = e + 1
    end
  end
end

local function apply_highlights(buf, lines, highlights, issue_pattern)
  ensure_popup_highlights()
  vim.api.nvim_buf_clear_namespace(buf, popup_ns, 0, -1)
  if highlights then
    for _, mark in ipairs(highlights) do
      add_buffer_highlight(buf, mark.group, mark.line, mark.start_col, mark.end_col)
    end
  end
  add_issue_key_highlights(buf, lines, issue_pattern)
  add_link_highlights(buf, lines)
end

local focus_group = vim.api.nvim_create_augroup("JiraPopupGuard", { clear = true })

local state = {
  container_win = nil,
  main_win = nil,
  sidebar_win = nil,
  summary_win = nil,
  url_win = nil,
  buffers = {},
  allowed_wins = {},
  focus_autocmd = nil,
  last_focus = nil,
  navigation = nil,
}

local function valid_win(win)
  return win ~= nil and vim.api.nvim_win_is_valid(win)
end

local function update_allowed_wins()
  local allowed = {}
  for _, win in ipairs({ state.main_win, state.sidebar_win, state.url_win }) do
    if valid_win(win) then
      table.insert(allowed, win)
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

local function normalized_base_url(config)
  if config and config.api and config.api.base_url and config.api.base_url ~= "" then
    return (config.api.base_url or ""):gsub("/*$", "")
  end
  return (vim.env.JIRA_BASE_URL or ""):gsub("/*$", "")
end

local function format_issue_url(issue_key, config)
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
  for _, win in ipairs({ state.main_win, state.sidebar_win }) do
    if valid_win(win) then
      table.insert(wins, win)
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

local function search_in_window(win, pattern, use_current_position)
  if not valid_win(win) then
    return false
  end
  local original_win = vim.api.nvim_get_current_win()
  if original_win ~= win then
    vim.api.nvim_set_current_win(win)
  end
  local flags = use_current_position and "c" or "cw"
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
  local wins = popup_content_windows()
  if #wins == 0 then
    return
  end
  local start_idx = find_window_index(start_win, wins) or 1
  for offset = 0, #wins - 1 do
    local idx = ((start_idx + offset - 1) % #wins) + 1
    local win = wins[idx]
    if search_in_window(win, pattern, idx == start_idx) then
      return
    end
  end
  vim.notify("jira.nvim: Pattern not found inside popup", vim.log.levels.INFO)
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
  close_window(state.main_win)
  close_window(state.sidebar_win)
  close_window(state.summary_win)
  close_window(state.url_win)
  close_window(state.container_win)
  for _, buf in ipairs(state.buffers) do
    wipe_buffer(buf)
  end
  state = {
    container_win = nil,
    main_win = nil,
    sidebar_win = nil,
    summary_win = nil,
    url_win = nil,
    buffers = {},
    allowed_wins = {},
    focus_autocmd = nil,
    last_focus = nil,
    navigation = nil,
  }
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
        local assignee_name = item.toString or item.to or ""
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
    local fallback = fields.assignee and (fields.assignee.displayName or fields.assignee.name or fields.assignee.emailAddress)
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
    { label = "Resolution", value = fields.resolution and fields.resolution.name },
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
  local legend_line = nav_hint
  table.insert(lines, legend_line)
  highlight_full_line(highlights, "JiraPopupUrlBar", #lines - 1, legend_line)
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

local function fill_buffer(buf, lines, opts)
  opts = opts or {}
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
  local function focus_next()
    focus_next_popup_window(vim.api.nvim_get_current_win())
  end
  local function focus_prev()
    focus_previous_popup_window(vim.api.nvim_get_current_win())
  end
  vim.keymap.set("n", "q", close_popup, opts)
  vim.keymap.set("n", "<Esc>", close_popup, opts)
  vim.keymap.set("n", "o", open_in_browser, opts)
  vim.keymap.set("n", "/", search_popup, opts)
  vim.keymap.set("n", "<Tab>", focus_next, opts)
  vim.keymap.set("n", "<S-Tab>", focus_prev, opts)
  if nav_controls and nav_controls.next_issue then
    vim.keymap.set("n", "<S-N>", nav_controls.next_issue, opts)
  end
  if nav_controls and nav_controls.prev_issue then
    vim.keymap.set("n", "<S-P>", nav_controls.prev_issue, opts)
  end
  for _, seq in ipairs({ "<C-w><Left>", "<C-w><Right>", "<C-w><Up>", "<C-w><Down>", "<C-w><", "<C-w>>", "<C-w>+", "<C-w>-", "<C-w>|", "<C-w>_" }) do
    vim.keymap.set("n", seq, function() end, opts)
  end
end

function Popup.render(issue, config, context)
  Popup.close()

  config = config or {}
  config.popup = config.popup or {}
  context = context or {}
  ensure_popup_highlights()

  local nav_context = context.navigation
  state.navigation = nav_context
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
  local url_bar_height = 2
  local margin = 0
  local min_inner_width = 56
  local min_content_height = 8
  local inner_width = math.max(min_inner_width, dims.width)
  local content_height = math.max(min_content_height, dims.height - url_bar_height - vertical_gap)

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

  local container_buf = vim.api.nvim_create_buf(false, true)
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
  vim.api.nvim_win_set_option(container_win, "winhl", "FloatTitle:JiraPopupTitleBar")

  local summary_buf = vim.api.nvim_create_buf(false, true)
  local main_buf = vim.api.nvim_create_buf(false, true)
  local sidebar_buf = vim.api.nvim_create_buf(false, true)
  local url_buf = vim.api.nvim_create_buf(false, true)

  local main_content, main_highlights = main_lines(issue, math.max(20, main_width - 2), config)
  local sidebar_content, sidebar_highlights = sidebar_lines(issue, math.max(20, sidebar_width - 2))
  local url_content, url_highlights = url_bar_lines(issue, config, inner_width)
  local summary_lines, summary_highlights = summary_bar_lines(issue, inner_width)
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

  fill_buffer(summary_buf, summary_lines)
  fill_buffer(main_buf, main_body_lines, { syntax = { "markdown", "markdown_inline" } })
  fill_buffer(sidebar_buf, sidebar_content)
  fill_buffer(url_buf, url_content)

  apply_highlights(summary_buf, summary_lines, summary_highlights, config.issue_pattern)
  apply_highlights(main_buf, main_body_lines, main_body_highlights, config.issue_pattern)
  apply_highlights(sidebar_buf, sidebar_content, sidebar_highlights, config.issue_pattern)
  apply_highlights(url_buf, url_content, url_highlights, config.issue_pattern)

  local summary_win = vim.api.nvim_open_win(summary_buf, false, {
    relative = "win",
    win = container_win,
    width = inner_width,
    height = summary_height,
    col = margin,
    row = margin,
    style = "minimal",
    border = "none",
    zindex = 60,
    focusable = false,
  })
  vim.api.nvim_win_set_option(summary_win, "winhl", "Normal:JiraPopupSummaryBackground,NormalNC:JiraPopupSummaryBackground")

  local main_win = vim.api.nvim_open_win(main_buf, true, {
    relative = "win",
    win = container_win,
    width = main_width,
    height = scrollable_height,
    col = margin,
    row = margin + summary_height,
    style = "minimal",
    border = "none",
    zindex = 60,
  })

  local sidebar_win = vim.api.nvim_open_win(sidebar_buf, false, {
    relative = "win",
    win = container_win,
    width = sidebar_width,
    height = scrollable_height,
    col = margin + main_width + pane_gap,
    row = margin + summary_height,
    style = "minimal",
    border = "none",
    zindex = 60,
  })
  vim.api.nvim_win_set_option(sidebar_win, "winhl", "Normal:JiraPopupDetailsBody,NormalNC:JiraPopupDetailsBody")

  local url_win = vim.api.nvim_open_win(url_buf, false, {
    relative = "win",
    win = container_win,
    width = dims.width,
    height = url_bar_height,
    col = 0,
    row = margin + content_height + vertical_gap,
    style = "minimal",
    border = "none",
    zindex = 60,
  })
  vim.api.nvim_win_set_option(url_win, "winhl", "Normal:JiraPopupUrlBar,NormalNC:JiraPopupUrlBar")

  lock_window_size(summary_win)
  lock_window_size(main_win)
  lock_window_size(sidebar_win)
  lock_window_size(url_win)

  local fields = issue.fields or {}
  local status_name = fields.status and fields.status.name or "--"
  apply_statusline(main_win, status_name)
  apply_statusline(sidebar_win, status_name)

  map_popup_keys(main_buf, issue, config, nav_controls)
  map_popup_keys(sidebar_buf, issue, config, nav_controls)
  map_popup_keys(url_buf, issue, config, nav_controls)

  state.container_win = container_win
  state.main_win = main_win
  state.sidebar_win = sidebar_win
  state.summary_win = summary_win
  state.url_win = url_win
  state.buffers = { container_buf, summary_buf, main_buf, sidebar_buf, url_buf }
  update_allowed_wins()
  activate_focus_guard()
  focus_window(main_win)
end

return Popup

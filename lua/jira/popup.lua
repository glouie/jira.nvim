local utils = require("jira.utils")

local Popup = {}

local state = {
  main_win = nil,
  sidebar_win = nil,
  buffers = {},
}

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
  close_window(state.main_win)
  close_window(state.sidebar_win)
  for _, buf in ipairs(state.buffers) do
    wipe_buffer(buf)
  end
  state = {
    main_win = nil,
    sidebar_win = nil,
    buffers = {},
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

local function sidebar_lines(issue, width)
  local fields = issue.fields or {}
  local function name_for(user)
    if not user then
      return nil
    end
    return user.displayName or user.name or user.emailAddress
  end

  local metadata = {
    { "Key", issue.key },
    { "Status", fields.status and fields.status.name },
    { "Resolution", fields.resolution and fields.resolution.name },
    { "Priority", fields.priority and fields.priority.name },
    { "Severity", utils.get_severity(issue) },
    { "Assignee", name_for(fields.assignee) },
    { "Reporter", name_for(fields.reporter) },
    { "Created", utils.format_date(fields.created) },
    { "Updated", utils.format_date(fields.updated) },
    { "Due", utils.format_date(fields.duedate) },
  }

  local lines = { "Details", string.rep("-", math.max(10, width - 2)) }
  for _, entry in ipairs(metadata) do
    table.insert(lines, string.format("%s: %s", entry[1], utils.blank_if_nil(entry[2])))
  end
  return lines
end

local function collect_activity(issue, width)
  local lines = {}
  local wrap_width = math.max(20, width - 2)
  local comments = issue.fields and issue.fields.comment and issue.fields.comment.comments or {}
  if comments and #comments > 0 then
    table.insert(lines, "Comments")
    table.insert(lines, string.rep("-", math.max(10, width)))
    for _, comment in ipairs(comments) do
      local author = comment.author and (comment.author.displayName or comment.author.name) or "Unknown"
      local timestamp = utils.format_date(comment.updated or comment.created)
      table.insert(lines, string.format("[%s] %s", timestamp ~= "" and timestamp or "--", author))
      for _, wrapped in ipairs(utils.wrap_text(utils.comment_body(comment), wrap_width)) do
        table.insert(lines, "  " .. wrapped)
      end
      table.insert(lines, "")
    end
  end

  local histories = issue.changelog and issue.changelog.histories or {}
  if histories and #histories > 0 then
    table.insert(lines, "Changes")
    table.insert(lines, string.rep("-", math.max(10, width)))
    local total = 0
    for _, history in ipairs(histories) do
      if total >= 30 then
        break
      end
      total = total + 1
      local author = history.author and (history.author.displayName or history.author.name) or "Unknown"
      local timestamp = utils.format_date(history.created)
      table.insert(lines, string.format("[%s] %s", timestamp ~= "" and timestamp or "--", author))
      for _, item in ipairs(history.items or {}) do
        local from = item.fromString or item.from or ""
        local to = item.toString or item.to or ""
        table.insert(lines, string.format("  %s: %s -> %s", item.field or item.fieldId or "field", utils.blank_if_nil(from), utils.blank_if_nil(to)))
      end
      table.insert(lines, "")
    end
  end

  if #lines == 0 then
    return { "No recent activity." }
  end

  return lines
end

local function main_lines(issue, width)
  local fields = issue.fields or {}
  local summary = fields.summary or "(no summary)"
  local description = utils.requested_description(issue)
  if description == "" then
    description = "No description available."
  end

  local lines = {}
  table.insert(lines, string.format("%s — %s", issue.key, summary))
  table.insert(lines, string.rep("=", math.max(20, width)))
  table.insert(lines, "Description")
  table.insert(lines, string.rep("-", math.max(10, width)))
  for _, line in ipairs(utils.wrap_text(description, math.max(20, width))) do
    table.insert(lines, line)
  end
  table.insert(lines, "")
  table.insert(lines, "Activity")
  table.insert(lines, string.rep("-", math.max(10, width)))
  for _, line in ipairs(collect_activity(issue, width)) do
    table.insert(lines, line)
  end
  table.insert(lines, "")
  table.insert(lines, string.rep("-", math.max(10, width)))
  table.insert(lines, "Controls: q/Esc to close • o to open in browser")
  return lines
end

local function fill_buffer(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "jira_popup"
  vim.bo[buf].swapfile = false
end

local function map_popup_keys(buf, issue, config)
  vim.keymap.set("n", "q", function()
    Popup.close()
  end, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "<Esc>", function()
    Popup.close()
  end, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "o", function()
    local base = (config.api.base_url or vim.env.JIRA_BASE_URL or ""):gsub("/*$", "")
    if base == "" then
      vim.notify("jira.nvim: missing JIRA_BASE_URL; cannot open browser", vim.log.levels.WARN)
      return
    end
    utils.open_url(string.format("%s/browse/%s", base, issue.key))
  end, { buffer = buf, nowait = true, silent = true })
end

function Popup.render(issue, config)
  Popup.close()

  local dims = calculate_dimensions(config)
  local sidebar_width = math.max(24, math.floor(dims.width * 0.32))
  local main_width = dims.width - sidebar_width - 2
  if main_width < 40 then
    main_width = math.floor(dims.width * 0.65)
    sidebar_width = dims.width - main_width - 2
  end

  local main_buf = vim.api.nvim_create_buf(false, true)
  local sidebar_buf = vim.api.nvim_create_buf(false, true)

  fill_buffer(main_buf, main_lines(issue, main_width - 4))
  fill_buffer(sidebar_buf, sidebar_lines(issue, sidebar_width - 4))

  local border = config.popup.border or "rounded"
  local main_win = vim.api.nvim_open_win(main_buf, true, {
    relative = "editor",
    width = main_width,
    height = dims.height,
    col = dims.col,
    row = dims.row,
    style = "minimal",
    border = border,
    title = string.format(" JIRA %s ", issue.key),
    zindex = 50,
  })

  local sidebar_win = vim.api.nvim_open_win(sidebar_buf, false, {
    relative = "editor",
    width = sidebar_width,
    height = dims.height,
    col = dims.col + main_width + 1,
    row = dims.row,
    style = "minimal",
    border = border,
    title = " Details ",
    zindex = 49,
  })

  map_popup_keys(main_buf, issue, config)
  map_popup_keys(sidebar_buf, issue, config)

  state.main_win = main_win
  state.sidebar_win = sidebar_win
  state.buffers = { main_buf, sidebar_buf }
end

return Popup

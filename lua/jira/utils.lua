local utils = {}

local base64_alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function encode_base64(data)
  if not data or data == "" then
    return ""
  end

  return ((data:gsub(".", function(x)
    local bits = ""
    local byte = x:byte()
    for i = 8, 1, -1 do
      bits = bits .. ((byte % 2 ^ i - byte % 2 ^ (i - 1) > 0) and "1" or "0")
    end
    return bits
  end) .. "0000"):gsub("%d%d%d?%d?%d?%d?", function(chunk)
    if #chunk < 6 then
      return ""
    end
    local c = 0
    for i = 1, 6 do
      if chunk:sub(i, i) == "1" then
        c = c + 2 ^ (6 - i)
      end
    end
    return base64_alphabet:sub(c + 1, c + 1)
  end) .. ({ "", "==", "=" })[#data % 3 + 1])
end

function utils.encode_basic_auth(email, token)
  if not email or email == "" then
    return nil, "API email is missing (set config.api.email or $JIRA_API_EMAIL)"
  end
  if not token or token == "" then
    return nil, "API token is missing (set config.api.token, $JIRA_API_TOKEN, or $JIRA_API_KEY)"
  end
  return encode_base64(string.format("%s:%s", email, token))
end

local function json_decode(payload)
  if not payload or payload == "" then
    return nil
  end
  if vim.json and vim.json.decode then
    return vim.json.decode(payload)
  end
  return vim.fn.json_decode(payload)
end

utils.json_decode = json_decode

local function json_encode(payload)
  if payload == nil then
    return "null"
  end
  if vim.json and vim.json.encode then
    return vim.json.encode(payload)
  end
  return vim.fn.json_encode(payload)
end

utils.json_encode = json_encode

function utils.trim(text)
  return (text and text:gsub("^%s+", ""):gsub("%s+$", "")) or ""
end

function utils.url_encode(value)
  if value == nil then
    return ""
  end
  local text = tostring(value)
  text = text:gsub("\n", "\r\n")
  return text:gsub("([^%w%-_%.~])", function(char)
    return string.format("%%%02X", char:byte())
  end)
end

local function adf_node_to_text(node, indent)
  indent = indent or ""
  if not node then
    return ""
  end
  if type(node) == "string" then
    return node
  end
  local node_type = node.type
  if node_type == "text" then
    return node.text or ""
  end
  if node_type == "hardBreak" then
    return "\n"
  end
  local buffer = {}
  if node.content then
    for _, child in ipairs(node.content) do
      table.insert(buffer, adf_node_to_text(child, indent))
    end
  end
  local joined = table.concat(buffer)
  if node_type == "paragraph" or node_type == "heading" then
    return utils.trim(joined) .. "\n\n"
  end
  if node_type == "bulletList" or node_type == "orderedList" then
    local list_lines = {}
    for index, child in ipairs(node.content or {}) do
      local marker = node_type == "orderedList" and string.format("%d. ", index) or "- "
      table.insert(list_lines, indent .. marker .. utils.trim(adf_node_to_text(child, indent .. "  ")))
    end
    return table.concat(list_lines, "\n") .. "\n\n"
  end
  if node_type == "listItem" then
    return indent .. utils.trim(joined) .. "\n"
  end
  return joined
end

function utils.adf_to_text(value)
  if not value then
    return ""
  end
  if type(value) == "string" then
    return utils.trim(value)
  end
  if type(value) == "table" and value.content then
    local parts = {}
    for _, node in ipairs(value.content) do
      table.insert(parts, adf_node_to_text(node))
    end
    return utils.trim(table.concat(parts, ""))
  end
  return ""
end

function utils.html_to_text(html)
  if not html or html == "" then
    return ""
  end
  local text = html
  text = text:gsub("</p>", "\n\n")
  text = text:gsub("<br%s*/?>", "\n")
  text = text:gsub("<li>", "- ")
  text = text:gsub("</?[^>]+>", "")
  return utils.trim(text)
end

function utils.requested_description(issue)
  if not issue then
    return ""
  end
  local rendered = issue.renderedFields and issue.renderedFields.description
  if type(rendered) == "string" and rendered ~= "" then
    local plain = utils.html_to_text(rendered)
    if plain ~= "" then
      return plain
    end
  end
  local fields = issue.fields or {}
  local adf = utils.adf_to_text(fields.description)
  if adf ~= "" then
    return adf
  end
  return ""
end

function utils.wrap_text(text, width)
  width = width or 80
  local lines = {}
  if not text or text == "" then
    return lines
  end
  for paragraph in tostring(text):gmatch("[^\n]+") do
    local line = ""
    for word in paragraph:gmatch("%S+") do
      if line == "" then
        line = word
      elseif #line + 1 + #word <= width then
        line = line .. " " .. word
      else
        table.insert(lines, line)
        line = word
      end
    end
    if line ~= "" then
      table.insert(lines, line)
    end
    table.insert(lines, "")
  end
  if #lines > 0 and lines[#lines] == "" then
    table.remove(lines, #lines)
  end
  return lines
end

local function parse_jira_timestamp(value)
  if (vim and vim.NIL and value == vim.NIL) or not value or value == "" then
    return nil
  end
  if type(value) ~= "string" then
    return nil
  end
  local year, month, day, hour, minute, second = value:match("(%d+)%-(%d+)%-(%d+)T?(%d*):?(%d*):?(%d*)")
  if not year then
    return nil
  end
  return os.time({
    year = tonumber(year),
    month = tonumber(month),
    day = tonumber(day),
    hour = tonumber(hour) or 0,
    min = tonumber(minute) or 0,
    sec = tonumber(second) or 0,
  })
end

utils.parse_jira_timestamp = parse_jira_timestamp

function utils.format_date(value)
  if (vim and vim.NIL and value == vim.NIL) or not value or value == "" then
    return ""
  end
  if type(value) ~= "string" then
    return ""
  end
  local timestamp = parse_jira_timestamp(value)
  if not timestamp then
    return value
  end
  return os.date("%Y-%m-%d %H:%M", timestamp)
end

function utils.humanize_duration(seconds)
  seconds = tonumber(seconds) or 0
  if seconds <= 0 then
    return "Under 1m"
  end
  local remaining = seconds
  local units = {
    { label = "d", secs = 86400 },
    { label = "h", secs = 3600 },
    { label = "m", secs = 60 },
  }
  local parts = {}
  for _, unit in ipairs(units) do
    local value = math.floor(remaining / unit.secs)
    if value > 0 then
      table.insert(parts, string.format("%d%s", value, unit.label))
      remaining = remaining - (value * unit.secs)
    end
    if #parts == 2 then
      break
    end
  end
  if #parts == 0 then
    local minutes = math.floor(remaining / 60)
    if minutes > 0 then
      table.insert(parts, string.format("%dm", minutes))
    else
      table.insert(parts, "Under 1m")
    end
  end
  return table.concat(parts, " ")
end

function utils.comment_body(comment)
  if not comment then
    return ""
  end
  if type(comment.body) == "string" then
    return utils.trim(comment.body)
  end
  return utils.adf_to_text(comment.body)
end

function utils.open_url(url)
  if not url or url == "" then
    return
  end
  if vim.ui and vim.ui.open_url then
    vim.ui.open_url(url)
    return
  end
  local cmd
  if vim.fn.has("mac") == 1 or vim.fn.has("macunix") == 1 or (vim.loop and vim.loop.os_uname and vim.loop.os_uname().sysname == "Darwin") then
    cmd = { "open", url }
  elseif vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
    cmd = { "cmd.exe", "/c", "start", "", url }
  else
    cmd = { "xdg-open", url }
  end
  if cmd then
    vim.fn.jobstart(cmd, { detach = true })
  end
end

function utils.get_severity(issue)
  local fields = issue.fields or {}
  if fields.severity then
    return fields.severity.name or fields.severity.value or fields.severity
  end
  local names = issue.names or {}
  for field_id, label in pairs(names) do
    if type(label) == "string" and label:lower():find("severity") and fields[field_id] then
      local value = fields[field_id]
      if type(value) == "table" then
        return value.value or value.name or value.displayName or value.text
      end
      return value
    end
  end
  return nil
end

function utils.blank_if_nil(value)
  if value == nil then
    return "-"
  end
  if type(value) == "string" and value == "" then
    return "-"
  end
  return value
end

return utils

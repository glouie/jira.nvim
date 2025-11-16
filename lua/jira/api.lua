local utils = require("jira.utils")

local M = {}

local function run_command(args, callback)
  if vim.system then
    return vim.system(args, { text = true }, function(obj)
      if obj.code ~= 0 then
        local err = obj.stderr ~= "" and obj.stderr or string.format("curl exited with %d", obj.code)
        callback(nil, utils.trim(err))
        return
      end
      callback(obj.stdout, nil)
    end)
  end

  local stdout, stderr = {}, {}
  local ok, job = pcall(vim.fn.jobstart, args, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if not data then
        return
      end
      for _, chunk in ipairs(data) do
        if chunk ~= "" then
          table.insert(stdout, chunk)
        end
      end
    end,
    on_stderr = function(_, data)
      if not data then
        return
      end
      for _, chunk in ipairs(data) do
        if chunk ~= "" then
          table.insert(stderr, chunk)
        end
      end
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        callback(nil, table.concat(stderr, "\n"))
      else
        callback(table.concat(stdout, "\n"), nil)
      end
    end,
  })

  if not ok or job <= 0 then
    callback(nil, "failed to spawn curl - ensure it is available in PATH")
  end
end

local function normalize_base_url(url)
  if not url or url == "" then
    return ""
  end
  return url:gsub("/*$", "")
end

local function build_get_args(endpoint, auth_header)
  return {
    "curl",
    "-sS",
    "-f",
    "-X",
    "GET",
    "-H",
    "Accept: application/json",
    "-H",
    "Content-Type: application/json",
    "-H",
    "Authorization: Basic " .. auth_header,
    endpoint,
  }
end

local connection_error_codes = {
  [6] = true,
  [7] = true,
  [28] = true,
  [35] = true,
  [52] = true,
  [56] = true,
}

local connection_error_phrases = {
  "could not resolve host",
  "couldn't resolve host",
  "failed to connect",
  "could not connect",
  "couldn't connect",
  "unable to resolve host",
  "operation timed out",
  "timed out",
  "timeout",
  "ssl connect error",
  "connection refused",
  "connection reset",
  "empty reply from server",
}

local function looks_like_connection_problem(message)
  if message == "" then
    return false
  end
  local lower = message:lower()
  for _, needle in ipairs(connection_error_phrases) do
    if lower:find(needle, 1, true) then
      return true
    end
  end
  local curl_code = tonumber(message:match("curl:%s*%((%d+)%)") or "")
  if curl_code and connection_error_codes[curl_code] then
    return true
  end
  return false
end

local function extract_http_status(message)
  local status = message:match("error:%s*(%d+)")
  if status then
    return tonumber(status)
  end
  return nil
end

local function format_subject_label(issue_key)
  if issue_key and issue_key ~= "" then
    return issue_key
  end
  return "the requested issue"
end

local function format_connection_error(subject_label, base_url)
  local target = subject_label or "the requested resource"
  local location = ""
  if base_url and base_url ~= "" then
    location = string.format(" at %s", base_url)
  end
  return string.format("Unable to reach Jira%s while loading %s. Check your network/VPN connection and try again.", location, target)
end

local function parse_issue_key(issue_key)
  if not issue_key or issue_key == "" then
    return nil, nil
  end
  local project, number = issue_key:match("^([%a%d]+)%-(%d+)$")
  if not project then
    return nil, nil
  end
  return project:upper(), number
end

local function humanize_remote_error(err, issue_key, opts)
  opts = opts or {}
  local message = utils.trim(err or "")
  local subject_label = opts.subject_label or format_subject_label(issue_key)
  local base_url = opts.base_url or ""
  if message == "" then
    return string.format("Jira responded with an empty error message while loading %s.", subject_label)
  end
  if looks_like_connection_problem(message) then
    return format_connection_error(subject_label, base_url)
  end
  local status = extract_http_status(message)
  if status == 404 then
    return string.format("%s was not found or you don't have access to it.", subject_label)
  elseif status == 401 then
    return string.format("Jira rejected the credentials provided (401 Unauthorized) while loading %s. Verify your API email and token.", subject_label)
  elseif status == 403 then
    return string.format("You don't have permission to view %s (403 Forbidden).", subject_label)
  elseif status == 429 then
    return string.format("Jira rate limited the request for %s (429 Too Many Requests). Give it a moment and try again.", subject_label)
  elseif status and status >= 500 and status < 600 then
    return string.format("Jira returned a server error (%d) while loading %s. Try again shortly.", status, subject_label)
  end
  return string.format("Unexpected error while talking to Jira about %s: %s", subject_label, message)
end

local function check_project_exists(project_key, base_url, auth, issue_key, callback)
  if not project_key or project_key == "" then
    callback(nil, string.format("%s was not found or you don't have access to it.", format_subject_label(issue_key)))
    return
  end
  local endpoint = string.format("%s/rest/api/3/project/%s", base_url, project_key)
  run_command(build_get_args(endpoint, auth), function(_, err)
    if err then
      local message = utils.trim(err or "")
      if looks_like_connection_problem(message) then
        callback(nil, format_connection_error(string.format("project %s referenced by %s", project_key, format_subject_label(issue_key)), base_url))
        return
      end
      local status = extract_http_status(message)
      if status == 404 then
        callback(false, nil)
        return
      end
      callback(nil, humanize_remote_error(message, issue_key, {
        base_url = base_url,
        subject_label = string.format("project %s referenced by %s", project_key, format_subject_label(issue_key)),
      }))
      return
    end
    callback(true, nil)
  end)
end

local function explain_missing_issue(issue_key, base_url, auth, callback)
  local subject_label = format_subject_label(issue_key)
  local project_key = parse_issue_key(issue_key)
  if not project_key then
    callback(string.format("%s was not found or you don't have access to it.", subject_label))
    return
  end
  check_project_exists(project_key, base_url, auth, issue_key, function(exists, err_message)
    if err_message then
      callback(err_message)
      return
    end
    if exists then
      callback(string.format("%s does not exist in project %s.", subject_label, project_key))
    else
      callback(string.format("Project %s referenced by %s was not found or you don't have access to it.", project_key, subject_label))
    end
  end)
end

local function handle_fetch_issue_error(err, issue_key, base_url, auth, callback)
  local message = utils.trim(err or "")
  if looks_like_connection_problem(message) then
    callback(nil, format_connection_error(format_subject_label(issue_key), base_url))
    return
  end
  local status = extract_http_status(message)
  if status == 404 then
    explain_missing_issue(issue_key, base_url, auth, function(resolved_message)
      callback(nil, resolved_message)
    end)
    return
  end
  callback(nil, humanize_remote_error(message, issue_key, { base_url = base_url }))
end

function M.fetch_issue(issue_key, config, callback)
  local api_config = config.api or {}
  local base_url = normalize_base_url(api_config.base_url or vim.env.JIRA_BASE_URL or "")
  if base_url == "" then
    callback(nil, "Jira base URL is not configured. Set config.api.base_url or the JIRA_BASE_URL environment variable.")
    return
  end

  local auth, auth_err = utils.encode_basic_auth(api_config.email or vim.env.JIRA_API_EMAIL, api_config.token or vim.env.JIRA_API_TOKEN or vim.env.JIRA_API_KEY)
  if not auth then
    callback(nil, string.format("Jira credentials are incomplete: %s. Provide config.api.email/token or the JIRA_API_EMAIL/JIRA_API_TOKEN variables.", auth_err))
    return
  end

  local endpoint = string.format("%s/rest/api/3/issue/%s?expand=renderedFields,changelog,names,comment", base_url, issue_key)
  local args = build_get_args(endpoint, auth)

  run_command(args, function(payload, err)
    if err then
      handle_fetch_issue_error(err, issue_key, base_url, auth, callback)
      return
    end
    local ok, body = pcall(utils.json_decode, payload)
    if not ok then
      callback(nil, string.format("Jira returned a response that could not be parsed while loading %s.", format_subject_label(issue_key)))
      return
    end
    callback(body, nil)
  end)
end

return M

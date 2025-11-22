local utils = require("jira.utils")

local M = {}

local function resolve_log_path()
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
  local fallback = vim.fn.stdpath("cache")
  return fallback .. "/jira.nvim/api_access.log"
end

local function ensure_log_directory(path)
  local dir = vim.fn.fnamemodify(path, ":p:h")
  if dir ~= "" then
    pcall(vim.fn.mkdir, dir, "p")
  end
end

local api_log_path = resolve_log_path()
ensure_log_directory(api_log_path)

local function log_api_access(event, details)
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  local message = string.format("[%s] %s: %s\n", timestamp, event, details or "")
  local ok, file = pcall(io.open, api_log_path, "a")
  if not ok or not file then
    return
  end
  file:write(message)
  file:close()
end

local function sanitize_args(args)
  local sanitized = {}
  local i = 1
  while i <= #args do
    local arg = args[i]
    if arg == "-H" then
      local header = args[i + 1]
      table.insert(sanitized, arg)
      if type(header) == "string" and header:lower():find("^authorization:%s*basic") then
        table.insert(sanitized, "Authorization: Basic [REDACTED]")
      elseif header ~= nil then
        table.insert(sanitized, header)
      end
      i = i + 2
    else
      table.insert(sanitized, arg)
      i = i + 1
    end
  end
  return sanitized
end

local function format_args_for_log(args)
  local ok, inspected = pcall(vim.inspect, args)
  if ok and inspected then
    return inspected
  end
  return table.concat(args, " ")
end

local function run_command(args, callback)
  log_api_access("REQUEST", format_args_for_log(sanitize_args(args)))
  if vim.system then
    return vim.system(args, { text = true }, function(obj)
      if obj.code ~= 0 then
        local err = obj.stderr ~= "" and obj.stderr or string.format("curl exited with %d", obj.code)
        log_api_access("ERROR", string.format("exit=%d\n%s", obj.code, utils.trim(err)))
        callback(nil, utils.trim(err))
        return
      end
      log_api_access("RESPONSE", obj.stdout or "")
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
        local err = table.concat(stderr, "\n")
        log_api_access("ERROR", string.format("exit=%d\n%s", code, err))
        callback(nil, err)
        return
      end
      local output = table.concat(stdout, "\n")
      log_api_access("RESPONSE", output)
      callback(output, nil)
    end,
  })

  if not ok or job <= 0 then
    log_api_access("ERROR", "failed to spawn curl - ensure it is available in PATH")
    callback(nil, "failed to spawn curl - ensure it is available in PATH")
  end
end

local function normalize_base_url(url)
  if not url or url == "" then
    return ""
  end
  return url:gsub("/*$", "")
end

local function build_request_args(method, endpoint, auth_header, body)
  local args = {
    "curl",
    "-sS",
    "-f",
    "-X",
    method,
    "-H",
    "Accept: application/json",
    "-H",
    "Content-Type: application/json",
    "-H",
    "Authorization: Basic " .. auth_header,
  }
  if body and body ~= "" then
    table.insert(args, "-d")
    table.insert(args, body)
  end
  table.insert(args, endpoint)
  return args
end

local function build_get_args(endpoint, auth_header)
  return build_request_args("GET", endpoint, auth_header)
end

local function build_post_args(endpoint, auth_header, body)
  return build_request_args("POST", endpoint, auth_header, body)
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

local function assignment_jql(config)
  local assigned = (config and config.assigned_popup) or {}
  local jql = assigned.jql or "assignee = currentUser() AND resolution = Unresolved AND statusCategory != Done ORDER BY updated DESC"
  return utils.trim(jql)
end

local function clamp_page_size(size)
  local limit = tonumber(size) or 50
  if limit < 1 then
    return 1
  end
  if limit > 200 then
    return 200
  end
  return limit
end

local function assignment_limit(config)
  local assigned = (config and config.assigned_popup) or {}
  return clamp_page_size(assigned.max_results)
end

local function issue_summary_entry(issue, base_url)
  local fields = issue.fields or {}
  if vim and vim.NIL then
    if fields == vim.NIL then
      fields = {}
    end
    if fields.summary == vim.NIL then
      fields.summary = ""
    end
  end
  local status = fields.status or {}
  if vim and vim.NIL and status == vim.NIL then
    status = {}
  end
  local status_name = status.name or status.displayName or ""
  return {
    key = issue.key,
    summary = fields.summary or "",
    status = status_name,
    url = base_url ~= "" and string.format("%s/browse/%s", base_url, issue.key) or "",
  }
end

local function map_assigned_issues(payload, base_url)
  local issues = {}
  local issue_list = payload.issues
  if (vim and vim.NIL and issue_list == vim.NIL) or type(issue_list) ~= "table" then
    return issues
  end
  for _, issue in ipairs(issue_list) do
    local fields = issue.fields or {}
    if vim and vim.NIL and fields == vim.NIL then
      fields = {}
    end
    local status = fields.status or {}
    if vim and vim.NIL and status == vim.NIL then
      status = {}
    end
    local category = status.statusCategory or {}
    if vim and vim.NIL and category == vim.NIL then
      category = {}
    end
    local category_key = (category.key or category.name or ""):lower()
    local resolution = fields.resolution
    local resolved = resolution ~= nil and resolution ~= vim.NIL
    local is_done = category_key == "done" or category_key == "complete"
    if not resolved and not is_done then
      table.insert(issues, issue_summary_entry(issue, base_url))
    end
  end
  return issues
end

local function map_search_issues(payload, base_url)
  local issues = {}
  local issue_list = payload.issues
  if (vim and vim.NIL and issue_list == vim.NIL) or type(issue_list) ~= "table" then
    return issues
  end
  for _, issue in ipairs(issue_list) do
    table.insert(issues, issue_summary_entry(issue, base_url))
  end
  return issues
end

function M.fetch_assigned_issues(config, opts, callback)
  if type(opts) == "function" then
    callback = opts
    opts = {}
  end
  opts = opts or {}
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

  local endpoint_base = string.format("%s/rest/api/3/search/jql", base_url)
  local jql = assignment_jql(config)
  local limit = assignment_limit(config)
  local start_at = math.max(0, tonumber(opts.start_at) or 0)
  local fields = { "key", "summary", "status", "resolution" }

  local function decode_response(payload)
    local ok, body = pcall(utils.json_decode, payload)
    if not ok or type(body) ~= "table" then
      callback(nil, "Jira returned a response that could not be parsed while listing your assigned issues.")
      return
    end
    local issues = map_assigned_issues(body, base_url)
    local response = {
      issues = issues,
      total = tonumber(body.total) or #issues,
      start_at = tonumber(body.startAt) or start_at,
      max_results = tonumber(body.maxResults) or limit,
    }
    callback(response, nil)
  end

  local function handle_error(err)
    callback(nil, humanize_remote_error(err, "your assigned issues", { base_url = base_url, subject_label = "your assigned issues" }))
  end

  local function perform_post()
    local payload_table = {
      jql = jql,
      maxResults = limit,
      fields = fields,
    }
    if start_at > 0 then
      payload_table.startAt = start_at
    end
    local payload = utils.json_encode(payload_table)
    run_command(build_post_args(endpoint_base, auth, payload), function(body, err)
      if err then
        handle_error(err)
        return
      end
      decode_response(body)
    end)
  end

  perform_post()
end

function M.search_issues(config, params, callback)
  params = params or {}
  local jql = utils.trim(params.jql or "")
  if jql == "" then
    callback(nil, "A JQL query is required.")
    return
  end
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
  local start_at = math.max(0, tonumber(params.start_at) or 0)
  local limit = clamp_page_size(params.max_results or (config.search_popup and config.search_popup.max_results) or 50)
  local fields = params.fields or { "key", "summary", "status" }
  local endpoint = string.format("%s/rest/api/3/search/jql", base_url)
  local payload_table = {
    jql = jql,
    maxResults = limit,
    fields = fields,
  }
  if start_at > 0 then
    payload_table.startAt = start_at
  end
  local payload = utils.json_encode(payload_table)
  run_command(build_post_args(endpoint, auth, payload), function(body, err)
    if err then
      callback(nil, humanize_remote_error(err, "your JQL search", { base_url = base_url, subject_label = string.format("JQL query (%s)", jql) }))
      return
    end
    local ok, data = pcall(utils.json_decode, body)
    if not ok or type(data) ~= "table" then
      callback(nil, "Jira returned a response that could not be parsed while running your JQL search.")
      return
    end
    local mapped = map_search_issues(data, base_url)
    callback({
      issues = mapped,
      total = tonumber(data.total) or #mapped,
      start_at = tonumber(data.startAt) or start_at,
      max_results = tonumber(data.maxResults) or limit,
      jql = jql,
    }, nil)
  end)
end

return M

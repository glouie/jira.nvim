---HTTP helpers for interacting with Jira's REST API via curl.
-- Handles request construction, logging, error normalization, and higher-level fetch helpers.

local utils = require("jira.utils")

local M = {}

---Resolve the absolute path for the API access log file.
---@return string path Filesystem path used for API request/response logs.
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

---Ensure the directory for the given log path exists.
---@param path string Path to the log file.
---@return nil
local function ensure_log_directory(path)
  local dir = vim.fn.fnamemodify(path, ":p:h")
  if dir ~= "" then
    pcall(vim.fn.mkdir, dir, "p")
  end
end

local api_log_path = resolve_log_path()
ensure_log_directory(api_log_path)

---Append a structured API access log entry to disk.
---@param event string Short event label such as "REQUEST" or "ERROR".
---@param details string|nil Additional text payload to log.
---@return nil
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

---Strip sensitive fields from curl argument lists before logging.
---@param args string[] Raw curl arguments including headers.
---@return string[] sanitized Arguments with secrets like Authorization masked.
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

---Format curl arguments into a readable string for logs.
---@param args string[] Argument list to format.
---@return string text Space-joined representation with quotes preserved.
local function format_args_for_log(args)
  local parts = {}
  for _, arg in ipairs(args) do
    local text = tostring(arg)
    if text:find("%s") then
      text = string.format("'%s'", text)
    end
    table.insert(parts, text)
  end
  return table.concat(parts, " ")
end

---Run a curl command asynchronously and capture output.
---@param args string[] Curl argument list.
---@param callback fun(stdout:string|nil, err:string|nil) Invoked with stdout or error string.
---@return any job_handle Handle returned by the chosen job runner.
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

---Construct the curl argument list for a Jira REST request.
---@param method string HTTP method (GET/POST/etc).
---@param endpoint string Fully qualified Jira endpoint URL.
---@param auth_header string Base64-encoded Basic auth header value.
---@param body string|nil Optional JSON payload.
---@return string[] args Curl command arguments.
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

---Build curl arguments for a GET request.
---@param endpoint string Target Jira endpoint URL.
---@param auth_header string Basic auth header value.
---@return string[] args Curl command arguments.
local function build_get_args(endpoint, auth_header)
  return build_request_args("GET", endpoint, auth_header)
end

---Build curl arguments for a POST request.
---@param endpoint string Target Jira endpoint URL.
---@param auth_header string Basic auth header value.
---@param body string JSON payload to send.
---@return string[] args Curl command arguments.
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

---Extract an HTTP status code from a curl error message.
---@param message string Error output from curl.
---@return integer|nil status Parsed HTTP status or nil.
local function extract_http_status(message)
  local status = message:match("error:%s*(%d+)")
  if status then
    return tonumber(status)
  end
  return nil
end

---Heuristically detect network or connection errors from curl output.
---@param message string Error output from curl.
---@return boolean is_connection_problem True when the error appears to be connectivity related.
local function looks_like_connection_problem(message)
  if message == "" then
    return false
  end
  if extract_http_status(message) then
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

---Format a readable label for an issue or target resource.
---@param issue_key string|nil Issue key if available.
---@return string label Human-friendly subject label.
local function format_subject_label(issue_key)
  if issue_key and issue_key ~= "" then
    return issue_key
  end
  return "the requested issue"
end

---Generate a friendly connection error message referencing the base URL.
---@param subject_label string|nil Subject being loaded (issue/project/etc).
---@param base_url string|nil Jira base URL.
---@return string message Human-readable guidance about connectivity.
local function format_connection_error(subject_label, base_url)
  local target = subject_label or "the requested resource"
  local location = ""
  if base_url and base_url ~= "" then
    location = string.format(" at %s", base_url)
  end
  return string.format(
    "Unable to reach Jira%s while loading %s. Check your network/VPN connection and try again.",
    location,
    target
  )
end

---Split an issue key into project and number components.
---@param issue_key string|nil Issue key like "ABC-123".
---@return string|nil project Normalized project key or nil.
---@return string|nil number Issue number text or nil.
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

---Translate a raw Jira error into a user-friendly message.
---@param err string|nil Raw error output.
---@param issue_key string|nil Issue key for context.
---@param opts table|nil Additional context such as subject_label/base_url.
---@return string message Friendly error description.
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
    return string.format(
      "Jira rejected the credentials provided (401 Unauthorized) while loading %s. Verify your API email and token.",
      subject_label
    )
  elseif status == 403 then
    return string.format("You don't have permission to view %s (403 Forbidden).", subject_label)
  elseif status == 429 then
    return string.format(
      "Jira rate limited the request for %s (429 Too Many Requests). Give it a moment and try again.",
      subject_label
    )
  elseif status and status >= 500 and status < 600 then
    return string.format(
      "Jira returned a server error (%d) while loading %s. Try again shortly.",
      status,
      subject_label
    )
  end
  return string.format("Unexpected error while talking to Jira about %s: %s", subject_label, message)
end

---Check whether a referenced project exists, handling network/status errors.
---@param project_key string|nil Project key extracted from an issue key.
---@param base_url string Jira base URL.
---@param auth string Basic auth header.
---@param issue_key string|nil Issue key for context.
---@param callback fun(exists:boolean|nil, err:string|nil) Called with existence flag or error.
---@return nil
local function check_project_exists(project_key, base_url, auth, issue_key, callback)
  if not project_key or project_key == "" then
    callback(
      nil,
      string.format("%s was not found or you don't have access to it.", format_subject_label(issue_key))
    )
    return
  end
  local endpoint = string.format("%s/rest/api/3/project/%s", base_url, project_key)
  run_command(build_get_args(endpoint, auth), function(_, err)
    if err then
      local message = utils.trim(err or "")
      if looks_like_connection_problem(message) then
        callback(
          nil,
          format_connection_error(
            string.format("project %s referenced by %s", project_key, format_subject_label(issue_key)),
            base_url
          )
        )
        return
      end
      local status = extract_http_status(message)
      if status == 404 then
        callback(false, nil)
        return
      end
      callback(
        nil,
        humanize_remote_error(message, issue_key, {
          base_url = base_url,
          subject_label = string.format(
            "project %s referenced by %s",
            project_key,
            format_subject_label(issue_key)
          ),
        })
      )
      return
    end
    callback(true, nil)
  end)
end

---Provide a targeted explanation for a missing issue response.
---@param issue_key string|nil Issue key that could not be fetched.
---@param base_url string Jira base URL.
---@param auth string Basic auth header.
---@param callback fun(message:string) Called with resolved error string.
---@return nil
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
      callback(
        string.format(
          "Project %s referenced by %s was not found or you don't have access to it.",
          project_key,
          subject_label
        )
      )
    end
  end)
end

---Handle errors from the issue fetch request, mapping to readable messages.
---@param err string|nil Raw error output.
---@param issue_key string|nil Issue key requested.
---@param base_url string Jira base URL.
---@param auth string Basic auth header.
---@param callback fun(issue:nil, err:string|nil) Called with nil issue and friendly error.
---@return nil
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

---Fetch a single Jira issue and decode its payload.
---@param issue_key string Issue key such as "ABC-123".
---@param config table Plugin configuration containing API credentials and base URL.
---@param callback fun(issue:table|nil, err:string|nil) Invoked with the parsed issue table or an error message.
---@return nil
function M.fetch_issue(issue_key, config, callback)
  local api_config = config.api or {}
  local base_url = normalize_base_url(api_config.base_url or vim.env.JIRA_BASE_URL or "")
  if base_url == "" then
    callback(
      nil,
      "Jira base URL is not configured. Set config.api.base_url or the JIRA_BASE_URL environment variable."
    )
    return
  end

  local auth, auth_err = utils.encode_basic_auth(
    api_config.email or vim.env.JIRA_API_EMAIL,
    api_config.token or vim.env.JIRA_API_TOKEN or vim.env.JIRA_API_KEY
  )
  if not auth then
    callback(
      nil,
      string.format(
        "Jira credentials are incomplete: %s. Provide config.api.email/token or the JIRA_API_EMAIL/JIRA_API_TOKEN variables.",
        auth_err
      )
    )
    return
  end

  local endpoint =
      string.format("%s/rest/api/3/issue/%s?expand=renderedFields,changelog,names,comment", base_url, issue_key)
  local args = build_get_args(endpoint, auth)

  run_command(args, function(payload, err)
    if err then
      handle_fetch_issue_error(err, issue_key, base_url, auth, callback)
      return
    end
    local ok, body = pcall(utils.json_decode, payload)
    if not ok then
      callback(
        nil,
        string.format(
          "Jira returned a response that could not be parsed while loading %s.",
          format_subject_label(issue_key)
        )
      )
      return
    end
    callback(body, nil)
  end)
end

---Resolve the default JQL for the assigned issues popup.
---@param config table|nil Plugin configuration.
---@return string jql Trimmed JQL statement.
local function assignment_jql(config)
  local assigned = (config and config.assigned_popup) or {}
  local jql = assigned.jql
      or "assignee = currentUser() AND resolution = Unresolved AND statusCategory != Done ORDER BY updated DESC"
  return utils.trim(jql)
end

---Clamp the configured page size to Jira's supported bounds.
---@param size number|nil Desired max results.
---@return integer limit Page size between 1 and 200.
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

---Resolve the max results setting for the assigned issues popup.
---@param config table|nil Plugin configuration.
---@return integer limit Page size to request.
local function assignment_limit(config)
  local assigned = (config and config.assigned_popup) or {}
  return clamp_page_size(assigned.max_results)
end

---Map a Jira issue payload into a condensed summary for list display.
---@param issue table Jira issue object.
---@param base_url string Jira base URL.
---@return table summary Simplified issue fields.
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

---Filter and map assigned issues to summaries, omitting resolved/done items.
---@param payload table Jira search response.
---@param base_url string Jira base URL.
---@return table[] issues Collection of simplified issue entries.
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

---Map arbitrary search results to simplified summaries.
---@param payload table Jira search response.
---@param base_url string Jira base URL.
---@return table[] issues Collection of simplified issue entries.
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

---List unresolved issues assigned to the current user.
---@param config table Plugin configuration containing API credentials and popup settings.
---@param opts table|fun Result override such as pagination; or callback when opts omitted.
---@param callback fun(result:table|nil, err:string|nil) Invoked with issues, totals, and pagination or an error message.
---@return nil
function M.fetch_assigned_issues(config, opts, callback)
  if type(opts) == "function" then
    callback = opts
    opts = {}
  end
  opts = opts or {}
  local api_config = config.api or {}
  local base_url = normalize_base_url(api_config.base_url or vim.env.JIRA_BASE_URL or "")
  if base_url == "" then
    callback(
      nil,
      "Jira base URL is not configured. Set config.api.base_url or the JIRA_BASE_URL environment variable."
    )
    return
  end
  local auth, auth_err = utils.encode_basic_auth(
    api_config.email or vim.env.JIRA_API_EMAIL,
    api_config.token or vim.env.JIRA_API_TOKEN or vim.env.JIRA_API_KEY
  )
  if not auth then
    callback(
      nil,
      string.format(
        "Jira credentials are incomplete: %s. Provide config.api.email/token or the JIRA_API_EMAIL/JIRA_API_TOKEN variables.",
        auth_err
      )
    )
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
    callback(
      nil,
      humanize_remote_error(
        err,
        "your assigned issues",
        { base_url = base_url, subject_label = "your assigned issues" }
      )
    )
  end

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

---Run an arbitrary JQL search and return a simplified issue list.
---@param config table Plugin configuration containing API credentials and search defaults.
---@param params table JQL query parameters (jql, pagination, fields, expand, next_page_token).
---@param callback fun(result:table|nil, err:string|nil) Invoked with mapped search results or an error message.
---@return nil
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
    callback(
      nil,
      "Jira base URL is not configured. Set config.api.base_url or the JIRA_BASE_URL environment variable."
    )
    return
  end
  local auth, auth_err = utils.encode_basic_auth(
    api_config.email or vim.env.JIRA_API_EMAIL,
    api_config.token or vim.env.JIRA_API_TOKEN or vim.env.JIRA_API_KEY
  )
  if not auth then
    callback(
      nil,
      string.format(
        "Jira credentials are incomplete: %s. Provide config.api.email/token or the JIRA_API_EMAIL/JIRA_API_TOKEN variables.",
        auth_err
      )
    )
    return
  end
  local limit = clamp_page_size(params.max_results or (config.search_popup and config.search_popup.max_results) or 50)
  local fields = type(params.fields) == "table" and params.fields or { "key", "summary", "status" }
  local fields_by_keys = params.fields_by_keys
  local expand = type(params.expand) == "table" and params.expand or nil
  local next_page_token = params.next_page_token or params.nextPageToken
  local start_at = math.max(0, tonumber(params.start_at) or 0)
  local endpoint_base = string.format("%s/rest/api/3/search/jql", base_url)

  local function decode_response(data)
    local mapped = map_search_issues(data, base_url)
    callback({
      issues = mapped,
      total = tonumber(data.total) or #mapped,
      start_at = tonumber(data.startAt) or (start_at > 0 and start_at or nil),
      max_results = tonumber(data.maxResults) or limit,
      jql = jql,
      next_page_token = data.nextPageToken,
    }, nil)
  end

  local function handle_error(err)
    callback(
      nil,
      humanize_remote_error(
        err,
        "your JQL search",
        { base_url = base_url, subject_label = string.format("JQL query (%s)", jql) }
      )
    )
  end

  local payload = {
    jql = jql,
    maxResults = limit,
    fields = fields,
  }
  if fields_by_keys ~= nil then
    payload.fieldsByKeys = fields_by_keys
  end
  if expand and #expand > 0 then
    payload.expand = expand
  end
  if next_page_token and next_page_token ~= "" then
    payload.nextPageToken = next_page_token
  end
  if start_at > 0 then
    payload.startAt = start_at
  end
  local post_payload = utils.json_encode(payload)

  local args = build_post_args(endpoint_base, auth, post_payload)
  run_command(args, function(body, err)
    if err then
      handle_error(err)
      return
    end
    local ok, data = pcall(utils.json_decode, body)
    if not ok or type(data) ~= "table" then
      handle_error("Jira returned a response that could not be parsed while running your JQL search.")
      return
    end
    decode_response(data)
  end)
end

---Normalize mixed autocomplete values into a list of strings.
---@param list table|string[]|nil Raw list from Jira autocomplete endpoints.
---@return string[] normalized Flattened string values.
local function normalize_string_list(list)
  local normalized = {}
  local source = type(list) == "table" and list or {}
  for _, entry in ipairs(source) do
    if type(entry) == "string" then
      table.insert(normalized, entry)
    elseif type(entry) == "table" then
      local value = entry.value or entry.text or entry.name or entry.displayName
      if type(value) == "string" then
        table.insert(normalized, value)
      end
    end
  end
  return normalized
end

---Convert autocomplete payload arrays into string lists.
---@param payload table|nil Raw autocomplete response.
---@return table data Normalized fields/functions/keywords lists.
local function map_autocomplete_data(payload)
  if type(payload) ~= "table" then
    return {}
  end
  return {
    fields = normalize_string_list(payload.visibleFieldNames),
    functions = normalize_string_list(payload.visibleFunctionNames),
    keywords = normalize_string_list(payload.jqlReservedWords),
  }
end

---Extract suggestion strings from a JQL suggestions response.
---@param payload table|nil Jira autocomplete suggestions response.
---@return string[] suggestions List of suggestion texts.
local function map_suggestion_list(payload)
  local suggestions = {}
  local list = nil
  if type(payload) == "table" then
    if type(payload.suggestions) == "table" then
      list = payload.suggestions
    elseif type(payload.results) == "table" then
      list = payload.results
    end
  end
  for _, entry in ipairs(list or {}) do
    if type(entry) == "string" then
      table.insert(suggestions, entry)
    elseif type(entry) == "table" then
      local value = entry.text or entry.displayName or entry.value or entry.name
      if type(value) == "string" and value ~= "" then
        table.insert(suggestions, value)
      end
    end
  end
  return suggestions
end

---Retrieve autocomplete metadata for JQL fields, functions, and keywords.
---@param config table Plugin configuration containing API credentials and base URL.
---@param callback fun(data:table|nil, err:string|nil) Invoked with autocomplete data or an error message.
---@return nil
function M.fetch_jql_autocomplete(config, callback)
  local api_config = config.api or {}
  local base_url = normalize_base_url(api_config.base_url or vim.env.JIRA_BASE_URL or "")
  if base_url == "" then
    callback(
      nil,
      "Jira base URL is not configured. Set config.api.base_url or the JIRA_BASE_URL environment variable."
    )
    return
  end
  local auth, auth_err = utils.encode_basic_auth(
    api_config.email or vim.env.JIRA_API_EMAIL,
    api_config.token or vim.env.JIRA_API_TOKEN or vim.env.JIRA_API_KEY
  )
  if not auth then
    callback(
      nil,
      string.format(
        "Jira credentials are incomplete: %s. Provide config.api.email/token or the JIRA_API_EMAIL/JIRA_API_TOKEN variables.",
        auth_err
      )
    )
    return
  end
  local endpoint = string.format("%s/rest/api/3/jql/autocompletedata", base_url)
  run_command(build_get_args(endpoint, auth), function(body, err)
    if err then
      callback(nil, humanize_remote_error(err, "JQL suggestions", { base_url = base_url }))
      return
    end
    local ok, data = pcall(utils.json_decode, body)
    if not ok or type(data) ~= "table" then
      callback(nil, "Jira returned a response that could not be parsed while loading JQL autocomplete data.")
      return
    end
    callback(map_autocomplete_data(data), nil)
  end)
end

---Fetch value suggestions for a specific JQL field and prefix.
---@param config table Plugin configuration containing API credentials and base URL.
---@param opts table|fun Options including `field`/`field_name` and `value`/`prefix`; or callback when opts omitted.
---@param callback fun(result:table|nil, err:string|nil) Invoked with suggestion strings or an error message.
---@return nil
function M.fetch_jql_suggestions(config, opts, callback)
  opts = opts or {}
  if type(opts) == "function" then
    callback = opts
    opts = {}
  end
  local field_name = utils.trim(opts.field or opts.field_name or "")
  local input_value = utils.trim(opts.value or opts.prefix or "")
  if field_name == "" or input_value == "" then
    callback({ suggestions = {} }, nil)
    return
  end
  local api_config = config.api or {}
  local base_url = normalize_base_url(api_config.base_url or vim.env.JIRA_BASE_URL or "")
  if base_url == "" then
    callback(
      nil,
      "Jira base URL is not configured. Set config.api.base_url or the JIRA_BASE_URL environment variable."
    )
    return
  end
  local auth, auth_err = utils.encode_basic_auth(
    api_config.email or vim.env.JIRA_API_EMAIL,
    api_config.token or vim.env.JIRA_API_TOKEN or vim.env.JIRA_API_KEY
  )
  if not auth then
    callback(
      nil,
      string.format(
        "Jira credentials are incomplete: %s. Provide config.api.email/token or the JIRA_API_EMAIL/JIRA_API_TOKEN variables.",
        auth_err
      )
    )
    return
  end
  local endpoint = string.format(
    "%s/rest/api/3/jql/autocompletedata/suggestions?fieldName=%s&fieldValue=%s",
    base_url,
    utils.url_encode(field_name),
    utils.url_encode(input_value)
  )
  run_command(build_get_args(endpoint, auth), function(body, err)
    if err then
      callback(
        nil,
        humanize_remote_error(
          err,
          "JQL suggestions",
          { base_url = base_url, subject_label = string.format("values for %s", field_name) }
        )
      )
      return
    end
    local ok, data = pcall(utils.json_decode, body)
    if not ok or type(data) ~= "table" then
      callback(nil, "Jira returned a response that could not be parsed while loading field suggestions.")
      return
    end
    callback({ suggestions = map_suggestion_list(data) }, nil)
  end)
end

return M

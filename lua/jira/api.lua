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

function M.fetch_issue(issue_key, config, callback)
  local api_config = config.api or {}
  local base_url = normalize_base_url(api_config.base_url or vim.env.JIRA_BASE_URL or "")
  if base_url == "" then
    callback(nil, "JIRA_BASE_URL is missing")
    return
  end

  local auth, auth_err = utils.encode_basic_auth(api_config.email or vim.env.JIRA_API_EMAIL, api_config.token or vim.env.JIRA_API_TOKEN or vim.env.JIRA_API_KEY)
  if not auth then
    callback(nil, auth_err)
    return
  end

  local endpoint = string.format("%s/rest/api/3/issue/%s?expand=renderedFields,changelog,names,comment", base_url, issue_key)
  local args = {
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
    "Authorization: Basic " .. auth,
    endpoint,
  }

  run_command(args, function(payload, err)
    if err then
      callback(nil, err)
      return
    end
    local ok, body = pcall(utils.json_decode, payload)
    if not ok then
      callback(nil, "failed to parse JIRA response")
      return
    end
    callback(body, nil)
  end)
end

return M

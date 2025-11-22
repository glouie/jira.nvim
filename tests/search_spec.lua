package.path = "lua/?.lua;" .. package.path

-- Minimal stubs for the Neovim API used by jira.api
local captured_calls = {}
local success_body = [[{"issues":[{"key":"TNT-1","fields":{"summary":"Demo","status":{"name":"Open"}}}],"total":1,"startAt":0,"maxResults":50,"nextPageToken":"next-token"}]]
local decoded_bodies = {
  [success_body] = {
    issues = {
      { key = "TNT-1", fields = { summary = "Demo", status = { name = "Open" } } },
    },
    total = 1,
    startAt = 0,
    maxResults = 50,
    nextPageToken = "next-token",
  },
}

local original_io_open = io.open
io.open = function()
  return {
    write = function() end,
    close = function() end,
  }
end

local original_vim = _G.vim
_G.vim = {
  env = {},
  fn = {
  fnamemodify = function() return "/tmp/jira.nvim" end,
  stdpath = function() return "/tmp" end,
  mkdir = function() end,
  jobstart = function() return -1 end,
  json_encode = function(tbl)
      local function escape(value)
        return tostring(value):gsub("\\", "\\\\"):gsub('"', '\\"')
      end
      local function encode_list(values)
        local parts = {}
      for _, value in ipairs(values or {}) do
        table.insert(parts, string.format('"%s"', escape(value)))
      end
      return table.concat(parts, ",")
      end
      local pieces = {
        string.format('"jql":"%s"', escape(tbl.jql)),
        string.format('"maxResults":%d', tbl.maxResults),
        string.format('"fields":[%s]', encode_list(tbl.fields)),
      }
      if tbl.expand and #tbl.expand > 0 then
        table.insert(pieces, string.format('"expand":[%s]', encode_list(tbl.expand)))
      end
      if tbl.nextPageToken then
        table.insert(pieces, string.format('"nextPageToken":"%s"', escape(tbl.nextPageToken)))
      end
      return "{" .. table.concat(pieces, ",") .. "}"
    end,
    json_decode = function(body)
      local decoded = decoded_bodies[body]
      if not decoded then
        error("unexpected decode payload: " .. tostring(body))
      end
      return decoded
    end,
  },
  json = {
    encode = function(tbl)
      return _G.vim.fn.json_encode(tbl)
    end,
    decode = function(body)
      return _G.vim.fn.json_decode(body)
    end,
  },
  call = original_vim and original_vim.call or function() end,
  inspect = function()
    return "[stub inspect]"
  end,
}
setmetatable(_G.vim, { __index = original_vim })
setmetatable(_G.vim.fn, { __index = original_vim and original_vim.fn })

local function detect_arg(args, flag)
  for i = 1, #args do
    if args[i] == flag then
      return args[i + 1]
    end
  end
  return nil
end

local function detect_endpoint(args)
  for i = #args, 1, -1 do
    local entry = args[i]
    if type(entry) == "string" and entry:match("^https?://") then
      return entry
    end
  end
  return args[#args]
end

vim.system = function(args, _, on_exit)
  local endpoint = detect_endpoint(args)
  local method = detect_arg(args, "-X") or args[5]
  local body = detect_arg(args, "-d") or args[#args - 1]
  local response
  if method == "POST" and endpoint:find("/rest/api/3/search", 1, true) then
    response = { code = 0, stdout = success_body, stderr = "" }
  else
    response = { code = 56, stdout = "", stderr = "curl: (56) Unexpected search request" }
  end
  table.insert(captured_calls, { method = method, url = endpoint, body = body })
  on_exit(response)
  return { wait = function() return response end }
end

local api = require("jira.api")

local result, err
api.search_issues({
  api = {
    base_url = "https://example.atlassian.net",
    email = "user@example.com",
    token = "apitoken",
  },
}, {
  jql = "project = TNT",
  next_page_token = "prev-token",
}, function(res, error_msg)
  result = res
  err = error_msg
end)

assert(err == nil, err or "unexpected search error")
assert(result and result.total == 1, "expected parsed search payload")
assert(result.next_page_token == "next-token", "expected next page token from search response")
assert(#captured_calls == 1, "expected single POST Jira search")
assert(captured_calls[1].method == "POST", "expected POST search request")
assert(captured_calls[1].url:find("/rest/api/3/search", 1, true), "expected /rest/api/3/search endpoint")
assert(captured_calls[1].body == [[{"jql":"project = TNT","maxResults":50,"fields":["key","summary","status"],"nextPageToken":"prev-token"}]], "unexpected search payload: " .. tostring(captured_calls[1].body))

_G.vim = original_vim
io.open = original_io_open
print("ok\tjira.api.search_issues posts JSON body to /search")

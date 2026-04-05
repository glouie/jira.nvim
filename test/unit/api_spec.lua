-- test/unit/api_spec.lua
-- Busted unit tests for lua/jira/api.lua pure logic.
-- Run with: busted test/unit/ --helper test/helper.lua

-- ── Minimal vim stub ──────────────────────────────────────────────────────────
_G.vim = _G.vim or {}

local dkjson = require("dkjson")
vim.json = {
  decode = function(s) return dkjson.decode(s) end,
  encode = function(v) return dkjson.encode(v) end,
}
vim.fn = vim.fn or {}
vim.fn.stdpath     = function() return "/tmp" end
vim.fn.fnamemodify = function(p, _) return p end
vim.fn.mkdir       = function() end
vim.log            = { levels = { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3 } }
vim.notify         = function() end
vim.schedule       = function(f) f() end
vim.NIL            = {}
vim.env            = {}

-- ── Load module under test ────────────────────────────────────────────────────
local api  = require("jira.api")
local test = api._test

assert(test,                    "api._test table is missing")
assert(test.extract_jira_error, "api._test.extract_jira_error is nil — check function ordering in api.lua")

-- ── extract_jira_error ────────────────────────────────────────────────────────
describe("extract_jira_error", function()

  it("returns nil for nil input", function()
    assert.is_nil(test.extract_jira_error(nil))
  end)

  it("returns nil for empty string", function()
    assert.is_nil(test.extract_jira_error(""))
  end)

  it("returns nil for non-JSON body", function()
    assert.is_nil(test.extract_jira_error("Not found"))
  end)

  it("returns nil for a normal success JSON body", function()
    assert.is_nil(test.extract_jira_error('{"id":"ABC-1","key":"ABC-1"}'))
  end)

  it("returns nil when errorMessages is empty and errors is empty", function()
    assert.is_nil(test.extract_jira_error('{"errorMessages":[],"errors":{}}'))
  end)

  it("parses a single errorMessages entry", function()
    local body = '{"errorMessages":["Issue does not exist or you do not have permission to see it."],"errors":{}}'
    assert.equals(
      "Issue does not exist or you do not have permission to see it.",
      test.extract_jira_error(body)
    )
  end)

  it("joins multiple errorMessages with a semicolon", function()
    local body = '{"errorMessages":["First error","Second error"],"errors":{}}'
    local result = test.extract_jira_error(body)
    assert.is_not_nil(result)
    assert.is_truthy(result:find("First error",  1, true))
    assert.is_truthy(result:find("Second error", 1, true))
    assert.is_truthy(result:find("; ",           1, true))
  end)

  it("parses a field-level errors object", function()
    local body = '{"errorMessages":[],"errors":{"summary":"Field required"}}'
    local result = test.extract_jira_error(body)
    assert.is_not_nil(result)
    assert.is_truthy(result:find("summary",       1, true))
    assert.is_truthy(result:find("Field required",1, true))
  end)

  it("parses the top-level message field", function()
    local body = '{"message":"Unauthorized","status-code":401}'
    assert.equals("Unauthorized", test.extract_jira_error(body))
  end)

  it("combines errorMessages and errors when both present", function()
    local body = '{"errorMessages":["Top-level error"],"errors":{"priority":"Invalid priority"}}'
    local result = test.extract_jira_error(body)
    assert.is_not_nil(result)
    assert.is_truthy(result:find("Top-level error",  1, true))
    assert.is_truthy(result:find("priority",         1, true))
  end)

  it("ignores empty string entries in errorMessages", function()
    local body = '{"errorMessages":["","Valid error",""],"errors":{}}'
    local result = test.extract_jira_error(body)
    assert.equals("Valid error", result)
  end)

end)

-- test/unit/history_spec.lua
-- Busted unit tests for lua/jira/history.lua.
-- Run with: busted test/unit/ --helper test/helper.lua

-- ── Minimal vim stub (busted runs outside Neovim) ─────────────────────────────
_G.vim = _G.vim or {}

-- Each test suite run gets its own tmp dir so history files don't bleed across.
local _tmp_base = "/tmp/test_jira_nvim_" .. os.time()

vim.fn = vim.fn or {}
vim.fn.stdpath = function(t)
  if t == "data" then return _tmp_base end
  return "/tmp"
end
vim.fn.mkdir = vim.fn.mkdir or function() end

-- Run vim.schedule callbacks synchronously so writes happen before assertions.
vim.schedule = function(f) f() end

-- Minimal JSON helpers: encode as Lua table literal, decode via loadstring.
-- This is enough for the simple arrays/tables history.lua produces.
local dkjson = require("dkjson")
vim.json = {
  encode = function(v) return dkjson.encode(v) end,
  decode = function(s) return dkjson.decode(s) end,
}

vim.log    = vim.log    or { levels = { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3 } }
vim.notify = vim.notify or function() end

-- vim.fs is used for joinpath; provide a stub so it falls back to string concat.
vim.fs = nil

-- ── Load module under test ────────────────────────────────────────────────────
-- history.lua requires jira.utils, so the package path from helper.lua must
-- already include "./lua/?.lua".  When run via busted --helper test/helper.lua
-- that is already set; guard here in case this file is loaded directly.
if not package.path:find("./lua/") then
  package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
end

local history = require("jira.history")

-- ── Helpers ───────────────────────────────────────────────────────────────────

--- Reset history module state between tests by calling setup with a fresh config.
--- history.lua stores state in module-level upvalues; calling setup() replaces
--- config but does NOT reset the in-memory lists.  We do a load_all() against a
--- temp dir that contains no files to wipe them.
local function reset_history(cfg)
  -- Point stdpath("data") at a unique directory so io.open finds nothing.
  local unique = "/tmp/test_jira_nvim_empty_" .. math.random(1e9)
  vim.fn.stdpath = function(t)
    if t == "data" then return unique end
    return "/tmp"
  end
  history.setup(cfg or {
    search_popup  = { history_size = 10 },
    history_popup = { history_size = 10 },
    filter_popup  = { history_size = 10 },
  })
  history.load_all()  -- loads from non-existent files → empties all stores
end

-- ═════════════════════════════════════════════════════════════════════════════
describe("jira.history", function()

  -- ── setup + initial state ──────────────────────────────────────────────────
  describe("setup", function()
    it("returns empty search list after setup with no files", function()
      reset_history()
      assert.same({}, history.get_search())
    end)

    it("returns empty issue list after setup with no files", function()
      reset_history()
      assert.same({}, history.get_issue())
    end)

    it("returns empty filter list after setup with no files", function()
      reset_history()
      assert.same({}, history.get_filter())
    end)

    it("accepts nil config without erroring", function()
      assert.has_no.errors(function()
        history.setup(nil)
      end)
    end)
  end)

  -- ── record_search ──────────────────────────────────────────────────────────
  describe("record_search", function()
    before_each(function()
      reset_history()
    end)

    it("ignores an empty string query", function()
      history.record_search("")
      assert.same({}, history.get_search())
    end)

    it("ignores a whitespace-only query", function()
      history.record_search("   ")
      assert.same({}, history.get_search())
    end)

    it("ignores nil query", function()
      history.record_search(nil)
      assert.same({}, history.get_search())
    end)

    it("stores a valid query", function()
      history.record_search("project = ABC")
      local h = history.get_search()
      assert.equals(1, #h)
      assert.equals("project = ABC", h[1])
    end)

    it("stores multiple distinct queries (newest last)", function()
      history.record_search("first")
      history.record_search("second")
      local h = history.get_search()
      assert.equals(2, #h)
      assert.equals("first",  h[1])
      assert.equals("second", h[2])
    end)

    it("deduplicates: re-recording moves entry to the end", function()
      history.record_search("alpha")
      history.record_search("beta")
      history.record_search("alpha")   -- duplicate → should move to end
      local h = history.get_search()
      assert.equals(2, #h)
      assert.equals("beta",  h[1])
      assert.equals("alpha", h[2])
    end)

    it("trims whitespace from query before storing", function()
      history.record_search("  jql query  ")
      local h = history.get_search()
      assert.equals("jql query", h[1])
    end)
  end)

  -- ── record_issue ───────────────────────────────────────────────────────────
  describe("record_issue", function()
    before_each(function()
      reset_history()
    end)

    it("ignores nil issue", function()
      history.record_issue(nil)
      assert.same({}, history.get_issue())
    end)

    it("ignores issue with nil key", function()
      history.record_issue({ fields = { summary = "No key" } })
      assert.same({}, history.get_issue())
    end)

    it("ignores issue with empty string key", function()
      history.record_issue({ key = "", fields = { summary = "Empty key" } })
      assert.same({}, history.get_issue())
    end)

    it("stores a valid issue with key and summary", function()
      history.record_issue({ key = "ABC-1", fields = { summary = "Bug report" } })
      local h = history.get_issue()
      assert.equals(1, #h)
      assert.equals("ABC-1",      h[1].key)
      assert.equals("Bug report", h[1].summary)
    end)

    it("stores issue with no fields (summary defaults to empty string)", function()
      history.record_issue({ key = "ABC-2" })
      local h = history.get_issue()
      assert.equals(1, #h)
      assert.equals("ABC-2", h[1].key)
      assert.equals("",      h[1].summary)
    end)

    it("deduplicates by key: re-recording same key moves it to the end", function()
      history.record_issue({ key = "ABC-1", fields = { summary = "First" } })
      history.record_issue({ key = "ABC-2", fields = { summary = "Second" } })
      history.record_issue({ key = "ABC-1", fields = { summary = "Updated" } })
      local h = history.get_issue()
      assert.equals(2, #h)
      assert.equals("ABC-2",   h[1].key)
      assert.equals("ABC-1",   h[2].key)
      assert.equals("Updated", h[2].summary)
    end)

    it("trims whitespace from summary", function()
      history.record_issue({ key = "T-1", fields = { summary = "  spaced  " } })
      local h = history.get_issue()
      assert.equals("spaced", h[1].summary)
    end)

    it("stores multiple distinct issues newest-last", function()
      history.record_issue({ key = "X-1", fields = { summary = "one" } })
      history.record_issue({ key = "X-2", fields = { summary = "two" } })
      local h = history.get_issue()
      assert.equals("X-1", h[1].key)
      assert.equals("X-2", h[2].key)
    end)
  end)

  -- ── record_filter ──────────────────────────────────────────────────────────
  describe("record_filter", function()
    before_each(function()
      reset_history()
    end)

    it("ignores nil filter", function()
      history.record_filter(nil)
      assert.same({}, history.get_filter())
    end)

    it("ignores filter with nil id", function()
      history.record_filter({ name = "No ID" })
      assert.same({}, history.get_filter())
    end)

    it("stores a valid filter", function()
      history.record_filter({ id = "123", name = "My Filter" })
      local h = history.get_filter()
      assert.equals(1, #h)
      assert.equals("123",       h[1].id)
      assert.equals("My Filter", h[1].name)
    end)

    it("coerces numeric id to string", function()
      history.record_filter({ id = 456, name = "Numeric ID" })
      local h = history.get_filter()
      assert.equals("456", h[1].id)
    end)

    it("deduplicates by id: same id moves to end with updated name", function()
      history.record_filter({ id = "1", name = "Alpha" })
      history.record_filter({ id = "2", name = "Beta" })
      history.record_filter({ id = "1", name = "Alpha updated" })
      local h = history.get_filter()
      assert.equals(2, #h)
      assert.equals("2", h[1].id)
      assert.equals("1", h[2].id)
      assert.equals("Alpha updated", h[2].name)
    end)

    it("deduplicates correctly when id was originally numeric", function()
      history.record_filter({ id = 7,   name = "First" })
      history.record_filter({ id = "7", name = "Second" })  -- same id, string form
      local h = history.get_filter()
      assert.equals(1, #h)
      assert.equals("7",      h[1].id)
      assert.equals("Second", h[1].name)
    end)

    it("trims whitespace from filter name", function()
      history.record_filter({ id = "9", name = "  padded  " })
      local h = history.get_filter()
      assert.equals("padded", h[1].name)
    end)
  end)

  -- ── trim_all ───────────────────────────────────────────────────────────────
  describe("trim_all", function()
    it("respects history_size=3 limit for searches", function()
      reset_history({
        search_popup  = { history_size = 3 },
        history_popup = { history_size = 10 },
        filter_popup  = { history_size = 10 },
      })
      for i = 1, 6 do
        history.record_search("query " .. i)
      end
      history.trim_all()
      assert.equals(3, #history.get_search())
      -- Newest entries survive (queries 4, 5, 6)
      assert.equals("query 4", history.get_search()[1])
      assert.equals("query 6", history.get_search()[3])
    end)

    it("respects history_size=3 limit for issues", function()
      reset_history({
        search_popup  = { history_size = 10 },
        history_popup = { history_size = 3 },
        filter_popup  = { history_size = 10 },
      })
      for i = 1, 5 do
        history.record_issue({ key = "I-" .. i, fields = { summary = "s" .. i } })
      end
      history.trim_all()
      assert.equals(3, #history.get_issue())
      assert.equals("I-3", history.get_issue()[1].key)
      assert.equals("I-5", history.get_issue()[3].key)
    end)

    it("respects history_size=3 limit for filters", function()
      reset_history({
        search_popup  = { history_size = 10 },
        history_popup = { history_size = 10 },
        filter_popup  = { history_size = 3 },
      })
      for i = 1, 5 do
        history.record_filter({ id = tostring(i), name = "filter " .. i })
      end
      history.trim_all()
      assert.equals(3, #history.get_filter())
      assert.equals("3", history.get_filter()[1].id)
      assert.equals("5", history.get_filter()[3].id)
    end)

    it("clears history when history_size is 0", function()
      reset_history({
        search_popup  = { history_size = 0 },
        history_popup = { history_size = 0 },
        filter_popup  = { history_size = 0 },
      })
      history.record_search("something")
      history.record_issue({ key = "A-1", fields = {} })
      history.record_filter({ id = "1", name = "f" })
      history.trim_all()
      assert.same({}, history.get_search())
      assert.same({}, history.get_issue())
      assert.same({}, history.get_filter())
    end)
  end)

  -- ── load_all ───────────────────────────────────────────────────────────────
  describe("load_all", function()
    it("does not crash when history files are missing", function()
      local unique_dir = "/tmp/test_jira_nvim_no_files_" .. math.random(1e9)
      vim.fn.stdpath = function(t)
        if t == "data" then return unique_dir end
        return "/tmp"
      end
      history.setup({
        search_popup  = { history_size = 10 },
        history_popup = { history_size = 10 },
        filter_popup  = { history_size = 10 },
      })
      assert.has_no.errors(function()
        history.load_all()
      end)
      assert.same({}, history.get_search())
      assert.same({}, history.get_issue())
      assert.same({}, history.get_filter())
    end)

    it("does not crash when stdpath returns an empty string", function()
      vim.fn.stdpath = function() return "" end
      history.setup({
        search_popup  = { history_size = 5 },
        history_popup = { history_size = 5 },
        filter_popup  = { history_size = 5 },
      })
      assert.has_no.errors(function()
        history.load_all()
      end)
    end)

    it("loads previously written search history from disk", function()
      -- Write a JSON file manually and verify load_all picks it up.
      local data_dir = "/tmp/test_jira_load_" .. math.random(1e9)
      os.execute("mkdir -p '" .. data_dir .. "/jira.nvim'")
      local path = data_dir .. "/jira.nvim/search_history.json"
      local f = io.open(path, "w")
      -- Use our encoder output style (array of quoted strings)
      f:write('["saved query 1","saved query 2"]')
      f:close()

      vim.fn.stdpath = function(t)
        if t == "data" then return data_dir end
        return "/tmp"
      end
      history.setup({
        search_popup  = { history_size = 10 },
        history_popup = { history_size = 10 },
        filter_popup  = { history_size = 10 },
      })
      history.load_all()

      local h = history.get_search()
      assert.equals(2, #h)
      assert.equals("saved query 1", h[1])
      assert.equals("saved query 2", h[2])
    end)

    it("tolerates a corrupt (non-JSON) history file without crashing", function()
      local data_dir = "/tmp/test_jira_corrupt_" .. math.random(1e9)
      os.execute("mkdir -p '" .. data_dir .. "/jira.nvim'")
      local path = data_dir .. "/jira.nvim/search_history.json"
      local f = io.open(path, "w")
      f:write("THIS IS NOT JSON }{{{")
      f:close()

      vim.fn.stdpath = function(t)
        if t == "data" then return data_dir end
        return "/tmp"
      end
      history.setup({
        search_popup  = { history_size = 10 },
        history_popup = { history_size = 10 },
        filter_popup  = { history_size = 10 },
      })
      assert.has_no.errors(function()
        history.load_all()
      end)
      assert.same({}, history.get_search())
    end)
  end)

end)

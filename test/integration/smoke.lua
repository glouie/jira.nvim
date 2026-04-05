-- test/integration/smoke.lua
-- Headless Neovim integration smoke test for jira.nvim.
-- Run with: nvim --headless -u test/minimal_init.lua -l test/integration/smoke.lua
--
-- Uses plain Lua assertions (no busted). fail() exits with code 1 so make treats it as failure.

local function pass(name)
  io.stdout:write(string.format("  PASS  %s\n", name))
  io.stdout:flush()
end

local function fail(name, reason)
  io.stderr:write(string.format("  FAIL  %s\n        %s\n", name, reason))
  io.stderr:flush()
  vim.cmd("cquit 1")
end

io.stdout:write("jira.nvim integration smoke test\n")

-- ── Test 1: setup() completes without error ───────────────────────────────────
do
  local ok, err = pcall(function()
    require("jira").setup({
      api = { base_url = "http://example.atlassian.net", email = "a@b.com", token = "tok" },
    })
  end)
  if not ok then
    fail("setup() completes without error", tostring(err))
  end
  pass("setup() completes without error")
end

-- ── Test 2: all 9 default keymaps are registered ─────────────────────────────
do
  local maps = vim.api.nvim_get_keymap("n")
  local found = {}
  for _, m in ipairs(maps) do
    if m.desc and m.desc:find("jira%.nvim") then
      found[#found + 1] = m.lhs
    end
  end
  if #found ~= 9 then
    fail(
      "9 jira.nvim keymaps registered",
      string.format("expected 9, got %d: {%s}", #found, table.concat(found, ", "))
    )
  end
  pass("9 jira.nvim keymaps registered")
end

-- ── Test 3: JIRA_EMAIL takes precedence over JIRA_API_EMAIL ──────────────────
do
  vim.env.JIRA_EMAIL     = "primary@test.com"
  vim.env.JIRA_API_EMAIL = "fallback@test.com"
  local ok, err = pcall(function()
    require("jira").setup({
      api = { base_url = "http://example.atlassian.net", token = "tok" },
    })
  end)
  if not ok then
    fail("JIRA_EMAIL env precedence (setup)", tostring(err))
  end
  local cfg = require("jira").get_config()
  if cfg.api.email ~= "primary@test.com" then
    fail(
      "JIRA_EMAIL takes precedence over JIRA_API_EMAIL",
      string.format("expected 'primary@test.com', got '%s'", tostring(cfg.api.email))
    )
  end
  pass("JIRA_EMAIL takes precedence over JIRA_API_EMAIL")
  vim.env.JIRA_EMAIL     = nil
  vim.env.JIRA_API_EMAIL = nil
end

-- ── Test 4: JIRA_API_EMAIL is used when JIRA_EMAIL is absent ─────────────────
do
  vim.env.JIRA_EMAIL     = nil
  vim.env.JIRA_API_EMAIL = "fallback@test.com"
  local ok, err = pcall(function()
    require("jira").setup({
      api = { base_url = "http://example.atlassian.net", token = "tok" },
    })
  end)
  if not ok then
    fail("JIRA_API_EMAIL fallback (setup)", tostring(err))
  end
  local cfg = require("jira").get_config()
  if cfg.api.email ~= "fallback@test.com" then
    fail(
      "JIRA_API_EMAIL used when JIRA_EMAIL absent",
      string.format("expected 'fallback@test.com', got '%s'", tostring(cfg.api.email))
    )
  end
  pass("JIRA_API_EMAIL used when JIRA_EMAIL absent")
  vim.env.JIRA_API_EMAIL = nil
end

-- ── Test 5: popup.render() does not crash ────────────────────────────────────
do
  vim.o.columns   = 200
  vim.o.lines     = 50
  vim.o.cmdheight = 1

  require("jira").setup({
    api = { base_url = "http://example.atlassian.net", email = "a@b.com", token = "tok" },
  })

  local mock_issue = {
    key     = "TEST-1",
    summary = "Mock issue summary",
    fields  = {
      summary     = "Mock issue summary",
      status      = { name = "In Progress", statusCategory = { colorName = "yellow" } },
      priority    = { name = "Medium" },
      assignee    = { displayName = "Test User" },
      reporter    = { displayName = "Reporter" },
      created     = "2024-01-01T00:00:00.000+0000",
      updated     = "2024-01-02T00:00:00.000+0000",
      due         = nil,
      description = nil,
      comment     = { comments = {} },
      changelog   = { histories = {} },
      labels      = {},
      fixVersions = {},
      versions    = {},
    },
  }

  local popup  = require("jira.popup")
  local config = require("jira").get_config()

  local ok, err = pcall(popup.render, mock_issue, config, {})
  if not ok then
    fail("popup.render() does not crash", tostring(err))
  end
  pass("popup.render() does not crash")
  pcall(popup.close_all)
end

-- ── Done ──────────────────────────────────────────────────────────────────────
io.stdout:write("\nAll integration tests passed.\n")
vim.cmd("quit")

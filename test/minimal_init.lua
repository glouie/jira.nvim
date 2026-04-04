-- test/minimal_init.lua
-- Minimal Neovim init for running busted tests inside a headless Neovim session:
--   nvim --headless -u test/minimal_init.lua

-- Add the plugin root to runtimepath so require("jira.*") works.
vim.opt.rtp:prepend(".")

-- Ensure package.path includes the lua source tree, the same way helper.lua does
-- for the pure-busted (no Neovim) runner.
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Minimal vim stubs that may be needed when the real Neovim globals are absent
-- (e.g. running tests via `nvim --headless` with a stripped environment).
vim.NIL = vim.NIL or {}

vim.json = vim.json or {
  decode = function(s)
    -- Neovim always provides vim.json; this branch is a safety net.
    return load("return " .. s:gsub("null", "nil"))()
  end,
  encode = function(v)
    return tostring(v)
  end,
}

vim.log = vim.log or { levels = { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3 } }

vim.notify = vim.notify or function() end
vim.schedule = vim.schedule or function(f) f() end
vim.cmd = vim.cmd or function() end
vim.pesc = vim.pesc or function(s) return s:gsub("(%W)", "%%%1") end

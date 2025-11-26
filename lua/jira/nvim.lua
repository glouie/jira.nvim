---Entry point that exposes jira.nvim when required from Neovim runtimes.
-- Loads the main module so `require("jira.nvim")` returns the plugin table.

local jira = require("jira")

return jira

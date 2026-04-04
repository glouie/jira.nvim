---Compatibility shim: makes `require("jira.nvim")` an alias for `require("jira")`.
-- Some plugin managers (e.g. older packer configs) call require("jira.nvim") by
-- convention based on the repository name. This file exists solely to support that
-- pattern without duplicating any logic.

return require("jira")

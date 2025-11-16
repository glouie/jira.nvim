if exists("g:loaded_jira_nvim")
  finish
endif
let g:loaded_jira_nvim = 1

lua << JIRANVIM
local ok, jira = pcall(require, "jira")
if not ok then
  return
end
local setup = jira and jira.setup
if type(setup) == "function" then
  setup()
end
JIRANVIM

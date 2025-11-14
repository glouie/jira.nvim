if vim.g.loaded_jira_nvim then
  return
end
vim.g.loaded_jira_nvim = true

local ok, jira = pcall(require, "jira")
if not ok then
  return
end

jira.setup()

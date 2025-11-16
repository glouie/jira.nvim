if vim.g.jira_nvim_local_loaded then
  return
end
vim.g.jira_nvim_local_loaded = true

local source = debug.getinfo(1, "S").source
if not source or source == "" or source:sub(1, 1) ~= "@" then
  return
end

local root = vim.fn.fnamemodify(source:sub(2), ":p:h")
if root == "" then
  return
end

local function ensure_rtp(path)
  local rtp = vim.opt.runtimepath:get()
  for _, entry in ipairs(rtp) do
    if vim.fn.fnamemodify(entry, ":p") == vim.fn.fnamemodify(path, ":p") then
      return false
    end
  end
  vim.opt.runtimepath:append(path)
  return true
end

local function load_plugin()
  if vim.g.loaded_jira_nvim then
    return
  end
  local ok, err = pcall(vim.cmd, "runtime plugin/jira.lua")
  if not ok then
    vim.notify(
      string.format("jira.nvim: failed to source plugin entry (%s)", err),
      vim.log.levels.ERROR
    )
  end
end

if ensure_rtp(root) or not vim.g.loaded_jira_nvim then
  load_plugin()
end

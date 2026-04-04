---Health check module for jira.nvim.
-- Run with :checkhealth jira

local M = {}

local function check_neovim_version()
  local health = vim.health or require("health")
  -- vim.system was added in Neovim 0.10
  if vim.fn.has("nvim-0.10") == 1 then
    health.ok("Neovim >= 0.10 (vim.system available)")
  elseif vim.fn.has("nvim-0.8") == 1 then
    health.warn("Neovim 0.8–0.9: vim.fn.jobstart fallback will be used (upgrade to 0.10+ recommended)")
  else
    health.error("Neovim < 0.8 is not supported")
  end
end

local function check_curl()
  local health = vim.health or require("health")
  local curl = vim.fn.exepath("curl")
  if curl and curl ~= "" then
    local result = vim.fn.system({ "curl", "--version" })
    local version = result:match("curl%s+([%d%.]+)")
    if version then
      health.ok(string.format("curl found: %s (%s)", curl, version))
    else
      health.ok(string.format("curl found: %s", curl))
    end
  else
    health.error("curl not found in PATH — jira.nvim requires curl to make API requests")
  end
end

local function check_credentials()
  local health = vim.health or require("health")
  local ok, jira = pcall(require, "jira")
  if not ok then
    health.warn("jira.nvim not yet loaded — call require('jira').setup() first for full credential check")
    -- Fall back to env var check
    local base_url = vim.env.JIRA_BASE_URL or ""
    local email = vim.env.JIRA_API_EMAIL or ""
    local token = vim.env.JIRA_API_TOKEN or vim.env.JIRA_API_KEY or ""
    if base_url ~= "" then
      health.ok(string.format("JIRA_BASE_URL set: %s", base_url))
    else
      health.warn("JIRA_BASE_URL not set — set via config.api.base_url or $JIRA_BASE_URL")
    end
    if email ~= "" then
      health.ok("JIRA_API_EMAIL set")
    else
      health.warn("JIRA_API_EMAIL not set — set via config.api.email or $JIRA_API_EMAIL")
    end
    if token ~= "" then
      health.ok("API token set (JIRA_API_TOKEN or JIRA_API_KEY)")
    else
      health.warn("API token not set — set via config.api.token, $JIRA_API_TOKEN, or $JIRA_API_KEY")
    end
    return
  end

  local cfg = jira.get_config and jira.get_config()
  if not cfg then
    health.warn("Could not read config — has setup() been called?")
    return
  end

  local base_url = (cfg.api and cfg.api.base_url) or ""
  if base_url ~= "" then
    if base_url:match("^https://") then
      health.ok(string.format("base_url: %s", base_url))
    elseif base_url:match("^http://") then
      health.warn(string.format("base_url uses http:// — credentials will be sent in plaintext: %s", base_url))
    else
      health.error(string.format("base_url does not start with https:// or http://: %s", base_url))
    end
  else
    health.error("base_url is not configured — set config.api.base_url or $JIRA_BASE_URL")
  end

  local email = (cfg.api and cfg.api.email) or ""
  if email ~= "" then
    health.ok("API email is set")
  else
    health.error("API email is not configured — set config.api.email or $JIRA_API_EMAIL")
  end

  local token = (cfg.api and cfg.api.token) or ""
  if token ~= "" then
    health.ok("API token is set")
  else
    health.error("API token is not configured — set config.api.token, $JIRA_API_TOKEN, or $JIRA_API_KEY")
  end
end

local function check_optional_deps()
  local health = vim.health or require("health")
  -- lualine (optional, for statusline integration)
  local has_lualine = pcall(require, "lualine")
  if has_lualine then
    health.ok("lualine found (statusline integration available)")
  else
    health.info("lualine not found — statusline will use vim.o.statusline or echo mode")
  end
end

function M.check()
  local health = vim.health or require("health")
  health.start("jira.nvim")
  check_neovim_version()
  check_curl()
  check_credentials()
  check_optional_deps()
end

return M

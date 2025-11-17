# Installing jira.nvim

This guide shows how to install jira.nvim with [`lazy.nvim`](https://github.com/folke/lazy.nvim) and configure it end-to-end.

## Prerequisites

- Neovim 0.9+ with `curl` available in your `$PATH`
- A Jira Cloud API token and credentials exported as environment variables:
  - `JIRA_BASE_URL` (e.g. `https://your-domain.atlassian.net`)
  - `JIRA_API_EMAIL`
  - `JIRA_API_TOKEN` (or `JIRA_API_KEY`)

## Install with lazy.nvim

Add this spec to your lazy.nvim setup:

```lua
{
  "glouie/jira.nvim",
  version = false, -- or pin to a tag/commit
  opts = {
    -- See the full reference in examples/full-config.lua
  },
}
```

Then run `:Lazy sync` and restart Neovim.

## Configure

If you want to customize keymaps, popup sizing, or API credentials, copy `examples/full-config.lua` into your config and tweak the values, then require it from your Neovim `init.lua` or a plugin file.

## Verify

1) Open a buffer containing Jira issue keys (e.g. `ABC-123`).
2) Press `<leader>ji` to open the popup.  
3) Use `<leader>ja` to see issues assigned to you, or `<leader>js` to run a JQL search.

If you see credential or network errors, double-check the environment variables and your VPN connection.

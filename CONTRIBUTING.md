# Contributing to jira.nvim

Thanks for taking the time to improve jira.nvim! This document outlines how to spin up a local dev session, run the plugin without installing it globally, and the guidelines we follow for patches.

## Quickstart (ad-hoc loading)

You can work entirely inside the repo without dropping it into your Neovim config. From the repository root:

```bash
nvim README.md
```

If you keep [`:set exrc`](https://neovim.io/doc/user/options.html#'exrc') enabled, the repository-local `.nvim.lua` file automatically adds the repo to `runtimepath` and sources `plugin/jira.lua` as soon as Neovim starts inside this directory, so the default keymaps and highlights are available immediately.

If you prefer not to trust local configs, extend the runtime path and load the plugin manually:

```vim
:set rtp+=/Users/glouie/Library/Mobile\ Documents/com~apple~CloudDocs/learning/nvim/jira.nvim
:runtime plugin/jira.lua
```

The first command temporarily adds the repo to `runtimepath`, and the second runs the plugin entry point so `require("jira").setup()` executes. Repeat these two commands any time you start Neovim without the local config. After loading you can hover over issue keys (e.g. `SPL-12345`) and trigger the configured keymap to test changes immediately.

## Environment variables

jira.nvim expects Atlassian Cloud credentials from your shell environment:

- `JIRA_BASE_URL` (e.g. `https://your-domain.atlassian.net`)
- `JIRA_API_EMAIL`
- `JIRA_API_TOKEN` (or `JIRA_API_KEY`)

Export them before starting Neovim so the plugin can authenticate when fetching issues.

## Coding standards

- Keep the codebase ASCII-only unless a file already uses other characters.
- Prefer pure Lua and built-in Neovim APIs; avoid adding dependencies unless essential.
- Document complex logic with concise comments (no noise comments).
- Match the existing formatting (two spaces indentation, `snake_case`, etc.).

## Testing changes

1. Start Neovim from the repo to keep paths short: `nvim lua/jira/init.lua`.
2. Add the repo to `runtimepath` and run `:runtime plugin/jira.lua` as shown above.
3. Open or create a scratch buffer and type sample issue keys (`ABC-123`).
4. Move the cursor onto a key and trigger the configured mapping (default `<leader>ji`).
5. Verify highlights, popup layout, and browser shortcuts.

## Submitting patches

1. Fork the repository (or create a feature branch locally).
2. Keep commits focused; include tests or sample buffers when relevant.
3. Update `README.md` or inline docs if behaviour changes.
4. Open a pull request describing the motivation, implementation details, and manual test steps.

Happy hacking!

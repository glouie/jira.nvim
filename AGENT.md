# AGENT.md — Working on `jira.nvim`

This file is the canonical “how to work in this repo” guide for humans and coding agents.

## Scope / Goal
`jira.nvim` is a Neovim plugin for browsing Jira issues (Atlassian Cloud) from inside Neovim.

Primary goals:
- fast, stable UX (popups, hover summaries, JQL search)
- safe credential handling (never commit tokens; avoid logging secrets)
- predictable keymaps + configuration

## Non-goals
- Jira Server/Data Center support unless explicitly added
- background push notifications (Jira is polled)

## Repo map (where things live)
- `lua/jira/init.lua` — user-facing setup + default config
- `lua/jira/api.lua` — Jira HTTP calls, paging, parsing, caching/backoff
- `lua/jira/popup.lua` — floating UI (issue view + tables)
- `lua/jira/jql_prompt.lua` — JQL prompt UI + history
- `lua/jira/utils.lua` — helpers/validation
- `examples/` — example configs
- `tests/` — tests/fixtures

## Run / Test / Dev loop
1) Install deps (Neovim + your plugin manager).
2) Set env vars (preferred):
   - `JIRA_BASE_URL` (e.g. `https://your-domain.atlassian.net`)
   - `JIRA_API_EMAIL`
   - `JIRA_API_TOKEN` (or `JIRA_API_KEY`)
3) Repro steps should include:
   - minimal `require("jira").setup({...})`
   - expected vs actual behavior
   - log snippet if relevant

If tests exist, run them before/after changes:
- Check `tests/` for the intended runner and keep tests passing.

## Safety rules (important)
- **Never** print or persist `JIRA_API_TOKEN` / `JIRA_API_KEY`.
- Don’t commit `.env` files or local secrets.
- When adding logging:
  - redact auth headers
  - prefer opt-in via `debug = true`

## UX rules
- Keymaps must be overridable and documented.
- Don’t change defaults without updating `README.md` (and `INSTALL.md` if setup changes).
- Keep UI responsive: avoid blocking calls on cursor move; debounce hover fetches.

## API rules
- Jira Cloud is rate-limited; implement:
  - pagination
  - backoff/retry (bounded)
  - caching where safe
- Treat missing fields/permissions gracefully.

## Documentation hygiene
When you add/modify behavior, update the relevant docs:
- setup/auth changes → `INSTALL.md` + `README.md`
- keymap changes → `README.md`
- portable UI/UX design changes → `docs/tui/TUI_SPEC.md` (entrypoint: `docs/UI.md`)
- Jira.nvim surface behavior changes → `docs/ui-impl/jira/JIRA_SURFACE_MAP.md`
- internal architecture changes → consider adding `docs/ARCHITECTURE.md` (future)

## PR checklist
- [ ] No secrets in code, logs, docs, or tests
- [ ] Existing behavior preserved (unless documented)
- [ ] Docs updated for user-visible changes
- [ ] Tests updated/added when practical

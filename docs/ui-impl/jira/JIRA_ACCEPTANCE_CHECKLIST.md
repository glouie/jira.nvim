# Jira.nvim UI Acceptance Checklist

This checklist validates Jira.nvim behavior against `docs/tui` and `docs/ui-impl/NEOVIM_LUA_PROFILE.md`.

Use this checklist for manual regression checks after UI behavior changes.

- [ ] Issue keys are highlighted/underlined in a buffer containing `ABC-123`.
- [ ] Hover summary shows `<KEY>: <summary>` without noticeable lag.
- [ ] Issue details popup opens from issue key under cursor.
- [ ] In issue details popup, `Tab` cycles panes and `q`/`Esc` closes.
- [ ] In issue details popup, `o` opens issue URL in browser.
- [ ] In issue details popup, `Enter` on a URL opens that URL.
- [ ] Buffer issue picker opens selected issue via `Enter`.
- [ ] Assigned list opens selected issue via `Enter`.
- [ ] Created list opens selected issue via `Enter`.
- [ ] Recently viewed list opens selected issue via `Enter`.
- [ ] JQL search prompt supports history and completion navigation.
- [ ] JQL search results show total + visible range and page correctly.
- [ ] Filter search accepts numeric filter id and returns results.
- [ ] Filter search result preview updates when selection changes.
- [ ] Invalid filter id shows inline error and keeps prompt open.
- [ ] Saved filters list sorts favorites before non-favorites.
- [ ] Viewed issue history persists and respects configured `history_size`.
- [ ] Filter history persists and respects configured `history_size`.
- [ ] Missing API config errors mention relevant config/env variables.
- [ ] No secrets/tokens are displayed in UI output or logs.

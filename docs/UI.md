# UI / UX Specification

This file is the entrypoint for all UI documentation.

## Layered Canonical Structure

1. Portable design system:
   - `docs/tui/TUI_SPEC.md`
   - `docs/tui/UI_ELEMENTS.md`
   - `docs/tui/GLOSSARY.md`
   - `docs/tui/PAGE_*.md`
2. Neovim implementation profile:
   - `docs/ui-impl/NEOVIM_LUA_PROFILE.md`
3. Plugin-specific surface maps:
   - `docs/ui-impl/<plugin>/...`

## Current Plugin Mapping

- Jira.nvim surface map: `docs/ui-impl/jira/JIRA_SURFACE_MAP.md`
- Jira.nvim UI checklist: `docs/ui-impl/jira/JIRA_ACCEPTANCE_CHECKLIST.md`

## How to Reuse for Another Plugin

- Reuse `docs/tui/*` unchanged.
- Reuse `docs/ui-impl/NEOVIM_LUA_PROFILE.md` for renderer behavior.
- Create `docs/ui-impl/<new-plugin>/SURFACE_MAP.md` from `docs/ui-impl/SURFACE_MAP_TEMPLATE.md`.
- Add `<new-plugin>/ACCEPTANCE_CHECKLIST.md` for regression checks.

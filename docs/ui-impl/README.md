# UI Implementation Layer

This folder translates the generic TUI design system (`docs/tui`) into concrete runtime implementations.

## Layering Model

1. `docs/tui` (portable design contracts)
2. `docs/ui-impl/NEOVIM_LUA_PROFILE.md` (runtime renderer profile)
3. `docs/ui-impl/<plugin>/...` (plugin-specific surface map and acceptance checks)

## Goal

Allow different plugins and backend stacks (Lua-only, Rust-backed, etc.) to ship the same UI behavior and look by sharing a common design layer.

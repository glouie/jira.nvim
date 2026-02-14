# Neovim Lua UI Implementation Profile

This profile maps the portable TUI spec (`docs/tui`) to Neovim UI primitives.
Use it for any Neovim plugin that should match the same UI behavior, regardless of backend language.

## Purpose

- Keep visual/interaction parity across plugins.
- Define implementation constraints for Neovim floating UI.
- Separate renderer concerns from business logic/backends.

## Runtime Primitives

| TUI concept | Neovim primitive |
|---|---|
| page/surface | scratch buffer + window (normal or floating) |
| region/pane | separate window or logical section in one buffer |
| overlay/modal | centered floating window with focused keymap scope |
| list/table selection | cursor row + extmark highlight |
| status bar | last line region in buffer or statusline integration |
| loading/empty/error | dedicated render state templates |

## Rendering Contracts

- Use deterministic render order: header, body panes, footer.
- Re-render should preserve selection/focus when possible.
- Resize handling should recalculate window geometry without state loss.
- Every render state must have text fallback (not highlight-only).

## Parity Locks (for \"look exactly the same\")

To keep a second plugin visually identical to the reference UI, lock these defaults unless explicitly versioned:

- border style: `rounded`
- spacing unit: `1` cell
- density: `compact`
- truncation: end-ellipsis
- list selection marker style and highlight group naming
- footer key-hint ordering

## Input and Focus Contracts

- Use buffer-local mappings for surface-specific keys.
- Keep global keys consistent with `docs/tui/TUI_SPEC.md`.
- `Tab` and `Shift+Tab` should rotate focus targets deterministically.
- Close keys (`q`, `Esc`) must always exit current overlay/surface cleanly.

## Suggested View Model Boundary

Use a runtime-agnostic view model between backend and UI renderer.

### Backend responsibilities

- fetch/transform domain data
- return state enum + normalized fields
- provide stable item IDs and action payloads

### Renderer responsibilities

- layout, alignment, truncation, highlighting
- cursor/focus behavior
- keymap binding and action dispatch

## Rust Backend Compatibility Notes

For a Rust-backed plugin that should match this UI:

- keep Neovim renderer contracts in Lua (or compatible host layer)
- expose backend data via RPC/job/channel using stable view-model schema
- do not let backend dictate presentation layout tokens
- preserve state/action naming from `docs/tui/TUI_SPEC.md`

## Surface Definition Pattern

For each plugin surface, define:

- surface ID
- mapped archetype (`PAGE_LIST.md`, `PAGE_DETAIL.md`, etc.)
- key contract deltas (if any)
- state transitions
- persistence paths (if any)

Use `docs/ui-impl/SURFACE_MAP_TEMPLATE.md`.

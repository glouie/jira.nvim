# TUI Specification Standard

This folder defines a portable, implementation-agnostic design system for terminal UIs.
It should be reusable across plugins, languages, and backends.

## Scope

This layer defines:

- page structure and layout contracts
- shared UI element behavior
- state naming and interaction rules
- terminology for consistent specs/reviews

This layer does not define:

- plugin-specific keymaps
- Neovim/Lua implementation details
- backend/runtime architecture (Lua, Rust, etc.)

## Canonical Usage Rules

- Keep `docs/tui` free of product/domain-specific behavior.
- Put runtime implementation details in `docs/ui-impl`.
- Put plugin-specific surface maps in `docs/ui-impl/<plugin>/`.
- Keep one source of truth per concern; avoid duplicated behavior text.

## Document Map

- `TUI_SPEC.md`: global design rules and naming standards
- `UI_ELEMENTS.md`: catalog of UI display elements and behavior contracts
- `GLOSSARY.md`: shared terminology
- `PAGE_TEMPLATE.md`: template for creating a new page spec
- `ELEMENT_TEMPLATE.md`: template for adding a UI element spec
- `PAGE_HOME.md`
- `PAGE_LIST.md`
- `PAGE_DETAIL.md`
- `PAGE_CREATE.md`
- `PAGE_EDIT.md`
- `PAGE_SEARCH.md`
- `PAGE_FILTERS.md`
- `PAGE_NOTIFICATIONS.md`
- `PAGE_ACTIVITY.md`
- `PAGE_SETTINGS.md`
- `PAGE_HELP.md`
- `PAGE_COMMAND_PALETTE.md`

## Authoring Workflow

1. Choose the closest page archetype.
2. Copy `PAGE_TEMPLATE.md` for a new page type.
3. Reuse terms from `GLOSSARY.md` and names from this file.
4. Add component behavior in `UI_ELEMENTS.md` only when needed.
5. Add implementation constraints under `docs/ui-impl`.
6. Add product/plugin behavior under `docs/ui-impl/<plugin>/`.

## Required Section Order (for every page spec)

1. `ID`
2. `Purpose`
3. `User jobs`
4. `Layout regions`
5. `Components`
6. `States`
7. `Keyboard model`
8. `Validation + errors`
9. `System feedback`
10. `Accessibility`
11. `Telemetry (optional)`
12. `Open questions`

## Shared Naming Contracts

### State names

Use only these names unless there is a hard exception:

- `idle`
- `loading`
- `ready`
- `empty`
- `error`
- `submitting`
- `success`
- `disabled`

### Action names

- `primary_action`
- `secondary_action`
- `destructive_action`
- `cancel_action`

### Region names

- `header`
- `left_pane`
- `main_pane`
- `right_pane`
- `footer`
- `overlay`

## Global UX Principles

- Fast by default.
- Keyboard-first interaction.
- Predictable focus and navigation.
- Graceful degradation on missing data.
- Explicit recovery for errors.

## Global Shell Layout

```txt
+--------------------------------------------------------------------------------+
| Header: app/context | global hint (/ search, ? help, Ctrl+p commands)         |
+---------------------------------------+----------------------------------------+
| Left Pane (optional nav/filters)      | Main Pane (page content viewport)      |
| - sections                            | - list/table/form/detail               |
| - saved views                         | - tabs/subpanes                        |
+---------------------------------------+----------------------------------------+
| Footer: mode | key hints | async status | error summary                        |
+--------------------------------------------------------------------------------+
| Overlay layer: command palette, modal, confirm dialogs                         |
+--------------------------------------------------------------------------------+
```

## Layout Invariants

- Popup width and height should be proportion-based (`0..1`) unless fixed.
- Surfaces should fit viewport and handle resize cleanly.
- Multi-pane views keep independent pane scroll positions.
- Focus changes do not reset pane scroll.

## Global Keyboard Contract

- Global: `?` help, `Ctrl+p` command palette, `q` quit/back
- Movement: `j/k` next/prev, `h/l` left/right where applicable
- Focus: `Tab` and `Shift+Tab` cycle regions
- Action: `Enter` activate, `Space` toggle/select
- Search: `/` focus search, `n/N` next/prev match
- Editing: `Ctrl+s` save/submit, `Esc` cancel/close
- Navigation: `gg` top, `G` bottom, `[` previous page, `]` next page
- Paging: `Ctrl+f` and `Ctrl+b` where paging exists
- Recovery: `r` retry/reload

## Visual Language Contract

- `spacing_unit`: 1 terminal cell
- `density`: `compact` default
- `alignment`: labels left; tabular values aligned by column
- `truncation`: end-ellipsis for overflow; full value on focus/preview
- `emphasis`: one primary emphasis target per region
- `contrast`: state must use text/symbol cues, not color alone

## Portability Contract

To reproduce the same UI in another plugin/runtime:

- keep page structure and state names unchanged
- keep component semantics unchanged
- keep keyboard contract unchanged (unless platform conflict)
- implement renderer adapters without changing conceptual behavior

Use `docs/ui-impl` for runtime-specific mapping (Neovim/Lua, Rust host integration, etc.).

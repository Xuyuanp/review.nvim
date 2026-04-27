# AGENTS.md

This file provides guidance to AI Coding Agent when working with code in this repository.

## What this plugin does

`review.nvim` is a Neovim plugin for ephemeral code review annotations, designed for `nvim -R` sessions. Annotations live in memory only and are exported to markdown (either on-demand via `require('review').export()` / `preview()`, or automatically to `config.output` on `VimLeavePre`). There is no persistence between sessions by design.

The user-facing entry point is the `:Review [path]` command (see `plugin/review.lua`), which calls `setup({ output = path, keymaps = true })`.

## Commands

```bash
make test                                         # run all tests via mini.test headless
make test-file FILE=tests/test_review_state.lua   # run a single test file
make lint                                         # luacheck on lua/ and tests/
make format                                       # stylua write
make format-check                                 # stylua --check
make clean                                        # remove .tests/ (mini.nvim clone)
```

The first test run clones `mini.nvim` into `.tests/mini.nvim` (see `tests/minimal_init.lua`). Tests use `mini.test`; assertions are `MiniTest.expect.equality` / `MiniTest.expect.error`. The test runner is invoked via `nvim --headless --noplugin -u tests/minimal_init.lua -c 'lua MiniTest.run()'`.

Override the Neovim binary with `NVIM=/path/to/nvim make test`.

## Architecture

The plugin is split into a pure data layer, a side-effect layer, and a thin orchestration layer. Respect this separation when making changes — the state module must stay decoupled from Neovim UI so it can be unit-tested headlessly.

- **`lua/review/state.lua`** — Pure data store (`review.State` class). Owns all annotations (`line` / `range` / `file` / `overall`), assigns IDs, and enforces invariants (see below). Emits `add` / `update` / `delete` events via an injected `on_change` callback — it does NOT touch buffers, extmarks, or any `vim.api.*`. Tests instantiate `State.new()` directly.
- **`lua/review/ui.lua`** — All buffer/extmark side effects. `ui.make_on_change(config)` returns the `on_change` callback that `state` invokes; this is where extmarks, signs, and virt_lines are created/updated/removed. Also hosts `open_float` (annotation editor) and `open_preview`. Uses a single namespace `review`; extmark IDs are derived from annotation IDs as `ann.id * 100 (+ offset)` so multiple extmarks per annotation can be addressed deterministically.
- **`lua/review/export.lua`** — Pure markdown generator. Consumes `State:all()` output; groups by file in first-seen order, sorts line/range within a file by `lnum`, emits overall section first. No side effects.
- **`lua/review/picker.lua`** — `vim.ui.select` wrapper.
- **`lua/review/init.lua`** — Orchestration. Wires `State` to `ui.make_on_change(config)`, defines `annotate()` / `next()` / `prev()` / `pick()` / `export()` / `preview()` / `reset()`, registers keymaps (when `config.keymaps = true`), and attaches the `VimLeavePre` autocmd that writes `config.output`.
- **`plugin/review.lua`** — Defines `:Review [path]`.

Data flow: user action → `init.lua` (collects buffer/line context, opens float) → on float close, calls `state:add/update/delete` → state fires `on_change` → `ui.lua` mutates extmarks. Export is a separate read path: `state:all()` → `export.generate()` → markdown string → either returned, shown in a preview float, or written to disk on exit.

## Invariants enforced by `state.lua`

When adding features, preserve these — they are tested and relied on by callers:

- At most one `overall` annotation.
- At most one `file` annotation per file path.
- `range` annotations cap at 10 lines and must not overlap another range in the same buffer.
- `line` annotations cannot be created inside an existing range in the same buffer.
- `State:all()` is sorted by `created_at`; `State:by_buffer()` is sorted by `lnum` and excludes `file` / `overall` scopes (so `next()` / `prev()` skip them).

`init.lua` performs an additional pre-validation for range creation (overlap / contained line annotations) before opening the float, so users aren't prompted to type text only to have it rejected. If you change range rules, update both places.

## Style and lint

- `stylua`: 4-space indent, 150-col width, single quotes preferred, no collapsed simple statements (see `.stylua.toml`).
- `luacheck`: `lua51+nvim`, with `vim` and `MiniTest` as read-only globals; max-line-length (631) is ignored. Unused args prefixed with `_` are ignored.
- All annotations, comments, and LuaCATS `---@` types are in English; the codebase uses LuaCATS extensively — keep type annotations on new public functions and data shapes.
- Every function `opts` parameter must have its own named `---@class` (or `---@alias`) type — never inline a table shape in `---@param opts { ... }`. Follow the `review.Config` / `review.StateOpts` / `review.OpenFloatOpts` convention. Applies to all table-shaped parameters; `opts` is just the most common offender.

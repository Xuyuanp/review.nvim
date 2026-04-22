# review.nvim

Ephemeral code review annotations for Neovim. Designed for read-only review
sessions (`nvim -R`).

Leave notes at four granularities -- line, range, file, and overall -- then
export them as structured markdown when you're done.

## Quick Start

```lua
require('review').setup({
    output = 'review.md',
    keymaps = true,
})
```

## Configuration

```lua
---@class review.Config
---@field output? string           -- file path to write on exit (nil = no auto-export)
---@field sign_text? string        -- sign for annotated lines (default: "󰅺")
---@field sign_range_start? string -- range start sign (default: "╭")
---@field sign_range_mid? string   -- range intermediate sign (default: "│")
---@field float_width? integer     -- floating window width (default: 60)
---@field float_height? integer    -- floating window height (default: 10)
---@field keymaps? boolean         -- enable review keymaps (default: false)
```

## Keymaps

Enabled when `keymaps = true`. These shadow core keys (`a`, `o`, `A`, etc.),
intended for `nvim -R` sessions only. Press `H` to show this table in-editor.

| Key  | Mode   | Action                    |
| ---- | ------ | ------------------------- |
| `a`  | normal | Annotate line             |
| `a`  | visual | Annotate range            |
| `A`  | normal | Annotate file             |
| `o`  | normal | Annotate overall          |
| `P`  | normal | Preview annotations       |
| `X`  | normal | Discard all annotations   |
| `]]` | normal | Next annotation           |
| `[[` | normal | Previous annotation       |
| `gp` | normal | Pick annotation           |
| `H`  | normal | Show keymaps help         |

## API

```lua
local review = require('review')

review.setup(opts?)   -- configure and register keymaps/autocmds
review.annotate(scope?) -- create/edit/delete annotation (adapts to context)
review.next()         -- jump to next annotation
review.prev()         -- jump to previous annotation
review.pick()         -- list annotations via vim.ui.select
review.export()       -- return markdown string
review.preview()      -- show export in a floating window
review.reset()        -- discard all annotations
review.help()         -- show keymaps help
```

## Testing

Tests use [mini.test](https://github.com/echasnovski/mini.test).

```bash
make test                                        # all tests
make test-file FILE=tests/test_review_state.lua  # single file
```

## License

[MIT](LICENSE)

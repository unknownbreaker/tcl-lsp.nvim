# tcl-lsp

A focused Language Server for **TCL** and **RVT** (Apache Rivet templates), for
Neovim and Vim. The server is a self-contained Go binary; Neovim and Vim clients
drive the same binary.

Scope is deliberately tight — **go-to-definition** and **find-references**, done
well (scope-correct, cross-file, `.rvt`-aware) — rather than a broad, shallow
feature set.

## Features

| LSP feature                | Status |
| -------------------------- | :----: |
| Go to definition           |   ✅   |
| Find references            |   ✅   |
| Hover                      |   ❌   |
| Completion                 |   ❌   |
| Signature help             |   ❌   |
| Rename                     |   ❌   |
| Formatting                 |   ❌   |
| Diagnostics                |   ❌   |
| Code actions               |   ❌   |
| Document / workspace symbols |  ❌   |
| Inlay hints / semantic tokens |  ❌  |

`❌` items are out of scope by design (see [Why a v2 reset](#why-a-v2-reset)).

**What the two supported features actually do:**

- ✅ **Cross-file** resolution, including `.rvt` ⇄ `.tcl`.
- ✅ **Reaching-definitions** — a `$x` jumps to the assignment(s) that actually
  reach it (through loops, conditionals, `break`/`continue`/`return`), not just
  the first binding.
- ✅ **Scope-correct** — namespaces, `namespace path`/`import`,
  `global`/`upvar`/`variable` link origin-chasing, and arrays.

## Requirements

- **Neovim ≥ 0.11** (uses the native `vim.lsp.config`/`vim.lsp.enable`), **or**
  classic **Vim** with [vim-lsp] or [coc.nvim] — see [`editors/README.md`](editors/README.md).
- **`go` + `make`** to build the bundled server. It builds automatically on first
  use and rebuilds when its sources change; no manual step, no binary to install.

[vim-lsp]: https://github.com/prabirshrestha/vim-lsp
[coc.nvim]: https://github.com/neoclide/coc.nvim

## Installation (Neovim)

The plugin loads on `tcl`/`rvt` filetypes, builds the bundled Go server via the
manager's build hook, and calls `require("tcl-lsp").setup(opts)`.

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "unknownbreaker/tcl-lsp",
  ft = { "tcl", "rvt" },
  build = "make -C server build",
  init = function()
    -- map .rvt before any file opens, so the `ft` trigger can fire
    vim.filetype.add({ extension = { tcl = "tcl", rvt = "rvt" } })
  end,
  opts = {}, -- calls require("tcl-lsp").setup({})
}
```

A fully-commented spec (including a dev/local-clone variant) lives at
[`editors/nvim/tcl-lsp.lua`](editors/nvim/tcl-lsp.lua).

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use({
  "unknownbreaker/tcl-lsp",
  run = "make -C server build",
  config = function()
    require("tcl-lsp").setup({})
  end,
})
```

### [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'unknownbreaker/tcl-lsp', { 'do': 'make -C server build' }
```

Then, after `plug#end()`:

```lua
require("tcl-lsp").setup({})
```

> `.rvt` filetype detection ships in `ftdetect/rvt.vim`, so packer/vim-plug pick
> it up automatically. With lazy.nvim's filetype lazy-loading, the `init` hook
> above sets it before load.

### Configuration

`setup()` takes an optional table; defaults shown:

```lua
require("tcl-lsp").setup({
  filetypes    = { "tcl", "rvt" },        -- buffers the server attaches to
  root_markers = { ".git", "pkgIndex.tcl" }, -- project root (order = priority; .git first)
  cmd          = nil,                     -- override the server binary; nil = bundled
  auto_build   = true,                    -- build the bundled server when missing/stale
})
```

## Installation (Vim)

Vim has no built-in LSP client; use **vim-lsp** or **coc.nvim**. Full recipes
(including the `.git`-first root config) are in
[`editors/README.md`](editors/README.md).

## Usage

Open a `.tcl` or `.rvt` file and use your LSP keymaps:

```lua
vim.keymap.set("n", "gd", vim.lsp.buf.definition)
vim.keymap.set("n", "grr", vim.lsp.buf.references)
```

(LazyVim already binds `gd` and `grr`.) In Vim: `:LspDefinition` / `:LspReferences`.

## Why a v2 reset

v1 (313 commits) tried to do too much and accumulated performance regressions that
were impossible to untangle. v2 inverts the approach: understand TCL's tricky
scope rules first, write them down, then build the minimum that works — which is
why heavier analysis (e.g. the reaching-definitions dataflow) runs only when
needed and stays off the goto-def hot path. Research lives in `research/`, designs
and plans in `docs/`. Deferred work (e.g. Itcl/TclOO `$obj method` type-tracking)
is tracked in [`docs/BACKLOG.md`](docs/BACKLOG.md).

## Recovering the old prototype

The full v1 history is preserved on the `v1` branch (its tip) and at the
`archive-v1` tag (an earlier checkpoint).

```bash
git checkout v1 -- <path>     # pull a v1 file back as reference
git checkout v1               # the full old tree lives on this branch
git checkout archive-v1       # ...or an earlier v1 checkpoint (tag)
```

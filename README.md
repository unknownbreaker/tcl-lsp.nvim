# tcl-lsp

A focused Language Server for **TCL** and **RVT** (Apache Rivet templates), for
Neovim and Vim. The server is a self-contained Go binary; Neovim and Vim clients
drive the same binary.

Scope is deliberately tight — **go-to-definition**, **find-references**, and
**document/workspace symbols**, done well (scope-correct, cross-file,
`.rvt`-aware) — rather than a broad, shallow feature set.

## Features

| LSP feature                | Status |
| -------------------------- | :----: |
| Go to definition           |   ✅   |
| Find references            |   ✅   |
| Document / workspace symbols |  ✅   |
| Call hierarchy             |   ✅   |
| Hover                      |   ❌   |
| Completion                 |   ❌   |
| Signature help             |   ❌   |
| Rename                     |   ❌   |
| Formatting                 |   ❌   |
| Diagnostics                |   ❌   |
| Code actions               |   ❌   |
| Inlay hints / semantic tokens |  ❌  |

`❌` items are out of scope by design (see [Why a v2 reset](#why-a-v2-reset)).

**What the supported features actually do:**

- ✅ **Cross-file** resolution, including `.rvt` ⇄ `.tcl`.
- ✅ **Reaching-definitions** — a `$x` jumps to the assignment(s) that actually
  reach it (through loops, conditionals, `break`/`continue`/`return`), not just
  the first binding.
- ✅ **Scope-correct** — namespaces, `namespace path`/`import`,
  `global`/`upvar`/`variable` link origin-chasing, and arrays.
- ✅ **Symbols, index-backed** — a hierarchical outline of the current file and a
  project-wide name search, built from the same symbol table (procs, namespace
  vars, Itcl classes/methods/ivars); `.rvt` page symbols surface at the top
  level.
- ✅ **Itcl ([incr Tcl]) OO** — classes, methods, instance variables, and
  inheritance resolve, including the `$obj method` receiver call. See
  [Itcl OO support](#itcl-oo-support).
- ✅ **Call hierarchy** — incoming ("who calls this?") and outgoing ("what does
  this call?") for procs and methods, across files and `.rvt` pages. Built on
  references + goto-def, so it inherits the same contract: complete for
  command-position calls (bare and qualified), best-effort for explicit
  `$obj method` / `$this method` calls, which aren't yet traced.

## Itcl OO support

The dominant OO idiom in Rivet/speedtables-style code — `itcl::class`,
`[::C #auto]`, `$obj method` — resolves end-to-end:

- **Classes** — `itcl::class ::C { … }` (and `::itcl::class`) are resolvable
  symbols. Goto-definition on an instantiation (`[::STDisplay #auto]`,
  `::STDisplay create x`, `C objName`) jumps to the class; find-references lists
  every instantiation and use.
- **Members** — `method`, `constructor`, `destructor`, class-level `proc`, and
  `variable`/`common` instance variables, **with or without a `public`/
  `protected`/`private` modifier** (the usual real-world form) — from both inline
  class blocks and external `itcl::body ::C::m { … }` definitions (merged as sites
  for one member).
- **Inheritance** — `inherit` chains are walked (simple `inherit`-order, cycle-
  and diamond-safe), so an inherited method or ivar resolves to its base-class site.
- **Three resolution tiers:**
  1. **Class names** in command position.
  2. **Intra-class** — a bare `method`, `$this method`, or `$ivar` inside a method
     body resolves to the member, including inherited ones.
  3. **`$obj method`** — `set d [::STDisplay #auto]; $d field` types `$d` via the
     reaching-definitions engine and resolves `field` on its class. Instantiation
     forms recognized: `#auto`, `new`, `create name`, `objName`, and bare `[::C …]`.
     The `$obj method` shape is detected both as a statement and bracketed for its
     value (`[$obj method]`), including inside method bodies.
- Classes, methods, and ivars also appear in the **document/workspace symbol**
  outlines, and all of the above works across `.tcl` and `.rvt`.

**Boundaries (graceful — it returns nothing rather than jump wrong):**

- **TclOO** (`oo::class`, `oo::define`) is not supported yet — Itcl only.
- Receivers whose class is not *locally* known — a method parameter, a factory
  return value, an ivar assigned in a different method — stay unresolved (Itcl has
  no type annotations to recover the class from).
- Simple `inherit`-order MRO, not full C3 linearization; no dynamic dispatch,
  `configure`/`cget`, mixins, or `rename`/`interp alias` on classes.
- Protection *blocks* (`public { … }` grouping several declarations) are not yet
  parsed — declare members individually (`public method …`), which is what real
  code overwhelmingly does.

The behavior here is pinned against verbatim excerpts of real Itcl/Rivet code
(`flightaware/speedtables`, `mxmanghi/rivetweb`, `apache/tcl-rivet`); see
[`research/07-realworld-itcl-survey.md`](research/07-realworld-itcl-survey.md).

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
vim.keymap.set("n", "gO", vim.lsp.buf.document_symbol)             -- outline of this file
vim.keymap.set("n", "<leader>ws", function()                       -- search the whole project
  vim.lsp.buf.workspace_symbol(vim.fn.input("Symbol: "))
end)
```

(LazyVim already binds `gd` and `grr`, plus `<leader>ss` for document symbols and
`<leader>sS` for workspace symbols via Telescope.) In Vim: `:LspDefinition` /
`:LspReferences` / `:LspDocumentSymbol` / `:LspWorkspaceSymbol`.

### Symbols

- **Document symbols** (`<leader>ss` / `gO`) — a hierarchical outline of the
  current file: procs, namespace variables, and Itcl classes with their
  methods/ivars, nested by namespace and class. In `.rvt` pages the synthetic
  `::request` wrapper is hidden, so page symbols sit at the top level.
- **Workspace symbols** (`<leader>sS`) — a flat, project-wide search by name
  (case-insensitive substring); each result shows its container namespace or
  class.

A live outline panel ([`aerial.nvim`](https://github.com/stevearc/aerial.nvim)) or
breadcrumbs ([`nvim-navic`](https://github.com/SmiteshP/nvim-navic)) work
automatically once installed — they consume the same document-symbol data.

### Call hierarchy

With the cursor on a proc or method, `vim.lsp.buf.incoming_calls()` lists who
calls it and `vim.lsp.buf.outgoing_calls()` lists what it calls. These aren't
bound by default (not even in LazyVim) — map them yourself, scoped to buffers
where an LSP is attached:

```lua
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    vim.keymap.set("n", "<leader>ci", vim.lsp.buf.incoming_calls,
      { buffer = args.buf, desc = "Incoming calls" })
    vim.keymap.set("n", "<leader>co", vim.lsp.buf.outgoing_calls,
      { buffer = args.buf, desc = "Outgoing calls" })
  end,
})
```

The `desc` makes which-key list them automatically. The built-in functions
populate the **quickfix list** (flat, one level). For an expandable drill-down
tree — the way call hierarchy is most useful — use
[`lspsaga.nvim`](https://github.com/nvimdev/lspsaga.nvim)
(`:Lspsaga incoming_calls` / `:Lspsaga outgoing_calls`). In Vim with vim-lsp:
`:LspCallHierarchyIncoming` / `:LspCallHierarchyOutgoing`.

Works across files and `.rvt` pages; method-to-method edges resolve through the
Itcl class chain (for bare and qualified calls — explicit `$obj method` /
`$this method` edges aren't traced yet).

## Why a v2 reset

v1 (313 commits) tried to do too much and accumulated performance regressions that
were impossible to untangle. v2 inverts the approach: understand TCL's tricky
scope rules first, write them down, then build the minimum that works — which is
why heavier analysis (e.g. the reaching-definitions dataflow) runs only when
needed and stays off the goto-def hot path. Research lives in `research/`, designs
and plans in `docs/`. Deferred work (e.g. TclOO `oo::class` support) is tracked in
[`docs/BACKLOG.md`](docs/BACKLOG.md).

## Recovering the old prototype

The full v1 history is preserved on the `v1` branch (its tip) and at the
`archive-v1` tag (an earlier checkpoint).

```bash
git checkout v1 -- <path>     # pull a v1 file back as reference
git checkout v1               # the full old tree lives on this branch
git checkout archive-v1       # ...or an earlier v1 checkpoint (tag)
```

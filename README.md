# tcl-lsp.nvim

A Language Server Protocol implementation for TCL/RVT, for Neovim and Vim.

> **Status: shipped.** goto-definition and goto-reference work for both `.tcl`
> files and `.rvt` Rivet templates, including cross-file resolution between
> `.rvt` and `.tcl`. Proc-local goto-definition is precise — reaching-definitions:
> a `$x` jumps to the assignment(s) that actually reach it, not just the first
> binding. See `editors/README.md` for setup.
>
> The full v1 history (313 commits) is preserved on the `v1` branch (its tip) and
> at the `archive-v1` tag (an earlier checkpoint).

## Scope

Deliberately tight: **goto-definition** and **goto-reference**, nothing else — no
completion, hover, formatting, diagnostics, or rename. The Go language server is
editor-agnostic (stdio/JSON-RPC); the Neovim (native `vim.lsp`) and Vim (vim-lsp
or coc) clients all drive the same binary.

## Why the reset

v1 tried to do too much at once and accumulated performance regressions that were
impossible to untangle. v2 inverts the approach: understand TCL's (notoriously
tricky) scope rules first, write them down, then build the minimum that works.
That discipline is why heavier analysis — e.g. the reaching-definitions dataflow —
runs only when needed and stays off the goto-def hot path. Research lives in
`research/`, designs and plans in `docs/`.

## What's built

- **goto-definition / goto-reference** for `.tcl` and `.rvt`, cross-file.
- **Scope-correct resolution** — namespaces, `namespace path`/`import`,
  proc-locals, `global`/`upvar`/`variable` link origin-chasing, arrays.
- **Reaching-definitions** for proc-local goto-def — context-sensitive through
  loops, conditionals, and `break`/`continue`/`return`.
- **Editors** — Neovim 0.11+ (native LSP) and classic Vim (vim-lsp or coc);
  `.rvt` filetype detection ships for both.
- **Lifecycle** — the workspace is indexed at startup and kept fresh via
  `workspace/didChangeWatchedFiles`; the bundled server builds on first use and
  rebuilds when its sources change.

Deferred work — notably Itcl/TclOO `$obj method` type-tracking — is tracked in
`docs/BACKLOG.md`.

## Recovering the old prototype

```bash
git checkout v1 -- <path>     # pull a v1 file back as reference
git checkout v1               # the full old tree lives on this branch
git checkout archive-v1       # ...or an earlier v1 checkpoint (tag)
```

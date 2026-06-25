# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project Overview

tcl-lsp is a Language Server Protocol implementation for TCL/RVT, integrated
with Neovim and classic Vim. (The repo was historically named `tcl-lsp.nvim`;
it now ships clients for both editors — the Go server is editor-agnostic.)

**This is a deliberate restart (v2).** A previous implementation (313 commits) grew
too broad — many features, accumulating performance regressions that became
intractable. That work is preserved on the `v1` branch (its tip) and at the
`archive-v1` tag (an earlier checkpoint in the same history); the `main` branch
now holds v2. Recover any piece with `git checkout v1 -- <path>`.

## Current Phase: Phase A + Phase B shipped, plus document/workspace symbols

**goto-definition** and **goto-reference** are implemented for both `.tcl` files
(Phase A) and `.rvt` Rivet templates (Phase B), including cross-file resolution
between `.rvt` and `.tcl`. **Document symbols** (`textDocument/documentSymbol`,
hierarchical) and **workspace symbols** (`workspace/symbol`) are also implemented,
serializing the index's existing symbol data (procs, namespace vars, Itcl
classes/methods/ivars). The implementation lives under `server/` (Go LSP server
with stdio/JSON-RPC framing). Research lives in `research/`; plans in `docs/plans/`.

Scope is deliberately limited to those features. Document and workspace symbols
were a considered, index-backed addition; the remaining LSP features (completion,
hover, formatting, diagnostics, rename, etc.) remain out of scope — do not propose
or scaffold them.

## Working Agreements

- Research output lives in `research/` as Markdown (create it when starting).
- Plans live in `docs/plans/` once research is mapped.
- Keep changes small and verified; resist re-expanding scope.

## Recovering v1

```bash
git log v1 --oneline              # browse the old history (full v1 tip)
git checkout v1 -- tcl/           # pull a specific path back as reference
git checkout v1                   # the full old tree lives on this branch
git checkout archive-v1           # ...or an earlier v1 checkpoint (tag)
```

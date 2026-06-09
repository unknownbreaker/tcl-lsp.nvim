# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project Overview

tcl-lsp.nvim is a Language Server Protocol implementation for TCL/RVT, integrated
with Neovim.

**This is a deliberate restart (v2).** A previous implementation (313 commits) grew
too broad — many features, accumulating performance regressions that became
intractable. That work is preserved at the `archive-v1` tag and on the `main`
branch; recover any piece with `git checkout archive-v1 -- <path>`.

## Current Phase: Phase A + Phase B shipped

**goto-definition** and **goto-reference** are implemented for both `.tcl` files
(Phase A) and `.rvt` Rivet templates (Phase B), including cross-file resolution
between `.rvt` and `.tcl`. The implementation lives under `server/` (Go LSP server
with stdio/JSON-RPC framing). Research lives in `research/`; plans in `docs/plans/`.

Scope remains tight: only those two features. Do not propose or scaffold additional
LSP features (completion, hover, formatting, diagnostics, rename, etc.).

## Working Agreements

- Research output lives in `research/` as Markdown (create it when starting).
- Plans live in `docs/plans/` once research is mapped.
- Keep changes small and verified; resist re-expanding scope.

## Recovering v1

```bash
git log archive-v1 --oneline      # browse the old history
git checkout archive-v1 -- tcl/   # pull a specific path back as reference
git checkout main                 # the full old tree still lives here
```

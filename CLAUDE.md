# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project Overview

tcl-lsp.nvim is a Language Server Protocol implementation for TCL/RVT, integrated
with Neovim.

**This is a deliberate restart (v2).** A previous implementation (313 commits) grew
too broad — many features, accumulating performance regressions that became
intractable. That work is preserved at the `archive-v1` tag and on the `main`
branch; recover any piece with `git checkout archive-v1 -- <path>`.

## Current Phase: Research, not implementation

We are **not building features yet.** The v1 failure mode was implementing before
understanding TCL's scope semantics. The current goal is the opposite:

1. **Research first.** Rigorously map TCL and RVT scope behavior — variables,
   namespaces, procs, `upvar`/`global`/`uplevel`, namespace resolution rules, and
   how RVT templates affect all of it. Produce clear, written specs.
2. **Plan from the research.** Only once scope behavior is mapped, design how to
   build it.
3. **Scope tightly.** The v2 target is just two reliable features:
   **goto-definition** and **goto-reference**. Nothing else until those are solid.

Do not propose or scaffold additional LSP features (completion, hover, formatting,
diagnostics, rename, etc.) during this phase.

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

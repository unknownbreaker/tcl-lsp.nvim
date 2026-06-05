# tcl-lsp.nvim

A Language Server Protocol implementation for TCL/RVT in Neovim.

> **Status: rebuilding (v2).** This project was reset from a broad v1 prototype
> to a tightly-scoped, research-first effort. The initial goal is two reliable
> features — **goto-definition** and **goto-reference** — built on a rigorous
> understanding of TCL/RVT scope semantics.
>
> The full v1 history (313 commits) is preserved at the `archive-v1` tag.

## Why the reset

v1 tried to do too much at once and accumulated performance regressions that were
impossible to untangle. v2 inverts the approach: understand TCL's (notoriously
tricky) scope rules first, write them down, then build the minimum that works.

## Roadmap

1. **Research** — map TCL + RVT scope behavior (variables, namespaces, procs,
   `upvar`/`global`/`uplevel`, RVT templates). Output in `research/`.
2. **Plan** — design goto-definition + goto-reference from the research.
3. **Build** — implement, scoped tightly to those two features.

## Recovering the old prototype

```bash
git checkout archive-v1 -- <path>   # pull a file back as reference
git checkout main                   # the full v1 tree
```

# TCL/RVT Scope Semantics Research

The goal of this research is to **map TCL and RVT name-resolution behavior
precisely enough to design reliable goto-definition and goto-reference** before
writing any implementation. (See `../CLAUDE.md` for why the project was reset to
a research-first approach.)

## Method

- Every claim is **verified empirically** with `tclsh`, not asserted from memory.
- Experiment scripts live in `experiments/` and are runnable: `tclsh experiments/NN_name.tcl`.
- Findings documents quote the observed output and draw out the implication for a
  static resolver (an LSP cannot `eval`; it must replicate TCL's resolution rules
  by static analysis).

## Environment / target version

- **Target: TCL 8.6** (the Rivet/RVT baseline). Run all experiments with:
  `/opt/homebrew/opt/tcl-tk@8/bin/tclsh experiments/NN_name.tcl`
  (installed via `brew install tcl-tk@8`, version 8.6.18, keg-only).
- A 9.0.3 `tclsh` is also present (the default on PATH) and is used as a
  cross-check. Topic 01 was verified **identical** on 8.6.18 and 9.0.3.
- When a behavior differs between 8.6 and 9.0, the findings doc must call it out.

## Findings index

| # | Topic | Status |
|---|-------|--------|
| 01 | [Variable scope & resolution](01-variable-scope.md) | ✅ verified on 8.6 + 9.0 |
| 02 | [Namespace name resolution (commands vs variables)](02-namespace-resolution.md) | ✅ verified on 8.6 + 9.0 |
| 03 | [Proc / command definition & call-site resolution](03-proc-resolution.md) | ✅ verified on 8.6 + 9.0 |
| 04 | [`source` / `package` / multi-file resolution](04-source-multifile.md) | ✅ verified on 8.6 + 9.0 |
| 05 | [RVT (Rivet template) scope implications](05-rvt-scope.md) | 🟡 partially verified (Rivet not installed; see [CONFIRM] items) |
| 06 | Synthesis → resolver model + v2 scope (bridge to planning) | ⏳ proposed |

## Why this order

goto-definition and goto-reference hinge most on **name resolution** — given a
symbol at a cursor, which declaration does it bind to? Variables (01) and
namespaces (02) are the foundation; the command-vs-variable asymmetry surfaced in
01 is the single biggest source of TCL's "wacky" reputation.

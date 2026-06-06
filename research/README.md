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

## Environment note

- Local `tclsh` is **9.0.3**. The project previously claimed "TCL 8.6+".
- **Open question:** which TCL version(s) must the LSP target? Rivet/RVT
  historically runs on 8.6. Most scope/namespace semantics are stable across
  8.6 → 9.0, but this must be pinned down before the design phase, and any
  version-sensitive behavior must be re-checked on the real target.

## Findings index

| # | Topic | Status |
|---|-------|--------|
| 01 | [Variable scope & resolution](01-variable-scope.md) | ✅ drafted (verified) |
| 02 | Namespace name resolution (commands vs variables) | ⏳ next |
| 03 | Proc / command resolution at call sites | ⏳ |
| 04 | `source` / `package` / multi-file resolution | ⏳ |
| 05 | RVT (Rivet template) scope implications | ⏳ |

## Why this order

goto-definition and goto-reference hinge most on **name resolution** — given a
symbol at a cursor, which declaration does it bind to? Variables (01) and
namespaces (02) are the foundation; the command-vs-variable asymmetry surfaced in
01 is the single biggest source of TCL's "wacky" reputation.

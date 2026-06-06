# TCL Coding Conventions

Conventions for TCL code in this repo.

> **Scope note (v2):** Architecture-specific conventions — namespace layout,
> module boundaries, file structure, test organization — are **deliberately
> deferred** until the v2 design is settled (see the research → plan phases in
> CLAUDE.md). Prescribing structure before understanding the problem was a v1
> mistake. This file currently covers only language-level practices that hold
> regardless of architecture. Add structural conventions here once they are
> earned by a written design.

## Language Baseline

- **Bracing:** prefer `{}` over `""` for blocks and expressions; only use quotes
  when you specifically want substitution.
- **Expressions:** always brace `expr` arguments — `expr {$a + $b}`, never
  `expr $a + $b` (correctness and performance).
- **Lists:** build and manipulate lists with `list`, `lappend`, `lindex`, etc.,
  not string concatenation.
- **Conditionals/loops:** brace the condition and body — `if {$x} { ... }`.
- **Quoting:** be deliberate about when substitution happens; avoid relying on
  double-substitution.

## Error Handling

- Use `try`/`trap`/`finally` (TCL 8.6+) or `catch` for recoverable errors.
- Fail loudly on programming errors; don't silently swallow exceptions.

## Style

- Keep procs small and single-purpose.
- Name things descriptively; avoid cryptic abbreviations.
- Comment *why*, not *what*, where intent isn't obvious.

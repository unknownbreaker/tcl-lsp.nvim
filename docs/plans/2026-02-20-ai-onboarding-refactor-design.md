# AI Agent Onboarding Refactor Design

**Date:** 2026-02-20
**Goal:** Restructure project documentation so a fresh Claude Code session can start writing correct code in 1-2 turns instead of 10+.

## Problem

CLAUDE.md is auto-loaded into every session's system prompt, but ~40% of its content is workflow ceremony (beads, session protocols, make commands) rather than architectural understanding. A fresh agent must spawn an Explore subagent (~65K tokens) just to map the codebase.

The README describes a past refactoring, not the project itself. The 20+ design docs in `docs/plans/` are per-feature with no system-level overview.

## Approach: Dense CLAUDE.md

Restructure CLAUDE.md to frontload the architectural mental model. Move workflow/tooling to DEVELOPMENT.md. Every line in CLAUDE.md earns its place by helping a fresh agent write correct code faster.

## New CLAUDE.md Structure (~145 lines)

| Section | Lines | Purpose |
|---------|-------|---------|
| Project Identity | 5 | What this is, filetypes, requirements |
| Architecture + Data Flow | 30 | ASCII diagram: keypress -> feature -> analyzer -> cache -> parser -> tclsh -> JSON -> back. Why two languages. |
| Module Map | 40 | Annotated directory tree with 1-line purpose per file, dependency notes |
| AST Contract | 20 | Node structure, key fields, var_name type gotcha, link to schema.lua |
| Invariants | 20 | 8 load-bearing constraints that break the system if violated |
| Key Patterns | 15 | Feature pattern, AST traversal pattern, TCL module pattern |
| Commands | 10 | Essential make targets + single-test commands |
| Pointers | 5 | Links to DEVELOPMENT.md, docs/plans/, .claude/rules/ |

## What Moves to DEVELOPMENT.md

- Session Start requirements (`/using-superpowers`)
- Progress Tracking (beads workflow, `bd` commands)
- Development Workflow details (schema-first, TDD steps, review)
- Session Close Protocol (git/beads commit checklist)
- Development Notes (file size limits, worktrees)

## README.md Change

Replace the refactoring guide with a proper project README:
- What this is (1 paragraph)
- Features list
- Installation (lazy.nvim)
- Quick start
- Configuration
- Links to CLAUDE.md/DEVELOPMENT.md for contributors

## Key Design Decisions

1. **CLAUDE.md is architecture-only** because it's the only document auto-loaded. Workflow can be discovered; architecture can't.
2. **Data flow diagram is the centerpiece** because it saves ~10 tool calls and ~15K tokens of exploration every session.
3. **Invariants are promoted from "gotchas"** because they're not trivia — they're constraints that prevent system breakage.
4. **Module map includes 1-line annotations** because knowing what a file *does* without reading it is the biggest time-saver.
5. **Commands section is minimal** because agents can discover commands via `make help` or reading the Makefile.

## Files Changed

- `CLAUDE.md` — rewritten (architecture-focused)
- `DEVELOPMENT.md` — new (workflow/tooling moved here)
- `README.md` — rewritten (project overview, not refactoring log)
- `.claude/rules/` — unchanged (conventions stay where they are)
- `docs/plans/` — unchanged (per-feature docs stay)

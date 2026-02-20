# AI Agent Onboarding Refactor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Restructure project documentation so a fresh Claude Code session can start writing correct code in 1-2 turns instead of 10+.

**Architecture:** Three files change: CLAUDE.md is rewritten to be architecture-dense (the only auto-loaded context), DEVELOPMENT.md is created for workflow/tooling, README.md is rewritten as a proper project overview. No code changes.

**Tech Stack:** Markdown only. No code, no tests — this is a pure documentation refactor.

---

### Task 1: Create DEVELOPMENT.md with workflow content extracted from CLAUDE.md

**Files:**
- Create: `DEVELOPMENT.md`
- Reference: `CLAUDE.md` (current content to extract from)

**Step 1: Write DEVELOPMENT.md**

This file receives everything from current CLAUDE.md that is workflow/tooling rather than architecture. Content:

```markdown
# Development Guide

## Session Start

Always invoke `/using-superpowers` at the start of every session. This loads the skill routing system.

## Progress Tracking

Use beads to track all significant work:

\```bash
bd create --title="Feature/task name" --type=feature|task|bug --priority=2 \
  --description="What needs to be done and why"
bd update <id> --status=in_progress    # While working
bd close <id> --reason="Completed"     # When done
bd ready                                # Check what's ready
bd sync                                 # Sync at session end
\```

Do NOT use TodoWrite for task tracking. Use beads for everything.

## Development Workflow

Schema-first, test-first, small-scope. One beads issue = one focused change.

### For new features:

1. **Plan** — `bd stats`, `bd ready`, create beads issues with dependencies
2. **Schema** — Define data shapes in `parser/schema.lua` first, run `/validate-schema`
3. **TDD** — Write failing tests, use `adversarial-tester` agent for edge cases, then implement until green
4. **Review** — `/lint`, use `lua-reviewer` or `tcl-reviewer` agents, `make pre-commit`
5. **Ship** — Commit, push, `bd sync`

## Session Close Protocol

Never skip this. Work is not done until pushed.

\```bash
git status                  # Check what changed
git add <files>             # Stage code changes
bd sync                     # Commit beads changes
git commit -m "feat: ..."   # Commit code
bd sync                     # Commit any new beads changes
git push                    # Push to remote
\```

## Development Notes

- Filetypes: `.tcl` and `.rvt` (Rivet templates)
- Requires: Neovim 0.11.3+, TCL 8.6+
- Test framework: plenary.nvim (Lua), native self-tests (TCL)
- Keep files under 700 lines; parser modules average 107 lines
- Worktrees: Use `.worktrees/` directory (gitignored) for feature branches
- Design docs: `docs/plans/YYYY-MM-DD-<feature>-design.md`
```

**Step 2: Verify the file reads correctly**

Run: `wc -l DEVELOPMENT.md`
Expected: ~55 lines

**Step 3: Commit**

```bash
git add DEVELOPMENT.md
git commit -m "docs: extract workflow/tooling to DEVELOPMENT.md"
```

---

### Task 2: Rewrite CLAUDE.md as architecture-dense context

**Files:**
- Modify: `CLAUDE.md` (full rewrite)
- Reference: `lua/tcl-lsp/init.lua`, `lua/tcl-lsp/parser/ast.lua`, `lua/tcl-lsp/parser/schema.lua`, `lua/tcl-lsp/utils/cache.lua`, `tcl/core/parser.tcl`

**Step 1: Rewrite CLAUDE.md**

Replace entire contents with architecture-focused document (~145 lines). Key sections in order:

1. **Project Identity** (3 lines) — what, filetypes, requirements
2. **Architecture + Data Flow** (30 lines) — ASCII diagram showing full path from keypress through features → analyzer → cache → parser/ast.lua → tclsh process → JSON → back. Note: each parse spawns fresh tclsh, cache prevents redundant spawns via changedtick.
3. **Module Map** (40 lines) — annotated directory tree covering both `lua/tcl-lsp/` and `tcl/core/` with 1-line purpose per file. Mark entry points. Note parser_utils.tcl must load last.
4. **The AST Contract** (15 lines) — node structure (type, range, depth), key node types (root, proc, set, namespace_eval, command), var_name type warning, link to schema.lua for full 25-type schema.
5. **Invariants** (15 lines) — 8 numbered constraints: shutdown order, depth limits, parser purity, cache keying, var_name type, same-file fallback, TCL load order, indexer disabled by default. Each with file reference.
6. **Key Patterns** (15 lines) — feature module pattern (setup → autocmd → handle_*), AST traversal (visit_node with depth guard, recurse children AND body.children), TCL module pattern (namespace, self-test guard, <200 lines).
7. **Commands** (10 lines) — make test, make lint, single Lua test command, single TCL test command.
8. **Pointers** (5 lines) — links to DEVELOPMENT.md, docs/plans/, .claude/rules/

**Step 2: Verify line count**

Run: `wc -l CLAUDE.md`
Expected: 130-150 lines (must stay under 200 for auto memory truncation)

**Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: rewrite CLAUDE.md as architecture-dense AI context"
```

---

### Task 3: Rewrite README.md as project overview

**Files:**
- Modify: `README.md` (full rewrite)

**Step 1: Write new README.md**

Replace the refactoring guide with a proper project overview. Sections:

1. **Title + description** — "tcl-lsp.nvim: TCL Language Server for Neovim"
2. **Features** — bullet list of implemented LSP features (definition, references, hover, diagnostics, rename, completion, formatting, folding, highlights, semantic tokens)
3. **Requirements** — Neovim 0.11.3+, TCL 8.6+, tclsh in PATH
4. **Installation** — lazy.nvim example
5. **Configuration** — basic setup call with config options
6. **Usage** — key commands and keymaps
7. **Architecture** — 3-sentence summary linking to CLAUDE.md for details
8. **Contributing** — link to CONTRIBUTING.md and DEVELOPMENT.md
9. **Status** — "Active development. Core LSP features implemented."

**Step 2: Verify it reads as a coherent project overview**

Run: `head -20 README.md`
Expected: Title, description, and features list — not refactoring language.

**Step 3: Commit**

```bash
git add README.md
git commit -m "docs: rewrite README as project overview"
```

---

### Task 4: Verify the full documentation set is coherent

**Step 1: Check all three files exist and have reasonable sizes**

Run: `wc -l CLAUDE.md DEVELOPMENT.md README.md`
Expected:
- CLAUDE.md: 130-150 lines
- DEVELOPMENT.md: 50-60 lines
- README.md: 60-90 lines

**Step 2: Check for broken cross-references**

Verify these references resolve:
- CLAUDE.md mentions `DEVELOPMENT.md` → file exists
- CLAUDE.md mentions `docs/plans/` → directory exists
- CLAUDE.md mentions `.claude/rules/lua-conventions.md` → file exists
- CLAUDE.md mentions `.claude/rules/tcl-conventions.md` → file exists
- CLAUDE.md mentions `parser/schema.lua` → file exists at `lua/tcl-lsp/parser/schema.lua`
- README.md mentions `CONTRIBUTING.md` → file exists
- README.md mentions `DEVELOPMENT.md` → file exists

**Step 3: Final commit (if any fixups needed)**

```bash
git add -A
git commit -m "docs: fix cross-references in documentation"
```

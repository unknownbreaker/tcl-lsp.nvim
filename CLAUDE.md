# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

tcl-lsp.nvim is a Language Server Protocol (LSP) implementation for TCL that integrates with Neovim. It provides intelligent code editing features for TCL/RVT files.

**Current Status:** Core LSP features implemented (definition, references, hover, diagnostics, rename, completion, formatting, folding, highlights, semantic tokens). Stub files (0 bytes) indicate planned features.

## Session Start (REQUIRED)

**Always invoke `/using-superpowers` at the start of every session.** This loads the skill routing system that ensures the correct workflow skills (TDD, debugging, brainstorming, code review, etc.) are used for each task.

## Progress Tracking (REQUIRED)

**You MUST use beads to track all significant work.** This is not optional.

```bash
# Before starting work
bd create --title="Feature/task name" --type=feature|task|bug --priority=2 \
  --description="What needs to be done and why"

# While working
bd update <id> --status=in_progress

# When done
bd close <id> --reason="Completed description"

# Check what's ready to work on
bd ready

# Sync at session end
bd sync
```

**Why this matters:**
- Work persists across sessions and context compaction
- Handoffs to other sessions have full context
- Dependencies between tasks are tracked
- Progress is visible via `bd stats`

Do NOT use TodoWrite for task tracking. Use beads for everything.

## Commands

```bash
# Run all tests (Lua + TCL)
make test

# Run unit tests only
make test-unit

# Run a specific Lua test file
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "lua require('plenary.test_harness').test_directory('tests/lua/', {minimal_init = 'tests/minimal_init.lua', filter = 'server'})" \
  -c "qa!"

# Run TCL tests
tclsh tests/tcl/core/ast/run_all_tests.tcl

# Run a specific TCL test module
tclsh tcl/core/ast/json.tcl

# Linting
make lint          # All (Lua + TCL)
make lint-lua      # Lua only (luacheck)
make lint-tcl      # TCL only (nagelfar)

# Formatting
make format-lua    # Format Lua with stylua
```

## Architecture

### Two-Language Design

TCL handles parsing, Lua handles Neovim integration. They communicate via JSON: the TCL parser (`tcl/core/`) produces an AST serialized as JSON, and the Lua side (`lua/tcl-lsp/parser/ast.lua`) deserializes it for analysis. Stub files (0 bytes) indicate planned but unimplemented modules.

Key directories: `parser/` (TCL bridge + schema), `analyzer/` (indexing + symbol resolution), `features/` (LSP handlers), `actions/` (code actions).

### Public API

**TCL Parser:**
```tcl
set ast [::ast::build $code $filepath]  # Parse TCL code to AST
set json [::ast::to_json $ast]          # Convert AST to JSON
```

**Lua Plugin:**
```lua
require("tcl-lsp").setup({})  -- Initialize plugin
-- User commands: :TclLspStart, :TclLspStop, :TclLspRestart, :TclLspStatus
```

### Adding New Features

Each feature module in `lua/tcl-lsp/features/` follows this pattern:
1. Create `features/<name>.lua` with `M.setup()` function
2. Create `tests/lua/features/<name>_spec.lua` with plenary tests
3. Register in `init.lua`: add require and call `<name>.setup()` in `M.setup()`

### Test Structure

- `tests/lua/` - Lua unit tests using plenary.nvim (spec files)
- `tests/tcl/core/ast/` - TCL parser tests (self-contained, run with tclsh)
- `tests/integration/` - End-to-end tests

Each TCL module has built-in self-tests runnable directly: `tclsh tcl/core/ast/json.tcl`

## Development Workflow

Schema-first, test-first, small-scope. One beads issue = one focused change.

### For new features:

1. **Plan** — `bd stats`, `bd ready`, create beads issues with dependencies
2. **Schema** — Define data shapes in `parser/schema.lua` first, run `/validate-schema`
3. **TDD** — Write failing tests, use `adversarial-tester` agent for edge cases, then implement until green
4. **Review** — `/lint`, use `lua-reviewer` or `tcl-reviewer` agents, `make pre-commit`
5. **Ship** — Commit, push, `bd sync`

### Session close protocol:

**Never skip this.** Work is not done until pushed.

```bash
git status                  # Check what changed
git add <files>             # Stage code changes
bd sync                     # Commit beads changes
git commit -m "feat: ..."   # Commit code
bd sync                     # Commit any new beads changes
git push                    # Push to remote
```

## Known Gotchas

- **Indexer must stop before parser cleanup on quit.** Otherwise Neovim hangs on exit because the indexer holds references to the parser process.
- **Background indexer is disabled by default.** Enabling it caused UI lag. Any background processing must be carefully throttled.
- **AST traversal needs depth limits.** The ref_extractor hit infinite recursion on deeply nested/circular structures. Always guard recursive AST walks with a depth limit.
- **`var_name` in AST nodes can be a table, not just a string.** The extractor must handle both types. Don't assume string.
- **Same-file references need a fallback path.** Cross-file reference resolution can fail; always fall back to same-file search.
- **AST cache keys on changedtick.** Features should use `cache.parse(bufnr)` instead of `parser.parse(code)` for buffer-based operations. The parser module stays pure (no buffer awareness) for testing and file-based parsing. Tests that mock `parser.parse_with_errors` must also clear `package.loaded["tcl-lsp.utils.cache"]` so the cache picks up the fresh parser reference.

## Development Notes

- Filetypes: `.tcl` and `.rvt` (Rivet templates)
- Requires: Neovim 0.11.3+, TCL 8.6+
- Test framework: plenary.nvim (Lua), native self-tests (TCL)
- Keep files under 700 lines; parser modules average 107 lines
- Worktrees: Use `.worktrees/` directory (gitignored) for feature branches

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

tcl-lsp.nvim is a Language Server Protocol (LSP) implementation for TCL that integrates with Neovim. It provides intelligent code editing features for TCL/RVT files.

**Current Status:** Phase 3 in progress - go-to-definition complete, other LSP features pending.

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

Use TodoWrite only for simple single-step tasks within a session. For anything multi-step, multi-session, or strategic: use beads.

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

The project uses TCL for parsing and Lua for Neovim integration:

```
lua/tcl-lsp/           # Neovim plugin (Lua)
├── init.lua           # Plugin entry, user commands, autocommands
├── config.lua         # Configuration management
├── server.lua         # LSP server lifecycle
├── parser/            # Bridge to TCL parser (Phase 3)
├── features/          # LSP features: completion, hover, diagnostics (stubs)
└── actions/           # Code actions: rename, refactor (stubs)

tcl/core/              # Parser implementation (TCL)
├── tokenizer.tcl      # Token extraction
└── ast/               # AST builder modules
    ├── builder.tcl    # Main orchestrator, public API
    ├── json.tcl       # JSON serialization
    ├── utils.tcl      # Position tracking, ranges
    └── parsers/       # Command-specific parsers
        ├── procedures.tcl
        ├── variables.tcl
        ├── control_flow.tcl
        └── ...
```

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

### Test Structure

- `tests/lua/` - Lua unit tests using plenary.nvim (spec files)
- `tests/tcl/core/ast/` - TCL parser tests (self-contained, run with tclsh)
- `tests/integration/` - End-to-end tests

Each TCL module has built-in self-tests runnable directly: `tclsh tcl/core/ast/json.tcl`

## Development Notes

- Filetypes: `.tcl` and `.rvt` (Rivet templates)
- Requires: Neovim 0.11.3+, TCL 8.6+
- Test framework: plenary.nvim (Lua), native self-tests (TCL)
- Keep files under 700 lines; parser modules average 107 lines

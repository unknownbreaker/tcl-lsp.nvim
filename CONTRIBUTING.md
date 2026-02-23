# Contributing to tcl-lsp.nvim

## For AI Agents

Read these files in order:

1. **`CLAUDE.md`** — Architecture, module map, invariants, AST contract, commands
2. **`DEVELOPMENT.md`** — Workflow, task decision tree, checklists, error handling policy
3. **`.claude/rules/lua-conventions.md`** — Lua patterns (module, feature, visitor, lazy loading)
4. **`.claude/rules/tcl-conventions.md`** — TCL patterns (namespace, module, JSON serialization)

## Quick Start

```bash
make test            # All tests (Lua + TCL)
make lint            # All linting
make format-lua      # Format Lua with stylua
```

## Development Workflow

Schema-first, test-first, small-scope. See `DEVELOPMENT.md` for full details.

1. Write failing test
2. Implement minimal code to pass
3. Run `make test` to verify
4. Commit with conventional commits (`feat:`, `fix:`, `refactor:`, `test:`, `docs:`)

## Key Invariants

These break the system if violated. See `CLAUDE.md` for full list.

- **Shutdown order**: Stop indexer before parser on VimLeavePre (Neovim hangs otherwise)
- **AST depth limit**: Every recursive visit must guard `depth > MAX_DEPTH`
- **Parser purity**: `parser/ast.lua` takes code strings, never buffers
- **var_name type**: Always use `variable.safe_var_name()` (can be string or table)
- **TCL load order**: `parser_utils.tcl` loads last in `builder.tcl`

## Reporting Issues

Use GitHub issues. Include TCL code that reproduces the problem and the expected vs actual behavior.

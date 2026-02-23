# Development Guide

## Session Start

Always invoke `/using-superpowers` at the start of every session. This loads the skill routing system that ensures the correct workflow skills (TDD, debugging, brainstorming, code review, etc.) are used for each task.

## Development Workflow

Schema-first, test-first, small-scope.

### For new features:

1. **Plan** — Design the feature, create issues if multi-session
2. **Schema** — Define data shapes in `parser/schema.lua` first, run `/validate-schema`
3. **TDD** — Write failing tests, use `adversarial-tester` agent for edge cases, then implement until green
4. **Review** — `/lint`, use `lua-reviewer` or `tcl-reviewer` agents, `make pre-commit`
5. **Ship** — Commit, push

### Task Decision Tree

| Task | Files to Create/Modify |
|------|----------------------|
| **Add LSP feature** | `features/<name>.lua` (copy `_template.lua`), `tests/lua/features/<name>_spec.lua`, `init.lua` (require + setup) |
| **Add analyzer module** | `analyzer/<name>.lua`, `tests/lua/analyzer/<name>_spec.lua`. Use `visitor.walk()` unless you need control-flow body traversal (then_body, else_body, etc.) — see `semantic_tokens.lua` for that pattern. |
| **Add TCL parser command** | See checklist below — 6 files across 2 languages. |
| **Add AST node type** | `parser/schema.lua` (define node), TCL parser (emit node), `json.tcl` `list_fields` (if node has list fields), Lua extractor/ref_extractor (add handler), roundtrip test (add case). |
| **Add config option** | `config.lua` (add to defaults), validate if non-trivial type. |
| **Add utility function** | `utils/<name>.lua` (single-purpose module), `tests/lua/utils/<name>_spec.lua`. |

### Adding a new LSP feature:

1. Create `features/<name>.lua` — copy `features/_template.lua`, rename handle function
2. Create `tests/lua/features/<name>_spec.lua` with plenary tests
3. Register in `init.lua`: add require and call `<name>.setup()` in `M.setup()`

### Adding a new TCL parser command (checklist):

All 6 steps are required. Missing any one causes silent failures.

1. **Create parser:** `tcl/core/ast/parsers/<command>.tcl` — implement `::ast::parsers::<command>::parse_<command>`, include self-test
2. **Register in builder:** `tcl/core/ast/builder.tcl` — add to the `foreach module` loop, BEFORE `parser_utils.tcl`
3. **Add dispatch:** `tcl/core/ast/parser_utils.tcl` — add `case` in the command switch statement
4. **Update list_fields:** `tcl/core/ast/json.tcl` line 18 — add any new list field names to `list_fields`
5. **Define schema:** `lua/tcl-lsp/parser/schema.lua` — add node type definition in `M.nodes`
6. **Add handlers:** `lua/tcl-lsp/analyzer/extractor.lua` and/or `ref_extractor.lua` — add visitor handler so symbols are extractable
7. **Add roundtrip test:** `tests/lua/parser/roundtrip_spec.lua` — add a test case to validate the full pipeline

### Testing conventions:

- Clear module cache in `before_each`: `package.loaded["tcl-lsp.module"] = nil`
- Clean up buffers in `after_each`: `vim.api.nvim_buf_delete(bufnr, { force = true })`
- Clean up temp files/dirs in `after_each`: `vim.fn.delete(temp_dir, "rf")`
- Use `tests/spec/path_helpers.lua` for path comparisons (macOS symlink handling)
- Crash reproducers (`test_*.lua`) are standalone scripts, not plenary specs

## Session Close Protocol

Never skip this. Work is not done until pushed.

```bash
git status                  # Check what changed
git add <files>             # Stage code changes
git commit -m "feat: ..."   # Commit code
git push                    # Push to remote
```

## Development Notes

- Filetypes: `.tcl` and `.rvt` (Rivet templates)
- Requires: Neovim 0.11.3+, TCL 8.6+
- Test framework: plenary.nvim (Lua), native self-tests (TCL)
- Keep files under 700 lines; parser modules average 107 lines
- Worktrees: Use `.worktrees/` directory (gitignored) for feature branches
- Design docs: `docs/plans/YYYY-MM-DD-<feature>-design.md`
- Conventions: `.claude/rules/lua-conventions.md`, `.claude/rules/tcl-conventions.md`

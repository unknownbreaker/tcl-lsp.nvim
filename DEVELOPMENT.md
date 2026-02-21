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

### Adding a new LSP feature:

1. Create `features/<name>.lua` with `M.setup()` function
2. Create `tests/lua/features/<name>_spec.lua` with plenary tests
3. Register in `init.lua`: add require and call `<name>.setup()` in `M.setup()`

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

# Development Guide

## Session Start

Always invoke `/using-superpowers` at the start of every session. This loads the skill routing system that ensures the correct workflow skills (TDD, debugging, brainstorming, code review, etc.) are used for each task.

## Progress Tracking

Use beads to track all significant work. Do NOT use TodoWrite for task tracking.

```bash
bd create --title="Feature/task name" --type=feature|task|bug --priority=2 \
  --description="What needs to be done and why"
bd update <id> --status=in_progress    # While working
bd close <id> --reason="Completed"     # When done
bd ready                                # Check what's ready
bd sync                                 # Sync at session end
```

## Development Workflow

Schema-first, test-first, small-scope. One beads issue = one focused change.

### For new features:

1. **Plan** — `bd stats`, `bd ready`, create beads issues with dependencies
2. **Schema** — Define data shapes in `parser/schema.lua` first, run `/validate-schema`
3. **TDD** — Write failing tests, use `adversarial-tester` agent for edge cases, then implement until green
4. **Review** — `/lint`, use `lua-reviewer` or `tcl-reviewer` agents, `make pre-commit`
5. **Ship** — Commit, push, `bd sync`

### Adding a new LSP feature:

1. Create `features/<name>.lua` with `M.setup()` function
2. Create `tests/lua/features/<name>_spec.lua` with plenary tests
3. Register in `init.lua`: add require and call `<name>.setup()` in `M.setup()`

## Session Close Protocol

Never skip this. Work is not done until pushed.

```bash
git status                  # Check what changed
git add <files>             # Stage code changes
bd sync                     # Commit beads changes
git commit -m "feat: ..."   # Commit code
bd sync                     # Commit any new beads changes
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

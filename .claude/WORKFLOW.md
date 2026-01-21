# Development Workflow

A type-driven, test-first workflow for tcl-lsp.nvim using Claude Code agents, skills, and beads issue tracking.

## Philosophy

This workflow is inspired by Boris Cherny's approach to software development:

- **Types/Schemas first**: Define data shapes before implementation
- **Fail early**: Catch errors at the earliest possible moment
- **Test first**: Write failing tests, then make them pass
- **Small scope**: One issue = one focused change
- **Explicit dependencies**: Model blocking relationships clearly
- **Review before merge**: Automated review gates

---

## Phase Start

### 1. Scope & Plan with Beads

Before writing code, create a clear plan in beads:

```bash
# Check project health
bd stats
bd ready                    # See what's unblocked

# Create phase epic
bd create --title="Phase N: Feature Name" --type=epic --priority=1

# Break into typed sub-issues with dependencies
bd create --title="Define schemas for X" --type=task --priority=1
bd create --title="Implement X handler" --type=feature --priority=2
bd create --title="Add tests for X" --type=task --priority=2

# Model dependencies (schema blocks implementation)
bd dep add <impl-id> <schema-id>
bd dep add <tests-id> <impl-id>
```

### 2. Schema-First Development

Before writing any feature code, define the data shapes:

```bash
# Use the architect agent to review design
# "Review the data structures needed for feature X"

# Define schemas FIRST
# Example: lua/tcl-lsp/parser/schema.lua

# Validate schemas work
/validate-schema
```

This catches structural issues before they propagate through the codebase.

### 3. TDD Loop

Follow the red-green-refactor cycle:

```bash
# Claim the issue
bd update <issue-id> --status=in_progress

# Write failing tests first
# Use adversarial-tester agent to find edge cases

# Run tests (should fail)
/test-lua

# Implement until tests pass
/test-lua

# Validate no schema drift
/validate-schema

# Refactor if needed, keeping tests green
```

### 4. Pre-Commit Review Gate

Before committing, run all quality checks:

```bash
# Lint everything
/lint

# Use code reviewers
# lua-reviewer agent for Lua changes
# tcl-reviewer agent for TCL changes

# Run full pre-commit suite
make pre-commit
```

### 5. Session Close Protocol

**Never skip this.** Work is not done until pushed.

```bash
git status                  # Check what changed
git add <files>             # Stage code changes
bd sync                     # Commit beads changes
git commit -m "feat: ..."   # Commit code
bd sync                     # Commit any new beads changes
git push                    # Push to remote
```

---

## Available Tools

### Beads Commands

| Command | Purpose |
|---------|---------|
| `bd ready` | Show issues ready to work (no blockers) |
| `bd list --status=open` | All open issues |
| `bd show <id>` | Detailed issue view with dependencies |
| `bd create --title="..." --type=task` | Create new issue |
| `bd update <id> --status=in_progress` | Claim work |
| `bd close <id>` | Mark complete |
| `bd dep add <issue> <depends-on>` | Add dependency |
| `bd blocked` | Show all blocked issues |
| `bd sync` | Sync with git remote |
| `bd stats` | Project statistics |

### Skills (Slash Commands)

| Skill | Purpose |
|-------|---------|
| `/lint` | Run linting for Lua and TCL |
| `/test-lua` | Run Lua/Neovim plugin tests |
| `/test-tcl` | Run TCL parser tests |
| `/parse-ast` | Parse TCL code and display AST |
| `/validate-schema` | Validate TCL AST against Lua schema |

### Agents

| Agent | Purpose |
|-------|---------|
| `architect` | Review code structure and modularity |
| `lua-reviewer` | Review Lua code for best practices |
| `tcl-reviewer` | Review TCL code for best practices |
| `adversarial-tester` | Write tests to break code |
| `schema-validator` | Detect TCL/Lua serialization drift |
| `lua-lsp` | Neovim Lua plugin and LSP work |

---

## Example Session

```
You: "Start working on Phase 4 - LSP completion"

Claude:
  1. bd ready              → Find available work
  2. bd update <id>        → Claim the issue
  3. Define schemas        → Type-first approach
  4. Write failing tests   → TDD red phase
  5. Implement             → TDD green phase
  6. /validate-schema      → Check for drift
  7. lua-reviewer agent    → Code review
  8. make pre-commit       → Full quality gate
  9. git commit & push     → Ship it
  10. bd sync              → Update issue tracker
```

---

## Key Principles

| Principle | Implementation |
|-----------|----------------|
| Types first | Define `schema.lua` before features |
| Fail early | `/validate-schema` catches drift immediately |
| Test first | `adversarial-tester` + `/test-lua` before coding |
| Small scope | One beads issue = one focused change |
| Dependencies explicit | `bd dep add` to model blockers |
| Review before merge | `lua-reviewer`, `tcl-reviewer` agents |

---

## Appendix: Agent Architecture

### How Agents Work

Agents run independently in their own context windows, separate from the main conversation:

```
┌─────────────────────────────────────────────────┐
│  Main Conversation                              │
│  - Full history with you                        │
│  - Orchestrates work                            │
│  - All tools available                          │
└─────────────────────────────────────────────────┘
        │
        │ Task tool spawns agents
        ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ lua-reviewer │  │ tcl-reviewer │  │ adversarial- │
│              │  │              │  │ tester       │
│ Own context  │  │ Own context  │  │ Own context  │
│ Limited tools│  │ Limited tools│  │ Limited tools│
└──────────────┘  └──────────────┘  └──────────────┘
        │                │                  │
        └────────────────┴──────────────────┘
                         │
                         ▼
              Results return to main conversation
              (summarized for you)
```

### Benefits

1. **Context efficiency**: Heavy exploration doesn't consume tokens in the main conversation
2. **Parallelism**: Multiple agents can run simultaneously
3. **Specialization**: Each agent has focused tools and instructions
4. **Background execution**: Agents can run in background while other work continues

### Execution Modes

**Parallel execution**: Multiple agents launched at once
```
Task: lua-reviewer → "Review schema.lua"
Task: tcl-reviewer → "Review json.tcl"
# Both run simultaneously
```

**Background execution**: Agent runs while conversation continues
```
Task (background): adversarial-tester → "Find edge cases in parser"
# Continue other work, check results later
```

**Sequential execution**: Wait for one agent before starting another
```
Task: architect → "Design the feature"
# Wait for result
Task: adversarial-tester → "Write tests based on design"
```

### Agent Tool Access

Each agent type has specific tools available:

| Agent Type | Available Tools |
|------------|-----------------|
| `lua-reviewer` | Read, Grep, Glob, Bash |
| `tcl-reviewer` | Read, Grep, Glob, Bash |
| `adversarial-tester` | Read, Grep, Glob, Bash, Write, Edit |
| `architect` | Read, Grep, Glob, Bash |
| `researcher` | Read, Grep, Glob, WebFetch, WebSearch |

Agents cannot access tools outside their allowed set, providing security and focus.

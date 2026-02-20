# CLAUDE.md

tcl-lsp.nvim: TCL/RVT Language Server Protocol implementation for Neovim.
Filetypes: `.tcl`, `.rvt` (Rivet templates). Requires Neovim 0.11.3+, TCL 8.6+.

## Architecture

Two-language design: TCL parses TCL (it's the best at its own syntax), Lua handles Neovim integration. JSON is the contract between them.

### Data Flow

```
User action (e.g. `gd` for go-to-definition)
      │
      ▼
features/<name>.lua          ← M.setup() registers keymap + user command
      │ calls
      ▼
analyzer/<module>.lua        ← symbol resolution, reference finding
      │ calls
      ▼
utils/cache.lua              ← per-buffer AST cache (keyed on changedtick)
      │ cache miss? spawns:
      ▼
parser/ast.lua               ← `tclsh tcl/core/parser.tcl <tmpfile>` via vim.fn.jobstart
      │                        (stdio, 10s timeout, fresh process each time)
      ▼
tcl/core/parser.tcl          ← reads file → ::ast::build → ::ast::to_json → stdout
      │
      ▼
tcl/core/ast/builder.tcl     ← orchestrator: loads modules, dispatches to parsers/
      │
      ▼
JSON string back via stdout  → parser/ast.lua → vim.json.decode → Lua table
      │
      ▼
analyzer + features          ← traverse AST, produce LSP responses
```

Each parse spawns a fresh `tclsh` process (no persistent server). Cache prevents redundant spawns by keying on buffer `changedtick`.

## Module Map

```
lua/tcl-lsp/
├── init.lua                  ← ENTRY: setup(), autocommands, user commands
├── config.lua                ← config defaults, validation, deep merge
├── server.lua                ← LSP client lifecycle (start/stop/restart)
├── parser/
│   ├── ast.lua               ← spawns tclsh, parses JSON (sync + async)
│   ├── schema.lua            ← AST node type definitions (25 types)
│   ├── validator.lua         ← validates AST against schema
│   ├── symbols.lua           ← symbol extraction from AST
│   ├── scope.lua             ← scope analysis
│   └── rvt.lua               ← Rivet template support
├── analyzer/
│   ├── definitions.lua       ← find_definition(bufnr, line, col)
│   ├── references.lua        ← find_references(bufnr, line, col)
│   ├── extractor.lua         ← extract symbol definitions from AST
│   ├── ref_extractor.lua     ← extract references (with depth guard!)
│   ├── semantic_tokens.lua   ← token classification for highlighting
│   ├── indexer.lua           ← background workspace indexer (OFF by default)
│   ├── index.lua             ← symbol index storage
│   └── docs.lua              ← documentation extraction
├── features/                 ← each has M.setup() → autocmd → handle_<action>
│   ├── definition.lua        ← gd keybind
│   ├── references.lua        ← find all references
│   ├── hover.lua             ← hover information
│   ├── diagnostics.lua       ← error/warning reporting
│   ├── rename.lua            ← symbol rename
│   ├── completion.lua        ← code completion
│   ├── formatting.lua        ← code formatting
│   ├── folding.lua           ← fold ranges
│   └── highlights.lua        ← semantic highlighting
├── actions/                  ← code actions (rename, refactor, cleanup)
├── utils/
│   ├── cache.lua             ← AST cache keyed on changedtick
│   └── logger.lua, helpers.lua
└── data/packages.lua         ← built-in TCL package database

tcl/core/
├── parser.tcl                ← ENTRY: reads file, ::ast::build, outputs JSON
├── tokenizer.tcl             ← TCL tokenization
└── ast/
    ├── builder.tcl           ← orchestrator, loads modules in dependency order
    ├── json.tcl              ← AST dict → JSON string
    ├── utils.tcl             ← position tracking, make_range
    ├── comments.tcl          ← comment extraction
    ├── commands.tcl          ← command splitting
    ├── folding.tcl           ← fold region detection
    ├── delimiters.tcl        ← delimiter handling
    ├── parser_utils.tcl      ← shared parser utilities (LOADS LAST)
    └── parsers/              ← one file per TCL command type
        procedures.tcl, variables.tcl, control_flow.tcl,
        namespaces.tcl, packages.tcl, expressions.tcl, lists.tcl
```

## The AST Contract

Every AST node is a Lua table (deserialized from JSON) with at minimum:
- `type` (string): `"root"`, `"proc"`, `"set"`, `"if"`, `"namespace_eval"`, `"command"`, etc.
- `range` (table): `{ start = {line, column}, end_pos = {line, column} }` (1-indexed)
- `depth` (number): nesting depth

Root adds: `filepath`, `children[]`, `comments`, `had_error` (0|1), `errors[]`
Proc adds: `name`, `params[]` ({name, default?, is_varargs?}), `body.children[]`
Set adds: `var_name`, `value`. Namespace_eval adds: `name`, `body`.
Command (fallback): `name`, `args[]`. Full schema (25 types): `parser/schema.lua`

**CRITICAL: `var_name` can be a string OR a table** (for array access like `arr($key)`). Every code path reading `var_name` must type-check first. This is the #1 bug source.

## Invariants

These are load-bearing. Violating any one breaks the system.

1. **Shutdown order**: On VimLeavePre, stop indexer FIRST, then parser. Reversed = Neovim hangs. (init.lua:68-85)
2. **AST depth limit**: Every recursive `visit_node` MUST guard `depth > MAX_DEPTH`. Infinite recursion without it.
3. **Parser purity**: `parser/ast.lua` takes code strings, never buffers. Buffer-aware parsing → `utils/cache.lua`.
4. **Cache key**: changedtick, not content. Tests mocking `parser.parse_with_errors` must clear `package.loaded["tcl-lsp.utils.cache"]`.
5. **var_name type**: String or table. Always type-check. (See AST Contract.)
6. **Same-file fallback**: Cross-file ref resolution can fail. Always fall back to same-file search.
7. **TCL load order**: `parser_utils.tcl` loads LAST in builder.tcl (references other parser functions).
8. **Indexer off by default**: Background indexing causes UI lag. Must explicitly enable via `config.indexer.enabled`.

## Key Patterns

**Feature module** (`features/*.lua`): `M.setup()` creates user command + FileType autocmd with buffer-local keymap. `M.handle_<action>(bufnr, line, col)` delegates to analyzer. Features are client-side (user commands operating on the AST directly), not LSP server request handlers. Pattern: setup → autocmd → keymap → handle → analyzer → cache → parser.

**AST traversal** (`analyzer/*.lua`): Recursive `visit_node(node, results, filepath, namespace, depth)` with depth guard. MUST recurse into BOTH `node.children` AND `node.body.children` (procs store body separately).

**TCL module** (`tcl/core/ast/*.tcl`): Namespaces `::ast::`, `::ast::parsers::`, `::ast::json::`, `::ast::utils::`. Each self-contained, <200 lines, self-tests via `if {[info script] eq $argv0}`.

## Commands

```bash
make test            # All tests (Lua + TCL)
make test-unit       # Unit tests only
make lint            # All linting
make format-lua      # Format with stylua
```

Single test: `nvim --headless -u tests/minimal_init.lua -c "lua require('plenary.test_harness').test_directory('tests/lua/', {minimal_init='tests/minimal_init.lua', filter='<name>'})" -c "qa!"`
TCL test: `tclsh tests/tcl/core/ast/test_<module>.tcl`

## More Info

- Workflow, beads, session protocols: `DEVELOPMENT.md`
- Design docs: `docs/plans/`
- Lua conventions: `.claude/rules/lua-conventions.md`
- TCL conventions: `.claude/rules/tcl-conventions.md`

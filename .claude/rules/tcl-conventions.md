# TCL Coding Conventions

## Namespace Structure

- Use `::ast::` namespace for public AST functions
- Use `::ast::parsers::` for parser-specific functions
- Use `::ast::json::` for JSON serialization
- Use `::ast::utils::` for utilities

## Module Pattern

Each TCL module should:
1. Be self-contained and independently testable
2. Include self-tests runnable via `tclsh module.tcl` (guarded by `if {[info script] eq $argv0}`)
3. Stay under 200 lines
4. Load dependencies explicitly at the top using `source`

## Module Loading

`builder.tcl` is the orchestrator that loads all modules in dependency order:

```tcl
# Get script directory for loading modules
set script_dir [file dirname [file normalize [info script]]]

# Load modules with error handling
foreach module {utils delimiters comments commands json folding} {
    if {[catch {source [file join $script_dir ${module}.tcl]} err]} {
        puts stderr "Error loading ${module}.tcl: $err"
        exit 1
    }
}
```

**Load order matters:** `parser_utils.tcl` must load AFTER all parser modules because it references their functions.

## AST Node Structure

Every AST node is a dict with at minimum:
- `type` — node type string (e.g., `"proc"`, `"set"`, `"namespace_eval"`, `"command"`)
- `range` — position dict from `::ast::utils::make_range`

Root node has: `type "root"`, `filepath`, `comments`, `children`, `had_error`, `errors`

Proc nodes have: `name`, `params`, `body` (which contains `children`)

Variable nodes: `var_name` can be a string OR a dict (for complex array access). Always type-check before using.

## Error Handling

- Use `catch` for error handling
- Return error dicts with `type "error"`, `message`, `range` keys
- Set `had_error` flag (0 or 1) in AST root when errors occur
- Use `info complete` to check for syntactically complete TCL before parsing

## Testing

- Every module has a corresponding test file in `tests/tcl/core/ast/`
- Tests use simple pass/fail output with checkmarks
- Run individual tests: `tclsh tests/tcl/core/ast/test_<module>.tcl`
- Run all tests: `tclsh tests/tcl/core/ast/run_all_tests.tcl`

## JSON Serialization

The JSON module (`ast/json.tcl`) handles TCL-to-JSON conversion with these considerations:
- `is_dict` checks for string-like characters (`\n`, `\t`, `\r`, `"`) to distinguish strings from dicts
- Empty lists serialize as `[]`, not `{}`
- Single-element lists need special handling
- Field name hints (via `list_fields` variable) guide list-vs-dict detection

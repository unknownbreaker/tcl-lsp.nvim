# TCL Coding Conventions

## Namespace Structure

- Use `::ast::` namespace for public AST functions
- Use `::ast::parsers::` for parser-specific functions
- Use `::ast::json::` for JSON serialization
- Use `::ast::utils::` for utilities

## Module Pattern

Each TCL module should:
1. Be self-contained and independently testable
2. Include self-tests runnable via `tclsh module.tcl`
3. Stay under 200 lines
4. Load dependencies explicitly at the top

## Testing

- Every module has a corresponding test file in `tests/tcl/core/ast/`
- Tests use simple pass/fail output with checkmarks
- Run individual tests: `tclsh tests/tcl/core/ast/test_<module>.tcl`
- Run all tests: `tclsh tests/tcl/core/ast/run_all_tests.tcl`

## Error Handling

- Use `catch` for error handling
- Return error dicts with `type`, `message`, `range` keys
- Set `had_error` flag in AST root when errors occur

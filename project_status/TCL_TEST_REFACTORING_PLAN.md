# TCL Test Suite Refactoring Plan

## ðŸŽ¯ Goal: Update Tests to Match New Parser Structure

**Current Issue:** Tests call `::ast::parsers::parse_*` but implementation uses sub-namespaces like `::ast::parsers::procedures::parse_proc`

**Solution:** Update all test files to use the correct namespace paths

---

## ðŸ“‹ Files to Refactor

### Parser Test Files (7 files)
1. `tests/tcl/core/ast/parsers/test_procedures.tcl`
2. `tests/tcl/core/ast/parsers/test_variables.tcl`
3. `tests/tcl/core/ast/parsers/test_control_flow.tcl`
4. `tests/tcl/core/ast/parsers/test_namespaces.tcl`
5. `tests/tcl/core/ast/parsers/test_packages.tcl`
6. `tests/tcl/core/ast/parsers/test_expressions.tcl`
7. `tests/tcl/core/ast/parsers/test_lists.tcl`

### Other Test Files (4 files)
8. `tests/tcl/core/ast/test_utils.tcl` - Fix line counting and offset-to-line format
9. `tests/tcl/core/ast/test_comments.tcl` - Add utils.tcl dependency
10. `tests/tcl/core/ast/test_commands.tcl` - Fix variable escaping
11. `tests/tcl/core/ast/integration/test_full_ast.tcl` - Fix variable escaping

---

## ðŸ”§ Namespace Mapping Reference

| Test File | Old Call | New Call |
|-----------|----------|----------|
| test_procedures.tcl | `::ast::parsers::parse_proc` | `::ast::parsers::procedures::parse_proc` |
| test_variables.tcl | `::ast::parsers::parse_variable` | `::ast::parsers::variables::parse_set` (and others) |
| test_control_flow.tcl | `::ast::parsers::parse_control_flow` | `::ast::parsers::control_flow::parse_if` (and others) |
| test_namespaces.tcl | `::ast::parsers::parse_namespace` | `::ast::parsers::namespaces::parse_namespace` |
| test_packages.tcl | `::ast::parsers::parse_package` | `::ast::parsers::packages::parse_package` |
| test_expressions.tcl | `::ast::parsers::parse_expr` | `::ast::parsers::expressions::parse_expr` |
| test_lists.tcl | `::ast::parsers::parse_list` | `::ast::parsers::lists::parse_list` |

---

## ðŸŽ¯ Implementation Order

### Phase 1: Core Module Fixes (30 minutes) ðŸŸ¢
**Files:** test_utils.tcl, test_comments.tcl, test_commands.tcl, test_full_ast.tcl

**Expected:** 4/12 test suites passing

---

### Phase 2: Simple Parser Updates (1 hour) ðŸŸ¡
**Files:** test_namespaces.tcl, test_packages.tcl, test_expressions.tcl, test_procedures.tcl

**Expected:** 8/12 test suites passing

---

### Phase 3: Complex Parser Updates (1 hour) ðŸŸ¡
**Files:** test_variables.tcl, test_control_flow.tcl, test_lists.tcl

**Expected:** 11/12 test suites passing

---

### Phase 4: JSON Tests (30 minutes) ðŸŸ¢
**Files:** test_json.tcl

**Expected:** 12/12 test suites passing (100%) ðŸŽ¯

---

## ðŸ“Š Expected Progress

| Phase | Files Fixed | Test Suites Passing | Time |
|-------|-------------|---------------------|------|
| Start | 0 | 0/12 (0%) | - |
| Phase 1 | 4 | 4/12 (33%) | 30 min |
| Phase 2 | 8 | 8/12 (67%) | 1 hr |
| Phase 3 | 11 | 11/12 (92%) | 1 hr |
| Phase 4 | 12 | 12/12 (100%) ðŸŽ¯ | 30 min |
| **Total** | **12** | **12/12 (100%)** | **~3 hrs** |

---

## ðŸš€ Ready to Start!

This refactoring will:
1. âœ… Make tests match the actual implementation
2. âœ… Fix all "invalid command name" errors  
3. âœ… Get all 12 TCL test suites passing
4. âœ… Establish solid foundation for future tests

**Estimated Total Time:** 3 hours  
**Expected Result:** 12/12 test suites passing (100%) ðŸŽ¯

---

**Next Step:** Start with Phase 1 (Core Module Fixes)

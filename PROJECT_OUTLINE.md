# TCL LSP for Neovim - Project Structure & Development Progress

**Last Updated:** October 22, 2025  
**Repository:** https://github.com/unknownbreaker/tcl-lsp.nvim  
**Current Version:** 0.1.0-dev

---

## Executive Summary

The TCL LSP for Neovim project is in **Phase 1** of development, with foundational infrastructure being built following Test-Driven Development (TDD) principles. The project aims to create a full-featured Language Server Protocol implementation for TCL and RVT (Rivet template) files in Neovim.

### Current Status
- **Phase:** Phase 1 - Core Infrastructure (In Progress)
- **Test Coverage:** 70/76 unit tests passing (92.1%)
- **Files:** ~1,280 lines across modular TCL parser and ~700 lines of Lua LSP infrastructure
- **Architecture:** Modular, test-first approach with clear separation of concerns

---

## Project Architecture

```
tcl-lsp.nvim/
├── .github/                          # GitHub workflows and templates
│   ├── workflows/
│   │   ├── ci.yml                   # CI/CD pipeline
│   │   ├── release.yml              # Release automation
│   │   └── docs.yml                 # Documentation generation
│   └── ISSUE_TEMPLATE/              # Bug reports and feature requests
│
├── lua/tcl-lsp/                     # Neovim Lua plugin
│   ├── init.lua                     # ✅ Main plugin entry (implemented)
│   ├── config.lua                   # ✅ Configuration management (implemented)
│   ├── server.lua                   # ✅ LSP server wrapper (implemented)
│   ├── parser/                      # 🚧 TCL parsing logic (in progress)
│   │   ├── init.lua
│   │   ├── ast.lua                  # AST building
│   │   ├── symbols.lua              # Symbol extraction
│   │   └── scope.lua                # Scope analysis
│   ├── analyzer/                    # ⏳ Symbol analysis (pending)
│   │   ├── workspace.lua            # Workspace scanning
│   │   ├── references.lua           # Reference finding
│   │   └── definitions.lua          # Definition resolution
│   ├── features/                    # ⏳ LSP features (pending)
│   │   ├── completion.lua           # Code completion
│   │   ├── hover.lua                # Hover information
│   │   ├── signature.lua            # Signature help
│   │   ├── diagnostics.lua          # Diagnostics
│   │   ├── formatting.lua           # Code formatting
│   │   ├── highlights.lua           # Document highlights
│   │   └── symbols.lua              # Document/workspace symbols
│   ├── actions/                     # ⏳ Code actions (pending)
│   │   ├── rename.lua               # Symbol renaming
│   │   ├── cleanup.lua              # Remove unused items
│   │   └── refactor.lua             # Refactoring actions
│   └── utils/                       # ⏳ Utilities (pending)
│       ├── cache.lua                # Caching system
│       ├── logger.lua               # Logging utilities
│       └── helpers.lua              # Common helpers
│
├── tcl/core/ast/                    # ✅ TCL AST Parser (modular architecture)
│   ├── builder.lua                  # ✅ Orchestrator (~200 lines)
│   ├── json.tcl                     # ✅ JSON serialization (~180 lines)
│   ├── utils.tcl                    # ✅ Position tracking (~120 lines)
│   ├── comments.tcl                 # ✅ Comment extraction (~70 lines)
│   ├── commands.tcl                 # ✅ Command extraction (~120 lines)
│   └── parsers/                     # ✅ Individual command parsers
│       ├── procedures.tcl           # ✅ Proc parsing (~110 lines)
│       ├── variables.tcl            # ✅ Variable parsing (~100 lines)
│       ├── control_flow.tcl         # ✅ If/while/for/foreach/switch (~150 lines)
│       ├── namespaces.tcl           # ✅ Namespace operations (~65 lines)
│       ├── packages.tcl             # ✅ Package require/provide (~60 lines)
│       ├── expressions.tcl          # ✅ Expr commands (~40 lines)
│       └── lists.tcl                # ✅ List operations (~65 lines)
│
├── tests/                           # ✅ Comprehensive test suite
│   ├── lua/                         # Unit tests for Lua modules
│   │   ├── init_spec.lua           # ✅ Plugin entry tests
│   │   ├── config_spec.lua         # ✅ Configuration tests
│   │   ├── server_spec.lua         # ✅ LSP server wrapper tests
│   │   ├── parser/                 # Parser tests (70/76 passing)
│   │   │   ├── ast_spec.lua       # ✅ AST building (34/39 passing)
│   │   │   ├── symbols_spec.lua   # Symbol extraction
│   │   │   ├── scope_spec.lua     # Scope analysis
│   │   │   └── command_substitution_spec.lua  # ✅ (8/10 passing)
│   │   ├── analyzer/              # ⏳ Analyzer tests (pending)
│   │   ├── features/              # ⏳ Feature tests (pending)
│   │   ├── actions/               # ⏳ Action tests (pending)
│   │   └── utils/                 # ⏳ Utility tests (pending)
│   ├── tcl/                        # TCL script tests
│   │   └── core/                  # Core functionality tests
│   ├── integration/                # Integration tests
│   │   └── lsp_server_spec.lua   # Full LSP server integration
│   ├── spec/                       # Test specifications
│   │   ├── test_helpers.lua      # ✅ Common test utilities
│   │   └── coverage_config.lua   # Code coverage configuration
│   └── minimal_init.lua            # ✅ Test environment setup
│
├── scripts/                         # Build and utility scripts
│   ├── prepare_release.sh
│   ├── install_deps.sh
│   └── generate_tcl_docs.tcl
│
├── docs/                            # Documentation
│   ├── api/                         # API documentation
│   ├── guides/                      # User guides
│   └── contributing/                # Contribution guidelines
│
├── Makefile                         # ✅ Build automation
├── package.json                     # ✅ Node.js dependencies (for testing)
├── README.md                        # ✅ Project overview
├── CHANGELOG.md                     # Version history
├── LICENSE                          # MIT License
├── CONTRIBUTING.md                  # ✅ Contribution guidelines
└── environment_setup.sh             # ✅ Environment setup script
```

**Legend:**
- ✅ Implemented and tested
- 🚧 In progress / partially implemented
- ⏳ Planned / not yet started

---

## Development Phases Progress

### Phase 1: Core Infrastructure (Weeks 1-2) - **IN PROGRESS** 🚧

**Status:** 70% Complete

#### ✅ Completed Items:
1. **Basic Neovim Plugin Structure**
   - ✅ `lua/tcl-lsp/init.lua` - Main plugin entry with version tracking
   - ✅ `lua/tcl-lsp/config.lua` - Configuration system with validation
   - ✅ `lua/tcl-lsp/server.lua` - LSP server wrapper and lifecycle management
   - ✅ User commands: `:TclLspStart`, `:TclLspStop`, `:TclLspRestart`, `:TclLspStatus`
   - ✅ Autocommands for automatic LSP activation on `.tcl` and `.rvt` files

2. **Configuration System**
   - ✅ Default configuration with sensible defaults
   - ✅ User config merging with deep extend
   - ✅ Buffer-local overrides support
   - ✅ Input validation with clear error messages
   - ✅ Edge case handling (circular references, large configs, special characters)
   - ✅ Configuration utilities (reset, update, export/import)
   - ✅ Root directory detection with multiple markers

3. **TCL Parser Architecture**
   - ✅ Modular parser with ~1,280 lines across 12 files
   - ✅ Core modules: builder, JSON, utils, comments, commands
   - ✅ Parser modules: procedures, variables, control flow, namespaces, packages, expressions, lists
   - ✅ JSON serialization working (all tests passing)
   - ✅ Position tracking for all nodes
   - ✅ Command extraction and parsing

4. **Test Infrastructure**
   - ✅ Unit test framework with Plenary.nvim
   - ✅ Test helpers and utilities
   - ✅ Mock creation for vim, LSP, config, logger
   - ✅ File system utilities for test projects
   - ✅ 70/76 tests passing (92.1% pass rate)

#### 🚧 In Progress:
1. **LSP Server Communication**
   - 🚧 Tclsh process spawning (basic implementation complete)
   - ⏳ JSON-RPC message handling (pending)
   - ⏳ Request/response protocol (pending)
   - ⏳ Error recovery mechanisms (pending)

2. **Parser Improvements**
   - 🚧 Command substitution handling (8/10 tests passing)
   - 🚧 Complex AST structures (34/39 tests passing)
   - ⏳ Nested command handling (needs improvement)
   - ⏳ Variable interpolation in strings

#### ⏳ Pending:
1. Logging and error handling system
2. Performance optimization and caching
3. Integration tests for server lifecycle

---

### Phase 2: Parsing Engine (Weeks 3-4) - **PLANNED** ⏳

**Status:** Not Started

#### Planned Features:
- [ ] Complete TCL AST parser using tclsh
- [ ] Symbol identification (procs, namespaces, variables, packages)
- [ ] Scope analysis and resolution
- [ ] Workspace file scanning and indexing
- [ ] Cross-file reference tracking
- [ ] Caching system for performance

**Dependencies:** Phase 1 completion (LSP server communication)

---

### Phase 3: Essential LSP Features (Weeks 5-8) - **PLANNED** ⏳

**Status:** Not Started

#### Planned Core Features:
- [ ] **Go to Definition** (same file → cross-file → packages/namespaces)
- [ ] **Go to References** (workspace-wide search)
- [ ] **Code Completion** (procs, variables, packages, namespaces, built-ins)
- [ ] **Hover Information** (proc signatures, variable info, documentation)
- [ ] **Diagnostics** (syntax errors, undefined variables, unreachable code)
- [ ] **Document Symbols** (outline view)

**Dependencies:** Phase 2 completion (parsing engine)

---

### Phase 4: Code Actions & Advanced Features (Weeks 9-11) - **PLANNED** ⏳

**Status:** Not Started

#### Planned Productivity Features:
- [ ] **Symbol Renaming** (workspace-wide)
- [ ] **Code Actions** (remove unused variables/packages/procs)
- [ ] **Signature Help** (proc parameters, built-in command syntax)
- [ ] **Document Formatting** (indentation, brace placement, style)
- [ ] **Workspace Symbols** (global symbol search)
- [ ] **Document Highlights** (highlight symbol under cursor)

**Dependencies:** Phase 3 completion (essential LSP features)

---

### Phase 5: Polish & Performance (Weeks 12-14) - **PLANNED** ⏳

**Status:** Not Started

#### Planned Enhancement Features:
- [ ] **Code Lens** (reference counts, executable indicators)
- [ ] **Folding Ranges** (procs, namespaces, comments)
- [ ] **Inlay Hints** (variable types, parameter names)
- [ ] Performance optimization (incremental parsing, smart caching)
- [ ] Error handling improvements
- [ ] Comprehensive testing suite

**Dependencies:** Phase 4 completion

---

### Phase 6: Quality & Documentation (Weeks 15-16) - **PLANNED** ⏳

**Status:** Not Started

#### Planned Quality Assurance:
- [ ] Security scan compliance
- [ ] Performance benchmarking (<300ms response times)
- [ ] Documentation and examples
- [ ] User configuration options
- [ ] Plugin distribution setup (LuaRocks, vim-plug, packer.nvim)

**Dependencies:** Phase 5 completion

---

## Current Test Results

### Unit Tests Summary
```
Total Tests: 76
Passing: 70
Failing: 6
Pass Rate: 92.1%
```

### Test Breakdown by Module

#### ✅ Fully Passing Modules:
- **config_spec.lua** - Configuration management (all tests passing)
- **init_spec.lua** - Plugin initialization (all tests passing)
- **server_spec.lua** - LSP server wrapper (all tests passing)
- **test_helpers.lua** - Test utilities (all tests passing)

#### 🚧 Partially Passing Modules:
- **ast_spec.lua** - AST building (34/39 passing, 87.2%)
  - ✅ Basic command parsing
  - ✅ Procedure definitions
  - ✅ Variable assignments
  - ✅ Control flow structures
  - ✅ Namespace handling
  - ✅ Position tracking
  - ❌ Complex nested structures (5 tests)

- **command_substitution_spec.lua** - Command substitution (8/10 passing, 80%)
  - ✅ Simple command substitution
  - ✅ Nested command substitution
  - ✅ Multiple substitutions
  - ❌ Edge cases with special characters (2 tests)

#### ⏳ Not Yet Implemented:
- symbols_spec.lua (pending)
- scope_spec.lua (pending)
- analyzer/* (pending)
- features/* (pending)
- actions/* (pending)

---

## Technical Implementation Notes

### Modular Parser Architecture

The TCL parser has been refactored into a highly modular structure:

**Benefits:**
1. **Bug Isolation** - Issues are confined to specific modules
2. **Targeted Testing** - Test individual parsers independently
3. **Parallel Development** - Multiple developers can work without conflicts
4. **Easy Debugging** - Module structure reveals exactly where to look
5. **Incremental Enhancement** - Add new parsers without touching existing code

**File Size Comparison:**
- **Before:** 800 lines in 1 monolithic file
- **After:** 1,280 lines across 12 focused modules (avg 107 lines per file)

### RVT (Rivet Template) Support Architecture

**Planned Implementation:**

1. **librivetparser.so Integration:**
   - Official Apache Rivet parser library for accurate RVT template parsing
   - Graceful fallback to pure Tcl parser when library unavailable
   - Cross-platform binary distribution (Linux, macOS, Windows)
   - Automatic installation and configuration

2. **Mixed Content Analysis:**
   - HTML structure parsing and validation
   - TCL code block extraction and analysis using tclsh
   - Template variable scope tracking across boundaries
   - Context-aware completions for HTML, TCL, and Rivet commands

### Performance Considerations

**Planned Optimizations:**
- **Incremental Parsing** - Only re-parse changed files
- **Smart Caching** - Cache parsed results with file modification tracking
- **Background Processing** - Workspace scanning in separate process
- **Lazy Loading** - Load symbols on-demand for large projects
- **Target**: <300ms response times for all LSP operations

### TCL-Specific Challenges

**Addressed:**
- ✅ Dynamic command parsing
- ✅ Procedure definitions with parameters
- ✅ Variable scoping (local, global, upvar)
- ✅ Control flow structures
- ✅ Namespace operations
- ✅ Package management

**To Be Addressed:**
- ⏳ Runtime variable creation and modification
- ⏳ Package system (`pkgIndex.tcl` parsing)
- ⏳ Complex namespace resolution and inheritance
- ⏳ Dynamic file inclusion via `source` command
- ⏳ `eval` and dynamic code execution

---

## Success Metrics

### Original Requirements Progress

| Requirement | Status | Progress |
|------------|--------|----------|
| Go to definition (procs, packages, namespaces, variables) | ⏳ | 0% |
| Go to references (workspace-wide) | ⏳ | 0% |
| Symbol outline | ⏳ | 0% |
| Code actions (rename, cleanup unused items) | ⏳ | 0% |
| Performance (<300ms response times) | ⏳ | 0% |
| Security scan compliance | ⏳ | 0% |

### New Essential Features Progress

| Feature | Status | Progress |
|---------|--------|----------|
| **Code Completion** | ⏳ | 0% |
| - Proc names with signatures | ⏳ | 0% |
| - Variable names with scope awareness | ⏳ | 0% |
| - Package names with auto-import | ⏳ | 0% |
| - Namespace completion | ⏳ | 0% |
| - Built-in Tcl commands | ⏳ | 0% |
| **Hover Information** | ⏳ | 0% |
| - Proc signatures and documentation | ⏳ | 0% |
| - Variable type and scope info | ⏳ | 0% |
| - Package descriptions | ⏳ | 0% |
| - Namespace information | ⏳ | 0% |
| **Signature Help** | ⏳ | 0% |
| - Real-time parameter information | ⏳ | 0% |
| - Parameter highlighting | ⏳ | 0% |
| - Overload navigation | ⏳ | 0% |
| **Diagnostics** | ⏳ | 0% |
| - Syntax error detection | ⏳ | 0% |
| - Undefined variable warnings | ⏳ | 0% |
| - Unreachable code detection | ⏳ | 0% |
| - Style/convention hints | ⏳ | 0% |
| **Document Formatting** | ⏳ | 0% |
| - Consistent indentation | ⏳ | 0% |
| - Brace placement standardization | ⏳ | 0% |
| - Line length management | ⏳ | 0% |

### Advanced Features Progress

| Feature | Status | Progress |
|---------|--------|----------|
| Document Highlights | ⏳ | 0% |
| Workspace Symbols | ⏳ | 0% |
| Code Lens | ⏳ | 0% |
| Folding Ranges | ⏳ | 0% |
| Inlay Hints | ⏳ | 0% |

---

## Development Workflow

### Test-Driven Development (TDD) Approach

The project follows strict TDD principles:

**For Each Function:**
1. ✅ Write Documentation First - Define function signature, parameters, return values
2. ✅ Write Tests - Create comprehensive test cases including edge cases
3. ✅ Favor Real Modules Over Mocks - Use actual APIs when possible
4. ✅ Implement Function - Write the actual implementation
5. ✅ Verify Coverage - Ensure all tests pass and coverage >90%
6. ✅ Fix Implementation First - Prioritize fixing implementation over changing tests
7. ⏳ Generate Docs - Auto-generate API documentation from comments

**For Each File:**
1. ✅ Keep Files Reasonably Sized - Max 700 lines per file
2. ✅ Refactor When Breaking Up Large Modules - Update dependencies
3. ✅ Refactor Tests Accordingly - Match test files to implementation structure

---

## Next Steps (Immediate Priorities)

### Week of October 22, 2025

1. **Complete Phase 1 (Priority: High)**
   - [ ] Fix remaining 6 failing parser tests
   - [ ] Implement JSON-RPC message handling
   - [ ] Add comprehensive logging system
   - [ ] Complete integration tests for server lifecycle

2. **Begin Phase 2 Planning (Priority: Medium)**
   - [ ] Design symbol table data structure
   - [ ] Plan workspace indexing strategy
   - [ ] Create test fixtures for Phase 2

3. **Documentation (Priority: Low)**
   - [ ] Update README with current progress
   - [ ] Document parser architecture in detail
   - [ ] Create user installation guide

---

## Contributing

The project follows these coding standards:
- **Test-First Development** - All features must have tests before implementation
- **File Size Limit** - Maximum 700 lines per file
- **Code Coverage** - Maintain >90% test coverage
- **Performance Target** - <300ms response times for all LSP operations
- **Documentation** - LuaLS annotations for all Lua functions
- **Commit Messages** - Conventional commit format (feat:, fix:, docs:, test:, refactor:)

See [CONTRIBUTING.md](https://github.com/unknownbreaker/tcl-lsp.nvim/blob/main/CONTRIBUTING.md) for detailed guidelines.

---

## Resources

- **Repository:** https://github.com/unknownbreaker/tcl-lsp.nvim
- **Issue Tracker:** https://github.com/unknownbreaker/tcl-lsp.nvim/issues
- **CI/CD:** GitHub Actions (.github/workflows/ci.yml)
- **Test Coverage:** Generated automatically in CI pipeline

---

## Version History

### v0.1.0-dev (Current)
- Initial project structure
- Configuration system implementation
- LSP server wrapper implementation
- Modular TCL parser (70% test coverage)
- Test infrastructure with Plenary.nvim
- CI/CD pipeline with GitHub Actions

---

**Project Maintainer:** unknownbreaker  
**License:** MIT  
**Neovim Version Required:** 0.11.3+  
**TCL Version Supported:** 8.6+


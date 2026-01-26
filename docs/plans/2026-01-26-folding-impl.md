# Code Folding Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement AST-based code folding for TCL/RVT files.

**Architecture:** TCL module extracts fold ranges from AST via recursive traversal. Lua handler calls TCL parser, transforms output to LSP FoldingRange format. Features integrate via existing plugin patterns.

**Tech Stack:** TCL 8.6 (parsing), Lua/Neovim (LSP handler), plenary.nvim (testing)

---

## Task 1: TCL Folding Module - Core Structure

**Files:**
- Create: `tcl/core/ast/folding.tcl`
- Test: `tests/tcl/core/ast/test_folding.tcl`

**Step 1: Write the failing test**

Create `tests/tcl/core/ast/test_folding.tcl`:

```tcl
#!/usr/bin/env tclsh
# tests/tcl/core/ast/test_folding.tcl
# Tests for folding range extraction

set script_dir [file dirname [file normalize [info script]]]
set ast_dir [file join [file dirname [file dirname [file dirname [file dirname $script_dir]]]] tcl core ast]
source [file join $ast_dir builder.tcl]
source [file join $ast_dir folding.tcl]

# Test counter
set total_tests 0
set passed_tests 0
set failed_tests 0

# Test helper
proc test {name script expected} {
    global total_tests passed_tests failed_tests
    incr total_tests

    if {[catch {uplevel 1 $script} result]} {
        puts "✗ FAIL: $name"
        puts "  Error: $result"
        incr failed_tests
        return 0
    }

    if {$result eq $expected} {
        puts "✓ PASS: $name"
        incr passed_tests
        return 1
    } else {
        puts "✗ FAIL: $name"
        puts "  Expected: $expected"
        puts "  Got: $result"
        incr failed_tests
        return 0
    }
}

# Test helper for list length
proc test_count {name script expected_count} {
    global total_tests passed_tests failed_tests
    incr total_tests

    if {[catch {uplevel 1 $script} result]} {
        puts "✗ FAIL: $name"
        puts "  Error: $result"
        incr failed_tests
        return 0
    }

    set count [llength $result]
    if {$count == $expected_count} {
        puts "✓ PASS: $name"
        incr passed_tests
        return 1
    } else {
        puts "✗ FAIL: $name"
        puts "  Expected count: $expected_count"
        puts "  Got count: $count"
        puts "  Result: $result"
        incr failed_tests
        return 0
    }
}

puts "========================================="
puts "Folding Module Test Suite"
puts "========================================="
puts ""

# Group 1: Basic proc folding
puts "Group 1: Procedure Folding"
puts "-----------------------------------------"

test_count "Single proc - one fold range" {
    set code {proc foo {args} {
    puts "hello"
    puts "world"
}}
    set ast [::ast::build $code]
    ::ast::folding::extract_ranges $ast
} 1

test_count "Single-line proc - no fold" {
    set code {proc foo {} { return 1 }}
    set ast [::ast::build $code]
    ::ast::folding::extract_ranges $ast
} 0

puts ""

# Summary
puts "========================================="
puts "Results: $passed_tests/$total_tests passed"
if {$failed_tests > 0} {
    puts "FAILED: $failed_tests tests"
    exit 1
} else {
    puts "All tests passed!"
    exit 0
}
```

**Step 2: Run test to verify it fails**

Run: `tclsh tests/tcl/core/ast/test_folding.tcl`
Expected: FAIL with "can't read "::ast::folding::...": no such variable" or similar

**Step 3: Write minimal implementation**

Create `tcl/core/ast/folding.tcl`:

```tcl
#!/usr/bin/env tclsh
# tcl/core/ast/folding.tcl
# Folding Range Extraction Module
#
# Extracts code folding ranges from AST for LSP foldingRange requests.

namespace eval ::ast::folding {}

# Extract folding ranges from AST
#
# Args:
#   ast - The parsed AST dict
#
# Returns:
#   List of range dicts with keys: startLine, endLine, kind
#
proc ::ast::folding::extract_ranges {ast} {
    set ranges [list]

    if {![dict exists $ast children]} {
        return $ranges
    }

    foreach child [dict get $ast children] {
        set child_ranges [::ast::folding::extract_from_node $child]
        lappend ranges {*}$child_ranges
    }

    return $ranges
}

# Extract folding range from a single AST node (recursive)
#
# Args:
#   node - An AST node dict
#
# Returns:
#   List of range dicts
#
proc ::ast::folding::extract_from_node {node} {
    set ranges [list]

    if {![dict exists $node type]} {
        return $ranges
    }

    set node_type [dict get $node type]

    # Check if this node type is foldable
    if {[::ast::folding::is_foldable $node_type]} {
        set range [::ast::folding::make_range $node]
        if {$range ne ""} {
            lappend ranges $range
        }
    }

    # Recurse into children
    if {[dict exists $node children]} {
        foreach child [dict get $node children] {
            set child_ranges [::ast::folding::extract_from_node $child]
            lappend ranges {*}$child_ranges
        }
    }

    # Recurse into body (for procs, etc.)
    if {[dict exists $node body]} {
        set body [dict get $node body]
        if {[dict exists $body children]} {
            foreach child [dict get $body children] {
                set child_ranges [::ast::folding::extract_from_node $child]
                lappend ranges {*}$child_ranges
            }
        }
    }

    return $ranges
}

# Check if a node type is foldable
proc ::ast::folding::is_foldable {node_type} {
    set foldable_types {
        proc_definition
    }
    return [expr {$node_type in $foldable_types}]
}

# Create a folding range dict from a node
# Returns empty string if node spans only one line
proc ::ast::folding::make_range {node} {
    if {![dict exists $node range]} {
        return ""
    }

    set range [dict get $node range]

    # Get start and end lines
    set start_line 1
    set end_line 1

    if {[dict exists $range start line]} {
        set start_line [dict get $range start line]
    } elseif {[dict exists $range start_line]} {
        set start_line [dict get $range start_line]
    }

    if {[dict exists $range end_pos line]} {
        set end_line [dict get $range end_pos line]
    } elseif {[dict exists $range end line]} {
        set end_line [dict get $range end line]
    } elseif {[dict exists $range end_line]} {
        set end_line [dict get $range end_line]
    }

    # Skip single-line constructs
    if {$end_line <= $start_line} {
        return ""
    }

    # LSP uses 0-indexed lines
    return [dict create \
        startLine [expr {$start_line - 1}] \
        endLine [expr {$end_line - 1}] \
        kind "region"]
}
```

**Step 4: Run test to verify it passes**

Run: `tclsh tests/tcl/core/ast/test_folding.tcl`
Expected: PASS

**Step 5: Commit**

```bash
git add tcl/core/ast/folding.tcl tests/tcl/core/ast/test_folding.tcl
git commit -m "feat(folding): add TCL folding module with proc support"
```

---

## Task 2: TCL Folding - Control Flow Support

**Files:**
- Modify: `tcl/core/ast/folding.tcl`
- Modify: `tests/tcl/core/ast/test_folding.tcl`

**Step 1: Add failing tests for control flow**

Add to `tests/tcl/core/ast/test_folding.tcl` before the summary:

```tcl
# Group 2: Control flow folding
puts "Group 2: Control Flow Folding"
puts "-----------------------------------------"

test_count "If statement - one fold" {
    set code {if {$x > 0} {
    puts "positive"
    puts "number"
}}
    set ast [::ast::build $code]
    ::ast::folding::extract_ranges $ast
} 1

test_count "If-else - two folds" {
    set code {if {$x > 0} {
    puts "positive"
} else {
    puts "not positive"
}}
    set ast [::ast::build $code]
    ::ast::folding::extract_ranges $ast
} 2

test_count "Foreach loop - one fold" {
    set code {foreach item $list {
    puts $item
    process $item
}}
    set ast [::ast::build $code]
    ::ast::folding::extract_ranges $ast
} 1

test_count "While loop - one fold" {
    set code {while {$i < 10} {
    puts $i
    incr i
}}
    set ast [::ast::build $code]
    ::ast::folding::extract_ranges $ast
} 1

test_count "Switch statement - one fold" {
    set code {switch $value {
    a { puts "alpha" }
    b { puts "beta" }
}}
    set ast [::ast::build $code]
    ::ast::folding::extract_ranges $ast
} 1

puts ""
```

**Step 2: Run tests to verify they fail**

Run: `tclsh tests/tcl/core/ast/test_folding.tcl`
Expected: FAIL for control flow tests

**Step 3: Add control flow types to is_foldable**

Update `tcl/core/ast/folding.tcl` `is_foldable` proc:

```tcl
# Check if a node type is foldable
proc ::ast::folding::is_foldable {node_type} {
    set foldable_types {
        proc_definition
        if_statement
        elseif_branch
        else_branch
        foreach_statement
        for_statement
        while_statement
        switch_statement
    }
    return [expr {$node_type in $foldable_types}]
}
```

Also update `extract_from_node` to handle elseif_branches and else_branch:

```tcl
proc ::ast::folding::extract_from_node {node} {
    set ranges [list]

    if {![dict exists $node type]} {
        return $ranges
    }

    set node_type [dict get $node type]

    # Check if this node type is foldable
    if {[::ast::folding::is_foldable $node_type]} {
        set range [::ast::folding::make_range $node]
        if {$range ne ""} {
            lappend ranges $range
        }
    }

    # Recurse into children
    if {[dict exists $node children]} {
        foreach child [dict get $node children] {
            set child_ranges [::ast::folding::extract_from_node $child]
            lappend ranges {*}$child_ranges
        }
    }

    # Recurse into body (for procs, loops, etc.)
    if {[dict exists $node body]} {
        set body [dict get $node body]
        if {[dict exists $body children]} {
            foreach child [dict get $body children] {
                set child_ranges [::ast::folding::extract_from_node $child]
                lappend ranges {*}$child_ranges
            }
        }
    }

    # Recurse into elseif_branches
    if {[dict exists $node elseif_branches]} {
        foreach branch [dict get $node elseif_branches] {
            set branch_ranges [::ast::folding::extract_from_node $branch]
            lappend ranges {*}$branch_ranges
        }
    }

    # Recurse into else_branch
    if {[dict exists $node else_branch]} {
        set else_branch [dict get $node else_branch]
        set else_ranges [::ast::folding::extract_from_node $else_branch]
        lappend ranges {*}$else_ranges
    }

    # Recurse into cases (for switch)
    if {[dict exists $node cases]} {
        foreach case [dict get $node cases] {
            set case_ranges [::ast::folding::extract_from_node $case]
            lappend ranges {*}$case_ranges
        }
    }

    return $ranges
}
```

**Step 4: Run tests to verify they pass**

Run: `tclsh tests/tcl/core/ast/test_folding.tcl`
Expected: PASS

**Step 5: Commit**

```bash
git add tcl/core/ast/folding.tcl tests/tcl/core/ast/test_folding.tcl
git commit -m "feat(folding): add control flow folding support"
```

---

## Task 3: TCL Folding - Namespace and TclOO Support

**Files:**
- Modify: `tcl/core/ast/folding.tcl`
- Modify: `tests/tcl/core/ast/test_folding.tcl`

**Step 1: Add failing tests**

Add to `tests/tcl/core/ast/test_folding.tcl`:

```tcl
# Group 3: Namespace and OO folding
puts "Group 3: Namespace and OO Folding"
puts "-----------------------------------------"

test_count "Namespace eval - one fold" {
    set code {namespace eval ::myns {
    variable x 1
    proc helper {} { return 1 }
}}
    set ast [::ast::build $code]
    ::ast::folding::extract_ranges $ast
} 2

test_count "Nested namespace - two folds" {
    set code {namespace eval ::outer {
    namespace eval ::inner {
        proc foo {} { return 1 }
    }
}}
    set ast [::ast::build $code]
    # outer ns + inner ns + proc = 3, but proc is single-line so 2
    ::ast::folding::extract_ranges $ast
} 2

puts ""
```

**Step 2: Run tests to verify they fail**

Run: `tclsh tests/tcl/core/ast/test_folding.tcl`
Expected: FAIL

**Step 3: Add namespace types**

Update `is_foldable` in `tcl/core/ast/folding.tcl`:

```tcl
proc ::ast::folding::is_foldable {node_type} {
    set foldable_types {
        proc_definition
        if_statement
        elseif_branch
        else_branch
        foreach_statement
        for_statement
        while_statement
        switch_statement
        namespace_eval
        oo_class
        oo_method
    }
    return [expr {$node_type in $foldable_types}]
}
```

**Step 4: Run tests to verify they pass**

Run: `tclsh tests/tcl/core/ast/test_folding.tcl`
Expected: PASS

**Step 5: Commit**

```bash
git add tcl/core/ast/folding.tcl tests/tcl/core/ast/test_folding.tcl
git commit -m "feat(folding): add namespace and TclOO folding support"
```

---

## Task 4: TCL Folding - Comment Block Support

**Files:**
- Modify: `tcl/core/ast/folding.tcl`
- Modify: `tests/tcl/core/ast/test_folding.tcl`

**Step 1: Add failing tests**

Add to `tests/tcl/core/ast/test_folding.tcl`:

```tcl
# Group 4: Comment folding
puts "Group 4: Comment Folding"
puts "-----------------------------------------"

test_count "Multi-line comment block" {
    set code {# This is a comment
# that spans multiple
# lines
proc foo {} { return 1 }}
    set ast [::ast::build $code]
    # Multi-line comment = 1 fold (proc is single-line)
    ::ast::folding::extract_ranges $ast
} 1

puts ""
```

**Step 2: Run tests to verify they fail**

Run: `tclsh tests/tcl/core/ast/test_folding.tcl`
Expected: FAIL

**Step 3: Add comment extraction**

The AST stores comments separately. Update `extract_ranges` in `tcl/core/ast/folding.tcl`:

```tcl
proc ::ast::folding::extract_ranges {ast} {
    set ranges [list]

    # Extract from comments (stored at root level)
    if {[dict exists $ast comments]} {
        set comment_ranges [::ast::folding::extract_comment_ranges [dict get $ast comments]]
        lappend ranges {*}$comment_ranges
    }

    # Extract from children
    if {[dict exists $ast children]} {
        foreach child [dict get $ast children] {
            set child_ranges [::ast::folding::extract_from_node $child]
            lappend ranges {*}$child_ranges
        }
    }

    return $ranges
}

# Extract folding ranges from consecutive comment lines
proc ::ast::folding::extract_comment_ranges {comments} {
    set ranges [list]

    if {[llength $comments] < 2} {
        return $ranges
    }

    # Group consecutive comments
    set groups [list]
    set current_group [list]
    set last_line -1

    foreach comment $comments {
        if {![dict exists $comment range]} {
            continue
        }

        set range [dict get $comment range]
        set line 1

        if {[dict exists $range start line]} {
            set line [dict get $range start line]
        } elseif {[dict exists $range start_line]} {
            set line [dict get $range start_line]
        }

        if {$last_line == -1 || $line == $last_line + 1} {
            lappend current_group $comment
        } else {
            if {[llength $current_group] >= 2} {
                lappend groups $current_group
            }
            set current_group [list $comment]
        }

        set last_line $line
    }

    # Don't forget last group
    if {[llength $current_group] >= 2} {
        lappend groups $current_group
    }

    # Create ranges from groups
    foreach group $groups {
        set first [lindex $group 0]
        set last [lindex $group end]

        set first_range [dict get $first range]
        set last_range [dict get $last range]

        set start_line 1
        set end_line 1

        if {[dict exists $first_range start line]} {
            set start_line [dict get $first_range start line]
        } elseif {[dict exists $first_range start_line]} {
            set start_line [dict get $first_range start_line]
        }

        if {[dict exists $last_range start line]} {
            set end_line [dict get $last_range start line]
        } elseif {[dict exists $last_range start_line]} {
            set end_line [dict get $last_range start_line]
        }

        lappend ranges [dict create \
            startLine [expr {$start_line - 1}] \
            endLine [expr {$end_line - 1}] \
            kind "comment"]
    }

    return $ranges
}
```

**Step 4: Run tests to verify they pass**

Run: `tclsh tests/tcl/core/ast/test_folding.tcl`
Expected: PASS

**Step 5: Commit**

```bash
git add tcl/core/ast/folding.tcl tests/tcl/core/ast/test_folding.tcl
git commit -m "feat(folding): add comment block folding support"
```

---

## Task 5: Load Folding Module in Builder

**Files:**
- Modify: `tcl/core/ast/builder.tcl`

**Step 1: Verify module loads correctly**

Run: `tclsh tcl/core/ast/folding.tcl`
Expected: No errors (module loads cleanly)

**Step 2: Add folding module to builder.tcl**

Find the line in `tcl/core/ast/builder.tcl`:

```tcl
foreach module {utils delimiters comments commands json} {
```

Change to:

```tcl
foreach module {utils delimiters comments commands json folding} {
```

**Step 3: Verify builder still works**

Run: `make test-tcl` or `tclsh tests/tcl/core/ast/run_all_tests.tcl`
Expected: All tests pass

**Step 4: Commit**

```bash
git add tcl/core/ast/builder.tcl
git commit -m "chore: load folding module in AST builder"
```

---

## Task 6: Lua Folding Handler - Core Structure

**Files:**
- Create: `lua/tcl-lsp/features/folding.lua`
- Create: `tests/lua/features/folding_spec.lua`

**Step 1: Write the failing test**

Create `tests/lua/features/folding_spec.lua`:

```lua
-- tests/lua/features/folding_spec.lua
-- Tests for folding feature

local helpers = require "tests.spec.test_helpers"

describe("Folding Feature", function()
  local folding

  before_each(function()
    package.loaded["tcl-lsp.features.folding"] = nil
    folding = require("tcl-lsp.features.folding")
  end)

  describe("setup", function()
    it("should register without error", function()
      local success = pcall(folding.setup)
      assert.is_true(success)
    end)
  end)

  describe("get_folding_ranges", function()
    it("should return empty array for empty code", function()
      local ranges = folding.get_folding_ranges("")
      assert.is_table(ranges)
      assert.equals(0, #ranges)
    end)

    it("should return fold range for multi-line proc", function()
      local code = [[proc foo {args} {
    puts "hello"
    puts "world"
}]]
      local ranges = folding.get_folding_ranges(code)
      assert.is_table(ranges)
      assert.equals(1, #ranges)
      assert.equals(0, ranges[1].startLine)
      assert.equals(3, ranges[1].endLine)
      assert.equals("region", ranges[1].kind)
    end)

    it("should not fold single-line proc", function()
      local code = [[proc foo {} { return 1 }]]
      local ranges = folding.get_folding_ranges(code)
      assert.is_table(ranges)
      assert.equals(0, #ranges)
    end)
  end)
end)
```

**Step 2: Run test to verify it fails**

Run: `make test-unit` or specific test
Expected: FAIL with "module 'tcl-lsp.features.folding' not found"

**Step 3: Write minimal implementation**

Create `lua/tcl-lsp/features/folding.lua`:

```lua
-- lua/tcl-lsp/features/folding.lua
-- Code folding feature for TCL LSP

local M = {}

local parser = require "tcl-lsp.parser"

--- Get folding ranges from TCL code
---@param code string The TCL code
---@param filepath string|nil Optional filepath
---@return table[] Array of FoldingRange objects
function M.get_folding_ranges(code, filepath)
  if not code or code == "" then
    return {}
  end

  -- Parse the code to get AST
  local ast, err = parser.parse(code, filepath)
  if not ast then
    return {}
  end

  -- Extract fold ranges from AST
  return M.extract_ranges_from_ast(ast)
end

--- Extract folding ranges from AST
---@param ast table The parsed AST
---@return table[] Array of FoldingRange objects
function M.extract_ranges_from_ast(ast)
  local ranges = {}

  -- Extract from comments
  if ast.comments then
    local comment_ranges = M.extract_comment_ranges(ast.comments)
    for _, r in ipairs(comment_ranges) do
      table.insert(ranges, r)
    end
  end

  -- Extract from children
  if ast.children then
    for _, child in ipairs(ast.children) do
      M.extract_from_node(child, ranges)
    end
  end

  return ranges
end

--- Foldable node types
local FOLDABLE_TYPES = {
  proc_definition = true,
  if_statement = true,
  elseif_branch = true,
  else_branch = true,
  foreach_statement = true,
  for_statement = true,
  while_statement = true,
  switch_statement = true,
  namespace_eval = true,
  oo_class = true,
  oo_method = true,
}

--- Extract folding range from a node (recursive)
---@param node table AST node
---@param ranges table[] Accumulator for ranges
function M.extract_from_node(node, ranges)
  if not node or not node.type then
    return
  end

  -- Check if this node is foldable
  if FOLDABLE_TYPES[node.type] then
    local range = M.make_range(node)
    if range then
      table.insert(ranges, range)
    end
  end

  -- Recurse into children
  if node.children then
    for _, child in ipairs(node.children) do
      M.extract_from_node(child, ranges)
    end
  end

  -- Recurse into body
  if node.body and node.body.children then
    for _, child in ipairs(node.body.children) do
      M.extract_from_node(child, ranges)
    end
  end

  -- Recurse into elseif_branches
  if node.elseif_branches then
    for _, branch in ipairs(node.elseif_branches) do
      M.extract_from_node(branch, ranges)
    end
  end

  -- Recurse into else_branch
  if node.else_branch then
    M.extract_from_node(node.else_branch, ranges)
  end

  -- Recurse into cases
  if node.cases then
    for _, case in ipairs(node.cases) do
      M.extract_from_node(case, ranges)
    end
  end
end

--- Create a FoldingRange from a node
---@param node table AST node with range
---@return table|nil FoldingRange or nil if single-line
function M.make_range(node)
  if not node.range then
    return nil
  end

  local range = node.range
  local start_line, end_line

  -- Handle different range formats
  if range.start and range.start.line then
    start_line = range.start.line
  elseif range.start_line then
    start_line = range.start_line
  else
    return nil
  end

  if range.end_pos and range.end_pos.line then
    end_line = range.end_pos.line
  elseif range["end"] and range["end"].line then
    end_line = range["end"].line
  elseif range.end_line then
    end_line = range.end_line
  else
    return nil
  end

  -- Skip single-line constructs
  if end_line <= start_line then
    return nil
  end

  -- LSP uses 0-indexed lines
  return {
    startLine = start_line - 1,
    endLine = end_line - 1,
    kind = "region",
  }
end

--- Extract folding ranges from consecutive comments
---@param comments table[] Array of comment nodes
---@return table[] Array of FoldingRange objects
function M.extract_comment_ranges(comments)
  local ranges = {}

  if not comments or #comments < 2 then
    return ranges
  end

  -- Group consecutive comments
  local groups = {}
  local current_group = {}
  local last_line = -1

  for _, comment in ipairs(comments) do
    if not comment.range then
      goto continue
    end

    local line
    if comment.range.start and comment.range.start.line then
      line = comment.range.start.line
    elseif comment.range.start_line then
      line = comment.range.start_line
    else
      goto continue
    end

    if last_line == -1 or line == last_line + 1 then
      table.insert(current_group, { line = line })
    else
      if #current_group >= 2 then
        table.insert(groups, current_group)
      end
      current_group = { { line = line } }
    end

    last_line = line
    ::continue::
  end

  -- Don't forget last group
  if #current_group >= 2 then
    table.insert(groups, current_group)
  end

  -- Create ranges from groups
  for _, group in ipairs(groups) do
    local start_line = group[1].line
    local end_line = group[#group].line

    table.insert(ranges, {
      startLine = start_line - 1,
      endLine = end_line - 1,
      kind = "comment",
    })
  end

  return ranges
end

--- Set up folding feature
function M.setup()
  -- Nothing to set up for folding - it's requested by the editor
end

return M
```

**Step 4: Run test to verify it passes**

Run: `make test-unit`
Expected: PASS

**Step 5: Commit**

```bash
git add lua/tcl-lsp/features/folding.lua tests/lua/features/folding_spec.lua
git commit -m "feat(folding): add Lua folding handler"
```

---

## Task 7: Register Folding in Plugin

**Files:**
- Modify: `lua/tcl-lsp/init.lua`

**Step 1: Add require and setup call**

In `lua/tcl-lsp/init.lua`, add after line 11 (after highlights require):

```lua
local folding = require "tcl-lsp.features.folding"
```

And in the `M.setup()` function, after line 109 (after highlights.setup()):

```lua
  -- Set up folding feature
  folding.setup()
```

**Step 2: Add public API function**

Add before `return M`:

```lua
-- Get folding ranges for current buffer (for testing and API)
function M.get_folding_ranges(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local code = table.concat(lines, "\n")
  local folding_module = require "tcl-lsp.features.folding"
  return folding_module.get_folding_ranges(code)
end
```

**Step 3: Verify plugin loads**

Run: `make test-unit`
Expected: All tests pass

**Step 4: Commit**

```bash
git add lua/tcl-lsp/init.lua
git commit -m "feat: register folding feature in plugin"
```

---

## Task 8: Add Folding Tests to Test Suite Runner

**Files:**
- Modify: `tests/tcl/core/ast/run_all_tests.tcl`

**Step 1: Add folding test to runner**

In `tests/tcl/core/ast/run_all_tests.tcl`, add `test_folding.tcl` to the list of test files.

**Step 2: Run all TCL tests**

Run: `tclsh tests/tcl/core/ast/run_all_tests.tcl`
Expected: All tests pass including folding tests

**Step 3: Commit**

```bash
git add tests/tcl/core/ast/run_all_tests.tcl
git commit -m "test: add folding tests to TCL test runner"
```

---

## Task 9: Final Integration Test

**Files:**
- Test all components together

**Step 1: Run full test suite**

Run: `make test`
Expected: All tests pass

**Step 2: Manual verification**

Open Neovim with a TCL file and verify:
1. Plugin loads without errors
2. `require("tcl-lsp").get_folding_ranges()` returns ranges

**Step 3: Final commit**

```bash
git add -A
git commit -m "feat(folding): complete Phase 4 code folding implementation"
```

---

## Summary

| Task | Description | Files |
|------|-------------|-------|
| 1 | TCL folding module core | `tcl/core/ast/folding.tcl`, test |
| 2 | Control flow support | folding.tcl, test |
| 3 | Namespace/TclOO support | folding.tcl, test |
| 4 | Comment block support | folding.tcl, test |
| 5 | Load module in builder | builder.tcl |
| 6 | Lua handler | `lua/tcl-lsp/features/folding.lua`, test |
| 7 | Plugin registration | init.lua |
| 8 | Test runner update | run_all_tests.tcl |
| 9 | Final integration | verify all |

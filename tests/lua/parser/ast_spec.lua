-- tests/lua/parser/ast_spec.lua
-- AST Parser Tests - Phase 2 TDD Implementation
-- These tests define what the AST parser should do (RED phase)

local helpers = require "tests.spec.test_helpers"

describe("TCL AST Parser", function()
  local parser
  local temp_dir

  before_each(function()
    -- Clean package cache for fresh module loading
    package.loaded["tcl-lsp.parser"] = nil
    package.loaded["tcl-lsp.parser.ast"] = nil

    -- Create temporary directory for test files
    temp_dir = vim.fn.tempname()
    vim.fn.mkdir(temp_dir, "p")

    -- Load parser module (will fail initially - that's expected!)
    parser = require "tcl-lsp.parser.ast"
  end)

  after_each(function()
    -- Clean up temporary files
    if temp_dir then
      vim.fn.delete(temp_dir, "rf")
    end
  end)

  describe("Basic AST Construction", function()
    it("should parse empty TCL code", function()
      local code = ""
      local ast, err = parser.parse(code)

      assert.is_not_nil(ast, "Should return AST for empty code")
      assert.is_nil(err, "Should not return error for empty code")
      assert.is_table(ast, "AST should be a table")
      assert.equals("root", ast.type, "Root node should have type 'root'")
      assert.is_table(ast.children, "AST should have children array")
      assert.equals(0, #ast.children, "Empty code should have no children")
    end)

    it("should parse whitespace-only code", function()
      local code = "   \n\t  \n  "
      local ast, err = parser.parse(code)

      assert.is_not_nil(ast, "Should return AST for whitespace")
      assert.is_nil(err, "Should not return error for whitespace")
      assert.equals(0, #ast.children, "Whitespace should produce no nodes")
    end)

    it("should parse single comment", function()
      local code = "# This is a comment"
      local ast, err = parser.parse(code)

      assert.is_not_nil(ast, "Should parse comment")
      assert.is_nil(err, "Should not error on comment")
      -- Comments might be stored or ignored - verify structure exists
      assert.is_table(ast, "AST should be a table")
    end)
  end)

  describe("Procedure (proc) Parsing", function()
    it("should parse simple procedure with no arguments", function()
      local code = [[
proc hello {} {
    puts "Hello, World!"
}
]]
      local ast, err = parser.parse(code)

      assert.is_nil(err, "Should not error: " .. tostring(err))
      assert.is_not_nil(ast, "Should return AST")
      assert.equals(1, #ast.children, "Should have one proc node")

      local proc_node = ast.children[1]
      assert.equals("proc", proc_node.type, "Node should be proc type")
      assert.equals("hello", proc_node.name, "Proc name should be 'hello'")
      assert.is_table(proc_node.params, "Proc should have params array")
      assert.equals(0, #proc_node.params, "Should have no parameters")
      assert.is_table(proc_node.body, "Proc should have body")
      assert.is_not_nil(proc_node.range, "Should have position range")
    end)

    it("should parse procedure with arguments", function()
      local code = [[
proc greet {name age} {
    puts "Hello, $name! You are $age years old."
}
]]
      local ast, err = parser.parse(code)

      assert.is_nil(err, "Should not error: " .. tostring(err))
      assert.equals(1, #ast.children, "Should have one proc")

      local proc_node = ast.children[1]
      assert.equals("greet", proc_node.name)
      assert.equals(2, #proc_node.params, "Should have 2 parameters")
      assert.equals("name", proc_node.params[1].name)
      assert.equals("age", proc_node.params[2].name)
    end)

    it("should parse procedure with default argument values", function()
      local code = [[
proc calculate {x {y 10} {operation "add"}} {
    # procedure body
}
]]
      local ast, err = parser.parse(code)

      assert.is_nil(err, "Should parse default values")
      local proc_node = ast.children[1]
      assert.equals(3, #proc_node.params)

      -- First param: no default
      assert.equals("x", proc_node.params[1].name)
      assert.is_nil(proc_node.params[1].default)

      -- Second param: default value
      assert.equals("y", proc_node.params[2].name)
      assert.equals("10", proc_node.params[2].default)

      -- Third param: default value
      assert.equals("operation", proc_node.params[3].name)
      assert.equals("add", proc_node.params[3].default)
    end)

    it("should parse procedure with args (variable arguments)", function()
      local code = [[
proc varargs {first args} {
    puts "First: $first, Rest: $args"
}
]]
      local ast, err = parser.parse(code)

      assert.is_nil(err, "Should parse variable arguments")
      local proc_node = ast.children[1]
      assert.equals(2, #proc_node.params)
      assert.equals("first", proc_node.params[1].name)
      assert.equals("args", proc_node.params[2].name)
      assert.is_true(proc_node.params[2].is_varargs or false)
    end)

    it("should parse nested procedures", function()
      local code = [[
proc outer {} {
    proc inner {} {
        puts "Inner proc"
    }
    inner
}
]]
      local ast, err = parser.parse(code)

      assert.is_nil(err, "Should parse nested procs")
      assert.equals(1, #ast.children)

      local outer = ast.children[1]
      assert.equals("outer", outer.name)

      -- Check that inner proc is in the body
      assert.is_table(outer.body)
      assert.is_table(outer.body.children)
    end)
  end)

  describe("Variable Declarations", function()
    it("should parse simple variable set", function()
      local code = 'set myvar "value"'
      local ast, err = parser.parse(code)

      assert.is_nil(err, "Should not error")
      assert.equals(1, #ast.children)

      local set_node = ast.children[1]
      assert.equals("set", set_node.type)
      assert.equals("myvar", set_node.var_name)
      assert.equals('"value"', set_node.value)
    end)

    it("should parse variable set with expression", function()
      local code = "set x [expr {1 + 2}]"
      local ast, err = parser.parse(code)

      assert.is_nil(err, "Should parse expression")
      local set_node = ast.children[1]
      assert.equals("x", set_node.var_name)
      assert.is_table(set_node.value) -- Expression is a subtree
    end)

    it("should parse global variable declaration", function()
      local code = "global myvar"
      local ast, err = parser.parse(code)

      assert.is_nil(err, "Should parse global")
      local global_node = ast.children[1]
      assert.equals("global", global_node.type)
      assert.is_table(global_node.vars)
      assert.equals("myvar", global_node.vars[1])
    end)

    it("should parse upvar declaration", function()
      local code = "upvar 1 varname localname"
      local ast, err = parser.parse(code)

      assert.is_nil(err, "Should parse upvar")
      local upvar_node = ast.children[1]
      assert.equals("upvar", upvar_node.type)
      assert.equals("1", upvar_node.level)
      assert.equals("varname", upvar_node.other_var)
      assert.equals("localname", upvar_node.local_var)
    end)

    it("should parse array set", function()
      local code = "array set myarray {key1 val1 key2 val2}"
      local ast, err = parser.parse(code)

      assert.is_nil(err, "Should parse array set")
      local array_node = ast.children[1]
      assert.equals("array", array_node.type)
      assert.equals("myarray", array_node.array_name)
    end)
  end)

  describe("Control Flow Structures", function()
    it("should parse if statement", function()
      local code = [[
if {$x > 0} {
    puts "positive"
}
]]
      local ast, err = parser.parse(code)

      assert.is_nil(err, "Should parse if")
      local if_node = ast.children[1]
      assert.equals("if", if_node.type)
      assert.is_not_nil(if_node.condition)
      assert.is_not_nil(if_node.then_body)
    end)

    it("should parse if-else statement", function()
      local code = [[
if {$x > 0} {
    puts "positive"
} else {
    puts "not positive"
}
]]
      local ast, err = parser.parse(code)

      assert.is_nil(err, "Should parse if-else")
      local if_node = ast.children[1]
      assert.is_not_nil(if_node.else_body)
    end)

    it("should parse if-elseif-else chain", function()
      local code = [[
if {$x > 0} {
    puts "positive"
} elseif {$x < 0} {
    puts "negative"
} else {
    puts "zero"
}
]]
      local ast, err = parser.parse(code)

      assert.is_nil(err, "Should parse if-elseif-else")
      local if_node = ast.children[1]
      assert.is_table(if_node.elseif_branches)
      assert.equals(1, #if_node.elseif_branches)
    end)

    it("should parse while loop", function()
      local code = [[
while {$i < 10} {
    incr i
}
]]
      local ast, err = parser.parse(code)

      assert.is_nil(err, "Should parse while")
      local while_node = ast.children[1]
      assert.equals("while", while_node.type)
      assert.is_not_nil(while_node.condition)
      assert.is_not_nil(while_node.body)
    end)

    it("should parse for loop", function()
      local code = [[
for {set i 0} {$i < 10} {incr i} {
    puts $i
}
]]
      local ast, err = parser.parse(code)

      assert.is_nil(err, "Should parse for loop")
      local for_node = ast.children[1]
      assert.equals("for", for_node.type)
      assert.is_not_nil(for_node.init)
      assert.is_not_nil(for_node.condition)
      assert.is_not_nil(for_node.increment)
      assert.is_not_nil(for_node.body)
    end)

    it("should parse foreach loop", function()
      local code = [[
foreach item $list {
    puts $item
}
]]
      local ast, err = parser.parse(code)

      assert.is_nil(err, "Should parse foreach")
      local foreach_node = ast.children[1]
      assert.equals("foreach", foreach_node.type)
      assert.equals("item", foreach_node.var_name)
      assert.is_not_nil(foreach_node.list)
      assert.is_not_nil(foreach_node.body)
    end)

    it("should parse switch statement", function()
      local code = [[
switch $value {
    "a" { puts "A" }
    "b" { puts "B" }
    default { puts "Other" }
}
]]
      local ast, err = parser.parse(code)

      assert.is_nil(err, "Should parse switch")
      local switch_node = ast.children[1]
      assert.equals("switch", switch_node.type)
      assert.is_table(switch_node.cases)
      assert.is_true(#switch_node.cases >= 2)
    end)
  end)

  describe("Namespace Handling", function()
    it("should parse namespace declaration", function()
      local code = [[
namespace eval MyNamespace {
    variable x 10
    proc myproc {} {}
}
]]
      local ast, err = parser.parse(code)

      assert.is_nil(err, "Should parse namespace")
      local ns_node = ast.children[1]
      assert.equals("namespace_eval", ns_node.type)
      assert.equals("MyNamespace", ns_node.name)
      assert.is_table(ns_node.body)
    end)

    it("should parse namespace import", function()
      local code = "namespace import ::Other::*"
      local ast, err = parser.parse(code)

      assert.is_nil(err, "Should parse namespace import")
      local import_node = ast.children[1]
      assert.equals("namespace_import", import_node.type)
      assert.is_table(import_node.patterns)
    end)

    it("should parse namespace qualified names", function()
      local code = "::MyNamespace::myproc"
      local ast, err = parser.parse(code)

      assert.is_nil(err, "Should parse qualified name")
      -- The exact structure depends on implementation
      assert.is_not_nil(ast)
    end)
  end)

  describe("Position Tracking", function()
    it("should track line and column numbers", function()
      local code = [[
proc test {} {
    puts "hello"
}
]]
      local ast, err = parser.parse(code)

      assert.is_nil(err)
      local proc_node = ast.children[1]

      assert.is_not_nil(proc_node.range, "Should have range")
      assert.is_number(proc_node.range.start.line, "Should have start line")
      assert.is_number(proc_node.range.start.column, "Should have start column")
      assert.is_number(proc_node.range.end_pos.line, "Should have end line")
      assert.is_number(proc_node.range.end_pos.column, "Should have end column")
    end)

    it("should track positions for all nodes", function()
      local code = [[
set x 10
set y 20
proc add {} { expr {$x + $y} }
]]
      local ast, err = parser.parse(code)

      assert.is_nil(err)
      assert.equals(3, #ast.children)

      -- Each node should have position info
      for _, node in ipairs(ast.children) do
        assert.is_not_nil(node.range, "Each node should have range")
      end
    end)
  end)

  describe("Error Handling", function()
    it("should detect syntax errors", function()
      local code = "proc { { {" -- Unbalanced braces
      local ast, err = parser.parse(code)

      assert.is_nil(ast, "Should not return AST for invalid syntax")
      assert.is_not_nil(err, "Should return error")
      assert.is_string(err, "Error should be a string")
      assert.matches("syntax", err:lower(), "Error should mention syntax")
    end)

    it("should handle incomplete code", function()
      local code = "proc incomplete {x y}"
      local ast, err = parser.parse(code)

      assert.is_not_nil(err, "Should detect incomplete proc")
    end)

    it("should provide helpful error messages", function()
      local code = [[
proc test {
    # missing closing brace
]]
      local ast, err = parser.parse(code)

      assert.is_not_nil(err)
      assert.is_string(err)
      -- Error should contain useful information
      assert.is_true(#err > 10, "Error message should be descriptive")
    end)
  end)

  describe("Expression Parsing", function()
    it("should parse expr command", function()
      local code = "expr {1 + 2 * 3}"
      local ast, err = parser.parse(code)

      assert.is_nil(err, "Should parse expr")
      local expr_node = ast.children[1]
      assert.equals("expr", expr_node.type)
      assert.is_not_nil(expr_node.expression)
    end)

    it("should parse variable substitution", function()
      local code = 'puts "$myvar"'
      local ast, err = parser.parse(code)

      assert.is_nil(err, "Should parse variable substitution")
      local puts_node = ast.children[1]
      assert.is_not_nil(puts_node.args)
    end)

    it("should parse command substitution", function()
      local code = "set result [expr {1 + 1}]"
      local ast, err = parser.parse(code)

      assert.is_nil(err, "Should parse command substitution")
      local set_node = ast.children[1]
      assert.is_table(set_node.value)
    end)
  end)

  describe("List Operations", function()
    it("should parse list creation", function()
      local code = "list a b c"
      local ast, err = parser.parse(code)

      assert.is_nil(err, "Should parse list")
      local list_node = ast.children[1]
      assert.equals("list", list_node.type)
      assert.is_table(list_node.elements)
    end)

    it("should parse lappend", function()
      local code = "lappend mylist element"
      local ast, err = parser.parse(code)

      assert.is_nil(err, "Should parse lappend")
      local lappend_node = ast.children[1]
      assert.equals("lappend", lappend_node.type)
    end)
  end)

  describe("Package Handling", function()
    it("should parse package require", function()
      local code = "package require Tcl 8.6"
      local ast, err = parser.parse(code)

      assert.is_nil(err, "Should parse package require")
      local pkg_node = ast.children[1]
      assert.equals("package_require", pkg_node.type)
      assert.equals("Tcl", pkg_node.package_name)
      assert.equals("8.6", pkg_node.version)
    end)

    it("should parse package provide", function()
      local code = "package provide MyPackage 1.0"
      local ast, err = parser.parse(code)

      assert.is_nil(err, "Should parse package provide")
      local pkg_node = ast.children[1]
      assert.equals("package_provide", pkg_node.type)
    end)
  end)

  describe("File Path Handling", function()
    it("should parse from file", function()
      local test_file = temp_dir .. "/test.tcl"
      helpers.write_file(
        test_file,
        [[
proc fromfile {} {
    puts "From file"
}
]]
      )

      local ast, err = parser.parse_file(test_file)

      assert.is_nil(err, "Should parse from file")
      assert.is_not_nil(ast)
      assert.equals(1, #ast.children)
    end)

    it("should handle file read errors", function()
      local nonexistent = temp_dir .. "/nonexistent.tcl"
      local ast, err = parser.parse_file(nonexistent)

      assert.is_nil(ast)
      assert.is_not_nil(err)
      assert.matches("file", err:lower())
    end)
  end)

  describe("Complex Real-World Code", function()
    it("should parse complex procedure with multiple constructs", function()
      local code = [[
proc process_data {filename {options {}}} {
    global debug_mode

    if {![file exists $filename]} {
        error "File not found: $filename"
    }

    set fp [open $filename r]
    set data [read $fp]
    close $fp

    set results [list]
    foreach line [split $data "\n"] {
        if {[string length $line] > 0} {
            lappend results [string toupper $line]
        }
    }

    return $results
}
]]
      local ast, err = parser.parse(code)

      assert.is_nil(err, "Should parse complex procedure: " .. tostring(err))
      assert.is_not_nil(ast)
      assert.equals(1, #ast.children)

      local proc_node = ast.children[1]
      assert.equals("proc", proc_node.type)
      assert.equals("process_data", proc_node.name)
    end)

    it("should parse multiple procedures and variables", function()
      local code = [[
set VERSION "1.0"

proc init {} {
    global VERSION
    puts "Initializing version $VERSION"
}

proc cleanup {} {
    puts "Cleaning up"
}

init
]]
      local ast, err = parser.parse(code)

      assert.is_nil(err, "Should parse multiple definitions")
      assert.is_true(#ast.children >= 3, "Should have multiple top-level nodes")
    end)
  end)
end)

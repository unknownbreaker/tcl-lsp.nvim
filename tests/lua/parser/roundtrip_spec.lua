-- tests/lua/parser/roundtrip_spec.lua
-- Contract test: TCL parser → JSON → Lua → schema validation
-- Ensures the TCL parser output matches what the Lua schema expects.
-- If any test here fails, the TCL↔Lua boundary contract is broken.

describe("TCL↔Lua Roundtrip Contract", function()
  local parser
  local validator

  before_each(function()
    package.loaded["tcl-lsp.parser.ast"] = nil
    package.loaded["tcl-lsp.parser.validator"] = nil
    package.loaded["tcl-lsp.parser.schema"] = nil
    parser = require("tcl-lsp.parser.ast")
    validator = require("tcl-lsp.parser.validator")
  end)

  -- Helper: parse code and validate the full AST against schema
  local function assert_roundtrip(code, description)
    local ast, err = parser.parse(code)
    assert.is_nil(err, (description or "parse") .. " failed: " .. tostring(err))
    assert.is_not_nil(ast, (description or "parse") .. " returned nil AST")
    assert.equals("table", type(ast), "AST must be a table, got " .. type(ast))

    local result = validator.validate_ast(ast, { strict = true })
    if not result.valid then
      local msgs = {}
      for _, e in ipairs(result.errors) do
        table.insert(msgs, string.format("  [%s] %s", e.path or "?", e.message or "?"))
      end
      error(
        string.format(
          "%s: schema validation failed with %d error(s):\n%s",
          description or "roundtrip",
          #result.errors,
          table.concat(msgs, "\n")
        )
      )
    end

    return ast
  end

  describe("basic constructs", function()
    it("should validate a simple proc", function()
      assert_roundtrip([[
proc hello {} {
    puts "Hello, World!"
}
]], "simple proc")
    end)

    it("should validate a proc with parameters", function()
      assert_roundtrip([[
proc greet {name {greeting "Hello"}} {
    puts "$greeting, $name!"
}
]], "proc with params")
    end)

    it("should validate a proc with args (varargs)", function()
      assert_roundtrip([[
proc variadic {required args} {
    puts "$required $args"
}
]], "proc with args")
    end)

    it("should validate set (variable assignment)", function()
      assert_roundtrip([[
set x 10
set greeting "hello world"
]], "set variables")
    end)

    it("should validate puts", function()
      assert_roundtrip([[
puts "hello"
puts stderr "error message"
]], "puts")
    end)
  end)

  describe("control flow", function()
    it("should validate if/then", function()
      assert_roundtrip([[
if {$x > 0} {
    puts "positive"
}
]], "if/then")
    end)

    it("should validate if/then/else", function()
      assert_roundtrip([[
if {$x > 0} {
    puts "positive"
} else {
    puts "non-positive"
}
]], "if/then/else")
    end)

    it("should validate if/elseif/else", function()
      assert_roundtrip([[
if {$x > 0} {
    puts "positive"
} elseif {$x == 0} {
    puts "zero"
} else {
    puts "negative"
}
]], "if/elseif/else")
    end)

    it("should validate while loop", function()
      assert_roundtrip([[
set i 0
while {$i < 10} {
    puts $i
    incr i
}
]], "while loop")
    end)

    it("should validate for loop", function()
      assert_roundtrip([[
for {set i 0} {$i < 10} {incr i} {
    puts $i
}
]], "for loop")
    end)

    it("should validate foreach loop", function()
      assert_roundtrip([[
foreach item {a b c d} {
    puts $item
}
]], "foreach loop")
    end)

    it("should validate switch statement", function()
      assert_roundtrip([[
switch $action {
    "start" {
        puts "starting"
    }
    "stop" {
        puts "stopping"
    }
    default {
        puts "unknown"
    }
}
]], "switch statement")
    end)
  end)

  describe("namespaces", function()
    it("should validate namespace eval", function()
      assert_roundtrip([[
namespace eval ::mylib {
    proc helper {} {
        puts "helper"
    }
}
]], "namespace eval")
    end)

    it("should validate nested namespaces", function()
      assert_roundtrip([[
namespace eval ::outer {
    namespace eval inner {
        proc deep {} {
            puts "deep"
        }
    }
}
]], "nested namespaces")
    end)

    it("should validate namespace import/export", function()
      assert_roundtrip([[
namespace eval ::mylib {
    namespace export helper
    namespace import ::otherlib::util
}
]], "namespace import/export")
    end)
  end)

  describe("packages", function()
    it("should validate package require", function()
      assert_roundtrip([[
package require Tcl 8.6
]], "package require")
    end)

    it("should validate package provide", function()
      assert_roundtrip([[
package provide mylib 1.0
]], "package provide")
    end)
  end)

  describe("expressions and lists", function()
    it("should validate expr", function()
      assert_roundtrip([[
set result [expr {$x + $y * 2}]
]], "expr")
    end)

    it("should validate list operations", function()
      assert_roundtrip([[
set mylist [list a b c d]
lappend mylist e
]], "list operations")
    end)
  end)

  describe("variable declarations", function()
    it("should validate global declaration", function()
      assert_roundtrip([[
proc use_global {} {
    global myvar
    puts $myvar
}
]], "global declaration")
    end)

    it("should validate upvar", function()
      assert_roundtrip([[
proc set_caller_var {varname value} {
    upvar 1 $varname local
    set local $value
}
]], "upvar")
    end)

    it("should validate variable command", function()
      assert_roundtrip([[
namespace eval ::mylib {
    variable counter 0
}
]], "variable command")
    end)
  end)

  describe("source", function()
    it("should validate source command", function()
      assert_roundtrip([[
source utils.tcl
]], "source command")
    end)
  end)

  describe("complex multi-construct code", function()
    it("should validate a realistic TCL module", function()
      assert_roundtrip([[
package require Tcl 8.6
package provide myapp 1.0

namespace eval ::myapp {
    variable version "1.0"
    variable debug 0

    namespace export init process

    proc init {config} {
        variable debug
        if {[dict exists $config debug]} {
            set debug [dict get $config debug]
        }
    }

    proc process {input args} {
        variable debug
        if {$debug} {
            puts stderr "Processing: $input"
        }

        set result ""
        foreach item $input {
            switch -exact -- $item {
                "skip" {
                    continue
                }
                "stop" {
                    break
                }
                default {
                    lappend result $item
                }
            }
        }
        return $result
    }
}
]], "realistic TCL module")
    end)

    it("should validate deeply nested control flow", function()
      assert_roundtrip([[
proc deep_nesting {x y} {
    if {$x > 0} {
        while {$y > 0} {
            foreach item {a b c} {
                if {$item eq "b"} {
                    puts "found b at y=$y"
                }
            }
            incr y -1
        }
    }
}
]], "deeply nested control flow")
    end)
  end)

  describe("parse_with_errors parity", function()
    it("should produce schema-valid AST via parse_with_errors", function()
      local code = [[
proc hello {name} {
    set greeting "Hello"
    puts "$greeting, $name!"
}
set x 10
]]
      local result = parser.parse_with_errors(code)
      assert.is_not_nil(result, "parse_with_errors returned nil")
      assert.is_table(result, "parse_with_errors must return a table")
      assert.is_not_nil(result.ast, "parse_with_errors result must have .ast")

      local validation = validator.validate_ast(result.ast, { strict = true })
      if not validation.valid then
        local msgs = {}
        for _, e in ipairs(validation.errors) do
          table.insert(msgs, string.format("  [%s] %s", e.path or "?", e.message or "?"))
        end
        error(
          string.format(
            "parse_with_errors schema validation failed:\n%s",
            table.concat(msgs, "\n")
          )
        )
      end
    end)
  end)

  describe("edge cases", function()
    it("should validate empty proc body", function()
      assert_roundtrip([[
proc noop {} {}
]], "empty proc body")
    end)

    it("should validate comment-only code", function()
      local ast, err = parser.parse("# just a comment\n")
      -- Comments may or may not produce children, but should parse
      assert.is_nil(err, "comment-only parse failed: " .. tostring(err))
      assert.is_not_nil(ast, "comment-only returned nil AST")

      local result = validator.validate_ast(ast, { strict = true })
      assert.is_true(result.valid, "comment-only AST failed schema validation")
    end)
  end)
end)

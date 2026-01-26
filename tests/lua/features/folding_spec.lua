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

    it("should return empty array for nil code", function()
      local ranges = folding.get_folding_ranges(nil)
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
      assert.equals("region", ranges[1].kind)
      -- LSP uses 0-indexed lines
      -- Parser returns 1-indexed lines, we subtract 1
      -- Just verify the range spans multiple lines
      assert.is_true(ranges[1].endLine > ranges[1].startLine)
    end)

    it("should not fold single-line proc", function()
      local code = [[proc foo {} { return 1 }]]
      local ranges = folding.get_folding_ranges(code)
      assert.is_table(ranges)
      assert.equals(0, #ranges)
    end)

    it("should return multiple fold ranges for nested structures", function()
      local code = [[proc outer {} {
    if {1} {
        puts "hello"
    }
}]]
      local ranges = folding.get_folding_ranges(code)
      assert.is_table(ranges)
      -- Should have at least proc and if folds
      assert.is_true(#ranges >= 1)
    end)
  end)

  describe("extract_ranges_from_ast", function()
    it("should handle AST with no children", function()
      local ast = { type = "root", children = {} }
      local ranges = folding.extract_ranges_from_ast(ast)
      assert.is_table(ranges)
      assert.equals(0, #ranges)
    end)

    it("should extract ranges from proc nodes", function()
      local ast = {
        type = "root",
        children = {
          {
            type = "proc",
            name = "test",
            range = {
              start = { line = 1, column = 1 },
              end_pos = { line = 4, column = 1 },
            },
          },
        },
      }
      local ranges = folding.extract_ranges_from_ast(ast)
      assert.is_table(ranges)
      assert.equals(1, #ranges)
      assert.equals(0, ranges[1].startLine) -- 0-indexed
      assert.equals(3, ranges[1].endLine) -- 0-indexed
      assert.equals("region", ranges[1].kind)
    end)

    it("should skip single-line nodes", function()
      local ast = {
        type = "root",
        children = {
          {
            type = "proc",
            name = "test",
            range = {
              start = { line = 1, column = 1 },
              end_pos = { line = 1, column = 20 },
            },
          },
        },
      }
      local ranges = folding.extract_ranges_from_ast(ast)
      assert.is_table(ranges)
      assert.equals(0, #ranges)
    end)
  end)

  describe("make_range", function()
    it("should create range from node with start/end_pos format", function()
      local node = {
        type = "proc",
        range = {
          start = { line = 5, column = 1 },
          end_pos = { line = 10, column = 1 },
        },
      }
      local range = folding.make_range(node)
      assert.is_not_nil(range)
      assert.equals(4, range.startLine) -- 0-indexed
      assert.equals(9, range.endLine) -- 0-indexed
      assert.equals("region", range.kind)
    end)

    it("should return nil for node without range", function()
      local node = { type = "proc", name = "test" }
      local range = folding.make_range(node)
      assert.is_nil(range)
    end)

    it("should return nil for single-line node", function()
      local node = {
        type = "proc",
        range = {
          start = { line = 5, column = 1 },
          end_pos = { line = 5, column = 20 },
        },
      }
      local range = folding.make_range(node)
      assert.is_nil(range)
    end)
  end)

  describe("extract_comment_ranges", function()
    it("should return empty for less than 2 comments", function()
      local comments = {
        { text = "# comment", range = { start = { line = 1 } } },
      }
      local ranges = folding.extract_comment_ranges(comments)
      assert.is_table(ranges)
      assert.equals(0, #ranges)
    end)

    it("should group consecutive comments", function()
      local comments = {
        { text = "# line 1", range = { start = { line = 1, column = 1 } } },
        { text = "# line 2", range = { start = { line = 2, column = 1 } } },
        { text = "# line 3", range = { start = { line = 3, column = 1 } } },
      }
      local ranges = folding.extract_comment_ranges(comments)
      assert.is_table(ranges)
      assert.equals(1, #ranges)
      assert.equals(0, ranges[1].startLine) -- 0-indexed
      assert.equals(2, ranges[1].endLine) -- 0-indexed
      assert.equals("comment", ranges[1].kind)
    end)

    it("should not group non-consecutive comments", function()
      local comments = {
        { text = "# line 1", range = { start = { line = 1, column = 1 } } },
        { text = "# line 5", range = { start = { line = 5, column = 1 } } },
      }
      local ranges = folding.extract_comment_ranges(comments)
      assert.is_table(ranges)
      assert.equals(0, #ranges)
    end)
  end)

  describe("integration", function()
    local temp_dir
    local test_file

    before_each(function()
      temp_dir = helpers.create_temp_dir("folding_test")
      test_file = temp_dir .. "/test.tcl"
    end)

    after_each(function()
      helpers.cleanup_temp_dir(temp_dir)
    end)

    it("should fold a complex TCL file", function()
      helpers.write_file(test_file, [[
# Header comment
# More header info
# Third line

proc main {} {
    puts "main"
    if {1} {
        puts "inside if"
    }
}

namespace eval ::test {
    proc helper {} {
        return 1
    }
}
]])
      local content = helpers.read_file(test_file)
      local ranges = folding.get_folding_ranges(content)

      assert.is_table(ranges)
      -- Should have comment block + main proc + if + namespace + helper
      assert.is_true(#ranges >= 3)

      -- Check we have at least one comment and one region
      local has_comment = false
      local has_region = false
      for _, r in ipairs(ranges) do
        if r.kind == "comment" then
          has_comment = true
        end
        if r.kind == "region" then
          has_region = true
        end
      end
      assert.is_true(has_comment, "Should have at least one comment fold")
      assert.is_true(has_region, "Should have at least one region fold")
    end)
  end)
end)

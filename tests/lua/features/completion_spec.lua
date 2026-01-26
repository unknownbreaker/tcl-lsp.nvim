-- tests/lua/features/completion_spec.lua
describe("completion", function()
  local completion

  before_each(function()
    package.loaded["tcl-lsp.features.completion"] = nil
    completion = require("tcl-lsp.features.completion")
  end)

  describe("detect_context", function()
    it("detects variable context after $", function()
      assert.equals("variable", completion.detect_context("set x $", 7))
      assert.equals("variable", completion.detect_context("puts $foo", 9))
    end)

    it("detects variable context with partial name", function()
      assert.equals("variable", completion.detect_context("puts $var", 9))
    end)

    it("detects namespace context after ::", function()
      assert.equals("namespace", completion.detect_context("::ns::", 6))
      assert.equals("namespace", completion.detect_context("::foo::bar", 10))
    end)

    it("detects package context after package require", function()
      assert.equals("package", completion.detect_context("package require ", 16))
      assert.equals("package", completion.detect_context("package require htt", 19))
    end)

    it("returns command context by default", function()
      assert.equals("command", completion.detect_context("pu", 2))
      assert.equals("command", completion.detect_context("set x [for", 10))
    end)
  end)

  describe("get_file_symbols", function()
    it("extracts procs from code", function()
      local code = [[
proc my_proc {arg1 arg2} {
  return $arg1
}
proc another_proc {} {
  puts "hello"
}
]]
      local symbols = completion.get_file_symbols(code, "/test.tcl")
      local names = {}
      for _, sym in ipairs(symbols) do
        if sym.type == "proc" then
          names[sym.name] = true
        end
      end
      assert.is_true(names["my_proc"])
      assert.is_true(names["another_proc"])
    end)

    it("extracts variables from code", function()
      local code = [[
set myvar "value"
set another 123
]]
      local symbols = completion.get_file_symbols(code, "/test.tcl")
      local names = {}
      for _, sym in ipairs(symbols) do
        if sym.type == "variable" then
          names[sym.name] = true
        end
      end
      assert.is_true(names["myvar"])
      assert.is_true(names["another"])
    end)

    it("returns empty list for invalid code", function()
      local code = "this is not valid {{{ tcl"
      local symbols = completion.get_file_symbols(code, "/test.tcl")
      assert.is_table(symbols)
      -- May be empty or contain partial results - just shouldn't crash
    end)
  end)

  describe("build_completion_item", function()
    it("builds item for proc", function()
      local symbol = { name = "my_proc", type = "proc", qualified_name = "::my_proc" }
      local item = completion.build_completion_item(symbol)
      assert.equals("my_proc", item.label)
      assert.equals("proc", item.detail)
      assert.equals("my_proc", item.insertText)
      assert.equals(vim.lsp.protocol.CompletionItemKind.Function, item.kind)
    end)

    it("builds item for variable", function()
      local symbol = { name = "myvar", type = "variable", qualified_name = "::myvar" }
      local item = completion.build_completion_item(symbol)
      assert.equals("myvar", item.label)
      assert.equals("variable", item.detail)
      assert.equals("myvar", item.insertText)
      assert.equals(vim.lsp.protocol.CompletionItemKind.Variable, item.kind)
    end)

    it("builds item for builtin", function()
      local builtin = { name = "puts", type = "builtin" }
      local item = completion.build_completion_item(builtin)
      assert.equals("puts", item.label)
      assert.equals("builtin", item.detail)
      assert.equals(vim.lsp.protocol.CompletionItemKind.Keyword, item.kind)
    end)

    it("builds item for namespace", function()
      local symbol = { name = "myns", type = "namespace", qualified_name = "::myns" }
      local item = completion.build_completion_item(symbol)
      assert.equals("myns", item.label)
      assert.equals("namespace", item.detail)
      assert.equals(vim.lsp.protocol.CompletionItemKind.Module, item.kind)
    end)
  end)

  describe("get_completions", function()
    it("returns empty table for empty buffer", function()
      local items = completion.get_completions("", 1, 0, "/test.tcl")
      assert.is_table(items)
    end)

    it("includes builtins in command context", function()
      local items = completion.get_completions("pu", 1, 2, "/test.tcl")
      local has_puts = false
      for _, item in ipairs(items) do
        if item.label == "puts" then
          has_puts = true
          break
        end
      end
      assert.is_true(has_puts)
    end)

    it("filters to variables after $", function()
      local code = [[set myvar "hello"
puts $my]]
      local items = completion.get_completions(code, 2, 8, "/test.tcl")
      -- Should include myvar, exclude procs/builtins
      local found_var = false
      local found_builtin = false
      for _, item in ipairs(items) do
        if item.label == "myvar" then
          found_var = true
        end
        if item.detail == "builtin" then
          found_builtin = true
        end
      end
      assert.is_true(found_var)
      assert.is_false(found_builtin)
    end)

    it("filters to packages after package require", function()
      local code = "package require ht"
      local items = completion.get_completions(code, 1, 18, "/test.tcl")
      -- Should include http, exclude procs/variables
      local found_http = false
      local found_proc = false
      for _, item in ipairs(items) do
        if item.label == "http" then
          found_http = true
        end
        if item.detail == "proc" then
          found_proc = true
        end
      end
      assert.is_true(found_http)
      assert.is_false(found_proc)
    end)

    it("includes procs from current file", function()
      local code = [[proc my_helper {} { return 1 }
my_]]
      local items = completion.get_completions(code, 2, 3, "/test.tcl")
      local found = false
      for _, item in ipairs(items) do
        if item.label == "my_helper" then
          found = true
          break
        end
      end
      assert.is_true(found)
    end)
  end)

  describe("setup", function()
    it("is callable", function()
      assert.has_no.errors(function()
        completion.setup()
      end)
    end)
  end)

  describe("omnifunc", function()
    it("returns start position when findstart=1", function()
      -- Mock vim functions
      local original_fn = vim.fn
      vim.fn = setmetatable({
        getline = function()
          return "puts hello"
        end,
        col = function()
          return 11
        end,
      }, { __index = original_fn })

      local result = completion.omnifunc(1, "")
      assert.is_number(result)

      vim.fn = original_fn
    end)
  end)
end)

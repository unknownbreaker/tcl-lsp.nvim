-- tests/lua/analyzer/indexer_spec.lua
-- Tests for Background Indexer - scans workspace files without blocking the editor

describe("Background Indexer", function()
  local indexer

  before_each(function()
    package.loaded["tcl-lsp.analyzer.indexer"] = nil
    package.loaded["tcl-lsp.analyzer.index"] = nil
    indexer = require("tcl-lsp.analyzer.indexer")
    indexer.reset()
  end)

  describe("find_tcl_files", function()
    it("should find .tcl files in directory", function()
      -- Use the project's own tcl directory for testing
      local project_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h:h")
      local files = indexer.find_tcl_files(project_root .. "/tcl")

      assert.is_table(files)
      assert.is_true(#files > 0, "Should find TCL files")

      local has_tcl = false
      for _, f in ipairs(files) do
        if f:match("%.tcl$") then
          has_tcl = true
          break
        end
      end
      assert.is_true(has_tcl, "Should include .tcl files")
    end)
  end)

  describe("state", function()
    it("should start in idle state", function()
      assert.equals("idle", indexer.get_status().status)
    end)
  end)

  describe("index_file", function()
    it("should parse file and add symbols to index", function()
      local index = require("tcl-lsp.analyzer.index")
      index.clear()

      -- Create a temp file with TCL code
      local temp_file = vim.fn.tempname() .. ".tcl"
      local f = io.open(temp_file, "w")
      f:write("proc hello {} { puts hi }\n")
      f:close()

      indexer.index_file(temp_file)

      local symbol = index.find("::hello")
      assert.is_not_nil(symbol, "Should index the proc")
      assert.equals("proc", symbol.type)

      vim.fn.delete(temp_file)
    end)
  end)

  describe("start", function()
    it("should set status to scanning", function()
      local project_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h:h")

      indexer.start(project_root .. "/tcl")

      local status = indexer.get_status()
      assert.is_true(status.status == "scanning" or status.status == "ready")
      assert.is_true(status.total > 0)
    end)
  end)
end)

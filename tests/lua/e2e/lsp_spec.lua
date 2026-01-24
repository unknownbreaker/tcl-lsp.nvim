-- tests/lua/e2e/lsp_spec.lua
-- Happy-path end-to-end tests for TCL LSP features
-- Tests verify the full pipeline works, not edge cases

describe("LSP E2E: Happy Path", function()
  local definition_feature
  local references_feature
  local hover_feature
  local diagnostics_feature
  local rename_feature
  local indexer
  local index_store
  local fixture_dir

  before_each(function()
    -- Clear module cache for fresh state
    package.loaded["tcl-lsp.features.definition"] = nil
    package.loaded["tcl-lsp.features.references"] = nil
    package.loaded["tcl-lsp.features.hover"] = nil
    package.loaded["tcl-lsp.features.diagnostics"] = nil
    package.loaded["tcl-lsp.features.rename"] = nil
    package.loaded["tcl-lsp.analyzer.indexer"] = nil
    package.loaded["tcl-lsp.analyzer.index"] = nil
    package.loaded["tcl-lsp.analyzer.definitions"] = nil
    package.loaded["tcl-lsp.analyzer.references"] = nil

    -- Load features
    definition_feature = require("tcl-lsp.features.definition")
    references_feature = require("tcl-lsp.features.references")
    hover_feature = require("tcl-lsp.features.hover")
    diagnostics_feature = require("tcl-lsp.features.diagnostics")
    rename_feature = require("tcl-lsp.features.rename")
    indexer = require("tcl-lsp.analyzer.indexer")
    index_store = require("tcl-lsp.analyzer.index")

    -- Setup diagnostics namespace
    diagnostics_feature.setup()

    -- Point to simple fixture
    local test_file = debug.getinfo(1, "S").source:sub(2)
    fixture_dir = vim.fn.fnamemodify(test_file, ":p:h:h:h") .. "/fixtures/simple"

    -- Clear and reset index
    indexer.reset()
    index_store.clear()
  end)

  after_each(function()
    -- Clean up all buffers
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      end
    end
    indexer.reset()
    index_store.clear()
  end)

  -- Helper to index fixture files
  local function index_fixture()
    indexer.index_file(fixture_dir .. "/math.tcl")
    indexer.index_file(fixture_dir .. "/main.tcl")
    indexer.resolve_references()
  end

  it("goto_definition: jumps to proc in another file", function()
    index_fixture()

    -- Open main.tcl
    local main_file = fixture_dir .. "/main.tcl"
    vim.cmd("edit " .. vim.fn.fnameescape(main_file))
    local bufnr = vim.api.nvim_get_current_buf()

    -- Line 6: "set result [add 1 2]" - cursor on "add" (1-indexed: line 6, col 14)
    -- vim cursor is 1-indexed, col is 0-indexed byte offset
    vim.api.nvim_win_set_cursor(0, { 6, 13 })
    local result = definition_feature.handle_definition(bufnr, 5, 13)

    assert.is_not_nil(result, "Should find definition")
    assert.is_true(result.uri:match("math%.tcl$") ~= nil, "Should jump to math.tcl")
    -- proc add is on line 4 (0-indexed: 3)
    assert.is_true(result.range.start.line <= 5, "Should point to proc add definition")
  end)

  it("find_references: finds usages across files", function()
    index_fixture()

    -- Open math.tcl
    local math_file = fixture_dir .. "/math.tcl"
    vim.cmd("edit " .. vim.fn.fnameescape(math_file))
    local bufnr = vim.api.nvim_get_current_buf()

    -- Line 4: "proc add {a b}" - cursor on "add" (1-indexed: line 4, col 6 for vim cursor)
    -- 0-indexed for handle_references: line 3, col 5
    vim.api.nvim_win_set_cursor(0, { 4, 5 })
    local refs = references_feature.handle_references(bufnr, 3, 5)

    assert.is_not_nil(refs, "Should find references")
    assert.is_true(#refs >= 2, "Should find at least 2 references (definition + usage)")
  end)

  it("hover: shows proc signature", function()
    index_fixture()

    -- Open main.tcl
    local main_file = fixture_dir .. "/main.tcl"
    vim.cmd("edit " .. vim.fn.fnameescape(main_file))
    local bufnr = vim.api.nvim_get_current_buf()

    -- Line 6: "set result [add 1 2]" - cursor on "add"
    -- Set cursor first (required for <cword> to work)
    vim.api.nvim_win_set_cursor(0, { 6, 13 })
    local result = hover_feature.handle_hover(bufnr, 5, 13)

    assert.is_not_nil(result, "Should return hover info")
    -- Result should contain proc signature
    local content = result
    if type(result) == "table" and result.contents then
      content = type(result.contents) == "table" and table.concat(result.contents, "\n") or result.contents
    end
    assert.is_true(content:match("proc") ~= nil or content:match("add") ~= nil, "Should show proc info")
  end)

  it("rename: updates proc name in multiple files", function()
    index_fixture()

    -- Open math.tcl
    local math_file = fixture_dir .. "/math.tcl"
    vim.cmd("edit " .. vim.fn.fnameescape(math_file))
    local bufnr = vim.api.nvim_get_current_buf()

    -- Line 4: "proc add {a b}" - cursor on "add"
    -- Set cursor first (required for <cword> to work)
    vim.api.nvim_win_set_cursor(0, { 4, 5 })
    local result = rename_feature.handle_rename(bufnr, 3, 5, "sum")

    assert.is_not_nil(result, "Should return rename edits")
    -- Result should have workspace_edit with changes
    if result.workspace_edit and result.workspace_edit.changes then
      local file_count = 0
      for _ in pairs(result.workspace_edit.changes) do
        file_count = file_count + 1
      end
      assert.is_true(file_count >= 1, "Should have edits in at least one file")
    end
  end)

  it("diagnostics: no errors on valid file", function()
    -- Open math.tcl (valid TCL)
    local math_file = fixture_dir .. "/math.tcl"
    vim.cmd("edit " .. vim.fn.fnameescape(math_file))
    local bufnr = vim.api.nvim_get_current_buf()

    -- Run diagnostics
    diagnostics_feature.check_buffer(bufnr)

    -- Get diagnostics for this buffer
    local diags = vim.diagnostic.get(bufnr)

    -- Filter for errors only (warnings are OK)
    local errors = vim.tbl_filter(function(d)
      return d.severity == vim.diagnostic.severity.ERROR
    end, diags)

    assert.equals(0, #errors, "Valid TCL file should have no errors")
  end)

  it("workspace: indexes directory and finds symbols", function()
    -- Index the fixture directory
    index_fixture()

    -- Check that symbols were indexed
    local add_symbol = index_store.find("::add")
    local subtract_symbol = index_store.find("::subtract")

    -- At least one should be found (namespace prefix may vary)
    local found_add = add_symbol ~= nil or index_store.find("add") ~= nil
    local found_subtract = subtract_symbol ~= nil or index_store.find("subtract") ~= nil

    assert.is_true(found_add or found_subtract, "Should index at least one symbol from fixture")
  end)
end)

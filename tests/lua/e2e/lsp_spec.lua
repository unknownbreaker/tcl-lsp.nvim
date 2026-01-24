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
    -- This test will be implemented next
    assert.is_true(false, "Test not implemented yet")
  end)
end)

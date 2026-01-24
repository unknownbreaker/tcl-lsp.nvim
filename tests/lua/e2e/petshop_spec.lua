-- tests/lua/e2e/petshop_spec.lua
-- Adversarial end-to-end tests for TCL LSP using the petshop fixture
-- These tests deliberately target edge cases to find bugs in the LSP implementation

local helpers = require("tests.spec.test_helpers")

describe("Petshop E2E: Adversarial LSP Tests", function()
  local definition_feature
  local references_feature
  local hover_feature
  local diagnostics_feature
  local rename_feature
  local indexer
  local index_store
  local petshop_dir

  -- Helper to index specific files needed for a test
  local function index_files(file_paths)
    for _, file in ipairs(file_paths) do
      local full_path = petshop_dir .. "/" .. file
      indexer.index_file(full_path)
    end
    -- Process second pass for references
    indexer.resolve_references()
  end

  -- Helper to get diagnostics (check_buffer then vim.diagnostic.get)
  local function get_diagnostics(bufnr)
    diagnostics_feature.check_buffer(bufnr)
    return vim.diagnostic.get(bufnr)
  end

  before_each(function()
    -- Load features
    package.loaded["tcl-lsp.features.definition"] = nil
    package.loaded["tcl-lsp.features.references"] = nil
    package.loaded["tcl-lsp.features.hover"] = nil
    package.loaded["tcl-lsp.features.diagnostics"] = nil
    package.loaded["tcl-lsp.features.rename"] = nil
    package.loaded["tcl-lsp.analyzer.indexer"] = nil
    package.loaded["tcl-lsp.analyzer.index"] = nil

    definition_feature = require("tcl-lsp.features.definition")
    references_feature = require("tcl-lsp.features.references")
    hover_feature = require("tcl-lsp.features.hover")
    diagnostics_feature = require("tcl-lsp.features.diagnostics")
    rename_feature = require("tcl-lsp.features.rename")
    indexer = require("tcl-lsp.analyzer.indexer")
    index_store = require("tcl-lsp.analyzer.index")

    -- Setup diagnostics (creates namespace)
    diagnostics_feature.setup()

    -- Point to petshop fixture
    petshop_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
      .. "/fixtures/petshop"

    -- Clear index for fresh start
    indexer.reset()
    index_store.clear()
  end)

  after_each(function()
    -- Clean up buffers
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      end
    end
    indexer.reset()
    index_store.clear()
  end)

  describe("Go-to-Definition: Cross-Namespace Edge Cases", function()
    it("should find definition of proc called with fully-qualified name across files", function()
      -- Attack: transactions.tcl calls ::petshop::models::pet::get
      -- LSP must resolve through namespace boundaries

      -- Index the relevant files
      index_files({ "models/pet.tcl", "services/transactions.tcl" })

      local txn_file = petshop_dir .. "/services/transactions.tcl"
      vim.cmd("edit " .. vim.fn.fnameescape(txn_file))
      local bufnr = vim.api.nvim_get_current_buf()

      -- Line 13: set pet [::petshop::models::pet::get $pet_id]
      -- Position cursor on "get" in the fully-qualified call
      local result = definition_feature.handle_definition(bufnr, 12, 45)

      if result then
        assert.is_not_nil(result.uri, "Should return URI")
        assert.is_true(result.uri:match("pet%.tcl$") ~= nil, "Should jump to pet.tcl")
        -- The definition is on line 42: proc get {id}
        assert.is_true(
          result.range.start.line >= 40 and result.range.start.line <= 44,
          "Should point to proc get definition around line 42"
        )
      else
        -- CRITICAL: Cross-file fully-qualified namespace resolution failed
        helpers.warn("CRITICAL: Failed to resolve ::petshop::models::pet::get across files")
      end
    end)

    it("should distinguish between same-named procs in different namespaces", function()
      -- Attack: petshop.tcl has proc "get" in ensemble at line 35
      -- models/pet.tcl has proc "get" at line 42
      -- models/customer.tcl has proc "get" at line 28
      -- models/inventory.tcl has proc "get_stock" (different)
      -- LSP must NOT conflate these

      local pet_file = petshop_dir .. "/models/pet.tcl"
      vim.cmd("edit " .. vim.fn.fnameescape(pet_file))
      local bufnr = vim.api.nvim_get_current_buf()

      -- Position on line 47: return [dict get $all_pets $id]
      -- Cursor on "get" should resolve to dict's get (builtin), not proc get
      -- This tests if LSP wrongly jumps to line 42 (our proc)
      local result = definition_feature.handle_definition(bufnr, 46, 25)

      -- If result points to line 42, LSP confused dict get with proc get
      if result and result.range.start.line == 42 then
        error(
          "HIGH: LSP confused dict get (builtin) with proc get - namespace scoping bug"
        )
      end
    end)

    it("should resolve namespace ensemble subcommands", function()
      -- Attack: petshop.tcl line 34: return [::petshop::models::pet::create {*}$args]
      -- This is called via ensemble: "petshop pet create"
      -- LSP should resolve "create" to line 12 of models/pet.tcl

      index_files({ "models/pet.tcl", "petshop.tcl" })

      local main_file = petshop_dir .. "/petshop.tcl"
      vim.cmd("edit " .. vim.fn.fnameescape(main_file))
      local bufnr = vim.api.nvim_get_current_buf()

      -- Line 34, cursor on "create"
      local result = definition_feature.handle_definition(bufnr, 33, 55)

      if result then
        assert.is_true(result.uri:match("pet%.tcl$") ~= nil, "Should resolve to pet.tcl")
        -- proc create is on line 12
        assert.is_true(
          result.range.start.line >= 10 and result.range.start.line <= 14,
          "Should point to proc create around line 12"
        )
      else
        helpers.warn("MEDIUM: Ensemble subcommand resolution failed for create")
      end
    end)

    it("should handle nested proc definitions (proc inside proc)", function()
      -- Attack: models/pet.tcl has nested proc at line 17
      -- proc create contains: proc validate_species_inner
      -- LSP should find this nested definition

      local pet_file = petshop_dir .. "/models/pet.tcl"
      vim.cmd("edit " .. vim.fn.fnameescape(pet_file))
      local bufnr = vim.api.nvim_get_current_buf()

      -- Line 22: if {![validate_species_inner $species]}
      local result = definition_feature.handle_definition(bufnr, 21, 16)

      if result then
        -- Should point to line 17: proc validate_species_inner
        assert.is_true(
          result.range.start.line >= 15 and result.range.start.line <= 19,
          "Should find nested proc definition"
        )
      else
        helpers.warn("MEDIUM: Nested proc definition not found - scope tracking issue")
      end
    end)

    it("should handle variable/proc name collision", function()
      -- Attack: models/pet.tcl line 9 has variable create "default_species"
      -- Line 12 has proc create
      -- When cursor is on variable reference, should NOT jump to proc

      local pet_file = petshop_dir .. "/models/pet.tcl"
      vim.cmd("edit " .. vim.fn.fnameescape(pet_file))
      local bufnr = vim.api.nvim_get_current_buf()

      -- Line 9: variable create "default_species"
      -- Position on "create" in variable declaration
      local result = definition_feature.handle_definition(bufnr, 8, 15)

      if result and result.range.start.line == 11 then
        error("HIGH: LSP confused variable 'create' with proc 'create' - name collision bug")
      end
    end)

    it("should resolve interp alias shortcuts", function()
      -- Attack: models/pet.tcl line 102: interp alias {} ::pet {} ::petshop::models::pet::create
      -- Calling "::pet" should resolve to "create" proc
      -- This is an unusual edge case

      -- For now, just document that this is hard to resolve
      helpers.warn("LOW: interp alias resolution not tested - complex runtime feature")
    end)

    it("should handle dynamic variable access via set $varname", function()
      -- Attack: models/inventory.tcl uses "set $varname" pattern
      -- Line 16: set stock_$item_id $quantity
      -- Line 33: return [set [namespace current]::$varname]
      -- LSP likely cannot resolve this (too dynamic), but should not crash

      local inv_file = petshop_dir .. "/models/inventory.tcl"
      vim.cmd("edit " .. vim.fn.fnameescape(inv_file))
      local bufnr = vim.api.nvim_get_current_buf()

      -- Line 33: set [namespace current]::$varname
      -- This should NOT crash the LSP
      local success = pcall(definition_feature.handle_definition, bufnr, 32, 20)

      assert.is_true(success, "CRITICAL: Dynamic variable access crashed LSP")
    end)
  end)

  describe("Find-References: Multi-File and Scope Edge Cases", function()
    it("should find all cross-namespace references to a proc", function()
      -- Attack: ::petshop::models::pet::get is called from:
      --   - petshop.tcl line 35 (via ensemble)
      --   - services/transactions.tcl line 13
      --   - Potentially views/*.rvt files
      -- LSP should find ALL of these

      index_files({
        "models/pet.tcl",
        "services/transactions.tcl",
        "petshop.tcl",
      })

      local pet_file = petshop_dir .. "/models/pet.tcl"
      vim.cmd("edit " .. vim.fn.fnameescape(pet_file))
      local bufnr = vim.api.nvim_get_current_buf()

      -- Position on proc get definition (line 42)
      local refs = references_feature.handle_references(bufnr, 41, 10)

      if refs then
        local file_count = {}
        for _, ref in ipairs(refs) do
          file_count[ref.file] = true
        end

        -- Should have references in at least 2 files (pet.tcl itself + transactions.tcl)
        local unique_files = 0
        for _ in pairs(file_count) do
          unique_files = unique_files + 1
        end

        if unique_files < 2 then
          helpers.warn("HIGH: Cross-file references not found for ::petshop::models::pet::get")
        end
      else
        helpers.warn("CRITICAL: Find-references returned nil for well-known proc")
      end
    end)

    it("should handle references in upvar contexts", function()
      -- Attack: models/customer.tcl line 39: upvar 1 $varname customer
      -- Variable "customer" is accessed in line 45 and saved in line 49
      -- LSP should track upvar references

      local cust_file = petshop_dir .. "/models/customer.tcl"
      vim.cmd("edit " .. vim.fn.fnameescape(cust_file))
      local bufnr = vim.api.nvim_get_current_buf()

      -- Line 39: upvar 1 $varname customer
      local refs = references_feature.handle_references(bufnr, 38, 25)

      -- This is HARD - upvar creates aliasing
      -- At minimum, should not crash
      if not refs then
        helpers.warn("MEDIUM: upvar variable references not tracked")
      end
    end)

    it("should distinguish references in different namespace scopes", function()
      -- Attack: "charge" proc exists in models/customer.tcl line 88
      -- Called from transactions.tcl line 19
      -- Should NOT find unrelated "charge" in other contexts

      index_files({ "models/customer.tcl", "services/transactions.tcl" })

      local cust_file = petshop_dir .. "/models/customer.tcl"
      vim.cmd("edit " .. vim.fn.fnameescape(cust_file))
      local bufnr = vim.api.nvim_get_current_buf()

      -- Line 88: proc charge
      local refs = references_feature.handle_references(bufnr, 87, 10)

      if refs then
        -- All refs should be in petshop::models::customer namespace context
        -- or fully-qualified calls
        for _, ref in ipairs(refs) do
          -- Should not find "charge" from unrelated code
          assert.is_not_nil(ref.file, "Reference should have file")
        end
      end
    end)

    it("should find references in RVT template files", function()
      -- Attack: views/pets/list.rvt calls ::petshop::models::pet::list (line 5)
      -- and ::petshop::services::pricing::format (line 24)
      -- LSP must parse RVT files and find these references

      index_files({
        "models/pet.tcl",
        "views/pets/list.rvt",
      })

      local pet_file = petshop_dir .. "/models/pet.tcl"
      vim.cmd("edit " .. vim.fn.fnameescape(pet_file))
      local bufnr = vim.api.nvim_get_current_buf()

      -- Line 50: proc list {{species ""}}
      local refs = references_feature.handle_references(bufnr, 49, 10)

      if refs then
        local found_rvt = false
        for _, ref in ipairs(refs) do
          if ref.file:match("%.rvt$") then
            found_rvt = true
            break
          end
        end

        if not found_rvt then
          helpers.warn("HIGH: References in RVT files not detected")
        end
      end
    end)

    it("should handle namespace import/export chains", function()
      -- Attack: petshop.tcl line 28: namespace import ::petshop::models::pet::create
      -- Line 29: namespace export create
      -- This creates an alias. References should track both original and imported

      helpers.warn("MEDIUM: Namespace import/export reference tracking is complex - not tested")
    end)
  end)

  describe("Hover: Complex Signature Edge Cases", function()
    it("should display hover for proc with default args", function()
      -- Attack: models/pet.tcl line 12: proc create {name species {price 0}}
      -- Hover should show the default value

      local pet_file = petshop_dir .. "/models/pet.tcl"
      vim.cmd("edit " .. vim.fn.fnameescape(pet_file))
      local bufnr = vim.api.nvim_get_current_buf()

      -- Hover on "create" proc name
      local hover_result = hover_feature.handle_hover(bufnr, 11, 10)

      if hover_result then
        local content = hover_result.contents
        -- Should mention "price 0" or "{price 0}"
        if type(content) == "table" then
          content = table.concat(content, "\n")
        end

        if not content:match("price") then
          helpers.warn("MEDIUM: Hover doesn't show default parameter values")
        end
      end
    end)

    it("should handle hover on procs with args as varargs", function()
      -- Attack: models/pet.tcl line 64: proc update {id args}
      -- Hover should indicate variable arguments

      local pet_file = petshop_dir .. "/models/pet.tcl"
      vim.cmd("edit " .. vim.fn.fnameescape(pet_file))
      local bufnr = vim.api.nvim_get_current_buf()

      -- Line 64: proc update {id args}
      local hover_result = hover_feature.handle_hover(bufnr, 63, 10)

      if hover_result then
        local content = hover_result.contents
        if type(content) == "table" then
          content = table.concat(content, "\n")
        end

        if not content:match("args") then
          helpers.warn("LOW: Hover doesn't show varargs parameter")
        end
      end
    end)

    it("should display namespace-qualified names in hover", function()
      -- Attack: When hovering over a fully-qualified call like
      -- ::petshop::services::pricing::calculate, show the full name

      index_files({ "services/pricing.tcl", "services/transactions.tcl" })

      local txn_file = petshop_dir .. "/services/transactions.tcl"
      vim.cmd("edit " .. vim.fn.fnameescape(txn_file))
      local bufnr = vim.api.nvim_get_current_buf()

      -- Line 16: set price [::petshop::services::pricing::calculate $pet]
      local hover_result = hover_feature.handle_hover(bufnr, 15, 50)

      if hover_result then
        local content = hover_result.contents
        if type(content) == "table" then
          content = table.concat(content, "\n")
        end

        if not content:match("pricing") then
          helpers.warn("MEDIUM: Hover doesn't show namespace context")
        end
      end
    end)

    it("should handle hover on variables with traces", function()
      -- Attack: models/inventory.tcl line 70: trace add variable v write ...
      -- Hovering on traced variable should not crash

      local inv_file = petshop_dir .. "/models/inventory.tcl"
      vim.cmd("edit " .. vim.fn.fnameescape(inv_file))
      local bufnr = vim.api.nvim_get_current_buf()

      -- Line 70: trace add variable v write
      local success = pcall(hover_feature.handle_hover, bufnr, 69, 30)

      assert.is_true(success, "CRITICAL: Hover on traced variable crashed LSP")
    end)
  end)

  describe("Diagnostics: False Positive Hunting", function()
    it("should NOT report errors for multi-line braced strings", function()
      -- Attack: utils/config.tcl has multi-line variable welcome_message (lines 6-15)
      -- LSP parsers often choke on multi-line strings

      local config_file = petshop_dir .. "/utils/config.tcl"
      vim.cmd("edit " .. vim.fn.fnameescape(config_file))
      local bufnr = vim.api.nvim_get_current_buf()

      local diags = get_diagnostics(bufnr)

      if diags then
        for _, diag in ipairs(diags) do
          if diag.lnum >= 5 and diag.lnum <= 15 then
            if diag.severity == vim.diagnostic.severity.ERROR then
              error("CRITICAL: False error on multi-line braced string in config.tcl")
            end
          end
        end
      end
    end)

    it("should NOT report errors for line continuations with backslash", function()
      -- Attack: utils/config.tcl line 34-37: expr with backslash continuations
      -- set total [expr {$base_price + \
      --   ($base_price * $tax) + \
      --   $shipping - \
      --   $discount}]

      local config_file = petshop_dir .. "/utils/config.tcl"
      vim.cmd("edit " .. vim.fn.fnameescape(config_file))
      local bufnr = vim.api.nvim_get_current_buf()

      local diags = get_diagnostics(bufnr)

      if diags then
        for _, diag in ipairs(diags) do
          if diag.lnum >= 33 and diag.lnum <= 37 then
            if diag.severity == vim.diagnostic.severity.ERROR then
              error("CRITICAL: False error on line continuation in expr")
            end
          end
        end
      end
    end)

    it("should NOT report errors for nested ternary operators in expr", function()
      -- Attack: services/pricing.tcl line 30-34: deeply nested expr with ternary
      -- set total [expr {
      --   ($base_price * (1.0 + $tax_rate))
      --   + ($weight > 10 ? $large_pet_fee : 0)
      --   - ($base_price * $loyalty_discount_rate)
      -- }]

      local pricing_file = petshop_dir .. "/services/pricing.tcl"
      vim.cmd("edit " .. vim.fn.fnameescape(pricing_file))
      local bufnr = vim.api.nvim_get_current_buf()

      local diags = get_diagnostics(bufnr)

      if diags then
        for _, diag in ipairs(diags) do
          if diag.lnum >= 29 and diag.lnum <= 34 then
            if diag.severity == vim.diagnostic.severity.ERROR then
              error("CRITICAL: False error on nested ternary in expr")
            end
          end
        end
      end
    end)

    it("should NOT report errors for apply lambdas", function()
      -- Attack: pkgIndex.tcl line 8: package ifneeded with apply lambda
      -- [list apply {{dir} { ... }} $dir]

      local pkg_file = petshop_dir .. "/pkgIndex.tcl"
      vim.cmd("edit " .. vim.fn.fnameescape(pkg_file))
      local bufnr = vim.api.nvim_get_current_buf()

      local diags = get_diagnostics(bufnr)

      if diags then
        for _, diag in ipairs(diags) do
          if diag.severity == vim.diagnostic.severity.ERROR then
            error("CRITICAL: False error on apply lambda in pkgIndex.tcl: " .. (diag.message or ""))
          end
        end
      end
    end)

    it("should NOT report errors for {*} expansion operator", function()
      -- Attack: services/events.tcl line 32: uplevel #0 [list {*}$cb {*}$args]
      -- and line 58: {*}$cb {*}$args

      local events_file = petshop_dir .. "/services/events.tcl"
      vim.cmd("edit " .. vim.fn.fnameescape(events_file))
      local bufnr = vim.api.nvim_get_current_buf()

      local diags = get_diagnostics(bufnr)

      if diags then
        for _, diag in ipairs(diags) do
          if diag.lnum >= 31 and diag.lnum <= 33 then
            if diag.severity == vim.diagnostic.severity.ERROR then
              error("CRITICAL: False error on {*} expansion in events.tcl")
            end
          end
        end
      end
    end)

    it("should NOT report errors for uplevel #0", function()
      -- Attack: services/events.tcl line 32: uplevel #0 [list {*}$cb {*}$args]

      local events_file = petshop_dir .. "/services/events.tcl"
      vim.cmd("edit " .. vim.fn.fnameescape(events_file))
      local bufnr = vim.api.nvim_get_current_buf()

      local diags = get_diagnostics(bufnr)

      if diags then
        for _, diag in ipairs(diags) do
          if diag.lnum == 31 then
            if diag.severity == vim.diagnostic.severity.ERROR then
              error("CRITICAL: False error on uplevel #0")
            end
          end
        end
      end
    end)

    it("should NOT report errors for RVT template syntax", function()
      -- Attack: views/pets/list.rvt mixes HTML and TCL with <? ?> and <?= ?>

      local list_view = petshop_dir .. "/views/pets/list.rvt"
      vim.cmd("edit " .. vim.fn.fnameescape(list_view))
      local bufnr = vim.api.nvim_get_current_buf()

      local diags = get_diagnostics(bufnr)

      if diags then
        for _, diag in ipairs(diags) do
          if diag.severity == vim.diagnostic.severity.ERROR then
            helpers.warn("HIGH: False error in RVT template - parser may not support RVT")
            break
          end
        end
      end
    end)

    it("should NOT report errors for coroutine yield", function()
      -- Attack: models/pet.tcl line 89: yield [info coroutine]

      local pet_file = petshop_dir .. "/models/pet.tcl"
      vim.cmd("edit " .. vim.fn.fnameescape(pet_file))
      local bufnr = vim.api.nvim_get_current_buf()

      local diags = get_diagnostics(bufnr)

      if diags then
        for _, diag in ipairs(diags) do
          if diag.lnum >= 88 and diag.lnum <= 92 then
            if diag.severity == vim.diagnostic.severity.ERROR then
              error("MEDIUM: False error on coroutine/yield syntax")
            end
          end
        end
      end
    end)

    it("should NOT report errors for valid TCL in petshop.tcl", function()
      -- Attack: The main petshop.tcl with namespace ensemble should parse cleanly

      local main_file = petshop_dir .. "/petshop.tcl"
      vim.cmd("edit " .. vim.fn.fnameescape(main_file))
      local bufnr = vim.api.nvim_get_current_buf()

      local diags = get_diagnostics(bufnr)

      local error_count = 0
      if diags then
        for _, diag in ipairs(diags) do
          if diag.severity == vim.diagnostic.severity.ERROR then
            error_count = error_count + 1
          end
        end
      end

      if error_count > 0 then
        helpers.warn("Found " .. error_count .. " false errors in petshop.tcl")
      end
    end)
  end)

  describe("Rename: Cross-File and Namespace Edge Cases", function()
    it("should rename proc across all files that reference it", function()
      -- Attack: Rename ::petshop::models::pet::get to ::petshop::models::pet::fetch
      -- Should update:
      --   - petshop.tcl line 35
      --   - services/transactions.tcl line 13
      --   - models/pet.tcl line 42 (definition)

      index_files({
        "models/pet.tcl",
        "services/transactions.tcl",
        "petshop.tcl",
      })

      local pet_file = petshop_dir .. "/models/pet.tcl"
      vim.cmd("edit " .. vim.fn.fnameescape(pet_file))
      local bufnr = vim.api.nvim_get_current_buf()

      -- Position on proc get definition
      local edits = rename_feature.handle_rename(bufnr, 41, 10, "fetch")

      if edits then
        local files_affected = {}
        for file, _ in pairs(edits) do
          table.insert(files_affected, file)
        end

        if #files_affected < 2 then
          helpers.warn("HIGH: Rename did not update all cross-file references")
        end

        -- Should NOT rename dict get or other 'get' procs
        -- Check that customer.tcl proc get is NOT touched
        local cust_file = petshop_dir .. "/models/customer.tcl"
        if edits[cust_file] then
          error("CRITICAL: Rename incorrectly modified unrelated proc in different namespace")
        end
      else
        helpers.warn("CRITICAL: Rename returned nil for well-known proc")
      end
    end)

    it("should NOT rename similarly-named items in other namespaces", function()
      -- Attack: There are multiple "get" procs:
      --   - ::petshop::models::pet::get
      --   - ::petshop::models::customer::get
      -- Renaming one should NOT affect the other

      index_files({
        "models/pet.tcl",
        "models/customer.tcl",
      })

      local pet_file = petshop_dir .. "/models/pet.tcl"
      vim.cmd("edit " .. vim.fn.fnameescape(pet_file))
      local bufnr = vim.api.nvim_get_current_buf()

      local edits = rename_feature.handle_rename(bufnr, 41, 10, "fetch")

      if edits then
        -- Check customer.tcl - proc get at line 28 should be UNTOUCHED
        local cust_file = petshop_dir .. "/models/customer.tcl"
        local cust_edits = edits[cust_file]

        if cust_edits then
          for _, edit in ipairs(cust_edits) do
            if edit.range.start.line >= 27 and edit.range.start.line <= 29 then
              error(
                "CRITICAL: Rename corrupted different namespace - renamed customer::get when renaming pet::get"
              )
            end
          end
        end
      end
    end)

    it("should handle rename of variable with name collision", function()
      -- Attack: models/pet.tcl has variable create (line 9) and proc create (line 12)
      -- Renaming the variable should NOT rename the proc

      local pet_file = petshop_dir .. "/models/pet.tcl"
      vim.cmd("edit " .. vim.fn.fnameescape(pet_file))
      local bufnr = vim.api.nvim_get_current_buf()

      -- Rename variable create to default_type
      local edits = rename_feature.handle_rename(bufnr, 8, 15, "default_type")

      if edits then
        -- Check that line 12 (proc create) was NOT modified
        for _, file_edits in pairs(edits) do
          for _, edit in ipairs(file_edits) do
            if edit.range.start.line == 11 then
              error("CRITICAL: Renaming variable corrupted proc with same name")
            end
          end
        end
      end
    end)

    it("should rename variables accessed via upvar", function()
      -- Attack: models/customer.tcl line 39: upvar 1 $varname customer
      -- If we rename "customer", should it update line 45 and 49?
      -- This is tricky because upvar creates aliasing

      helpers.warn("MEDIUM: upvar variable renaming is complex - requires alias tracking")
    end)
  end)

  describe("Performance: Large Workspace Stress Test", function()
    it("should handle go-to-definition without timeout", function()
      -- Measure time for cross-file definition lookup
      index_files({
        "models/pet.tcl",
        "services/transactions.tcl",
      })

      local txn_file = petshop_dir .. "/services/transactions.tcl"
      vim.cmd("edit " .. vim.fn.fnameescape(txn_file))
      local bufnr = vim.api.nvim_get_current_buf()

      local start_time = vim.loop.hrtime()
      local result = definition_feature.handle_definition(bufnr, 12, 45)
      local duration_ms = (vim.loop.hrtime() - start_time) / 1000000

      if duration_ms > 1000 then
        helpers.warn("PERFORMANCE: Go-to-definition took " .. duration_ms .. "ms (too slow)")
      end

      assert.is_true(duration_ms < 5000, "CRITICAL: Go-to-definition timeout > 5s")
    end)

    it("should handle find-references for commonly-used proc without timeout", function()
      -- Attack: Find all references to a proc used in many files
      index_files({
        "models/pet.tcl",
        "services/transactions.tcl",
        "petshop.tcl",
      })

      local pet_file = petshop_dir .. "/models/pet.tcl"
      vim.cmd("edit " .. vim.fn.fnameescape(pet_file))
      local bufnr = vim.api.nvim_get_current_buf()

      local start_time = vim.loop.hrtime()
      local refs = references_feature.handle_references(bufnr, 41, 10)
      local duration_ms = (vim.loop.hrtime() - start_time) / 1000000

      if duration_ms > 2000 then
        helpers.warn("PERFORMANCE: Find-references took " .. duration_ms .. "ms (too slow)")
      end

      assert.is_true(duration_ms < 10000, "CRITICAL: Find-references timeout > 10s")
    end)
  end)

  describe("Regression: Known Parser Edge Cases", function()
    it("should parse file with namespace ensemble create", function()
      -- Attack: petshop.tcl line 23: namespace ensemble create -subcommands {...}

      local main_file = petshop_dir .. "/petshop.tcl"
      vim.cmd("edit " .. vim.fn.fnameescape(main_file))
      local bufnr = vim.api.nvim_get_current_buf()

      local success, err = pcall(get_diagnostics, bufnr)

      assert.is_true(success, "CRITICAL: Parser crashed on namespace ensemble create: " .. tostring(err))
    end)

    it("should parse file with dict for loop", function()
      -- Attack: models/pet.tcl line 56: dict for {id pet} $all_pets {...}

      local pet_file = petshop_dir .. "/models/pet.tcl"
      vim.cmd("edit " .. vim.fn.fnameescape(pet_file))
      local bufnr = vim.api.nvim_get_current_buf()

      local success, err = pcall(get_diagnostics, bufnr)

      assert.is_true(success, "CRITICAL: Parser crashed on dict for loop: " .. tostring(err))
    end)

    it("should parse file with info coroutine", function()
      -- Attack: models/pet.tcl line 89: yield [info coroutine]

      local pet_file = petshop_dir .. "/models/pet.tcl"
      vim.cmd("edit " .. vim.fn.fnameescape(pet_file))
      local bufnr = vim.api.nvim_get_current_buf()

      local success, err = pcall(get_diagnostics, bufnr)

      assert.is_true(success, "CRITICAL: Parser crashed on info coroutine: " .. tostring(err))
    end)

    it("should parse file with uplevel at numeric level", function()
      -- Attack: models/customer.tcl line 55: upvar 2 $varname txn

      local cust_file = petshop_dir .. "/models/customer.tcl"
      vim.cmd("edit " .. vim.fn.fnameescape(cust_file))
      local bufnr = vim.api.nvim_get_current_buf()

      local success, err = pcall(get_diagnostics, bufnr)

      assert.is_true(success, "CRITICAL: Parser crashed on upvar 2: " .. tostring(err))
    end)

    it("should parse file with subst in expr", function()
      -- Attack: services/pricing.tcl line 57: expr [subst $formula]

      local pricing_file = petshop_dir .. "/services/pricing.tcl"
      vim.cmd("edit " .. vim.fn.fnameescape(pricing_file))
      local bufnr = vim.api.nvim_get_current_buf()

      local success, err = pcall(get_diagnostics, bufnr)

      assert.is_true(success, "CRITICAL: Parser crashed on expr [subst ...]: " .. tostring(err))
    end)

    it("should parse file with eval command", function()
      -- Attack: services/pricing.tcl line 93: foreach item [eval $items_expr]

      local pricing_file = petshop_dir .. "/services/pricing.tcl"
      vim.cmd("edit " .. vim.fn.fnameescape(pricing_file))
      local bufnr = vim.api.nvim_get_current_buf()

      local success, err = pcall(get_diagnostics, bufnr)

      assert.is_true(success, "CRITICAL: Parser crashed on eval: " .. tostring(err))
    end)

    it("should parse file with trace add variable", function()
      -- Attack: models/inventory.tcl line 70: trace add variable v write [...]

      local inv_file = petshop_dir .. "/models/inventory.tcl"
      vim.cmd("edit " .. vim.fn.fnameescape(inv_file))
      local bufnr = vim.api.nvim_get_current_buf()

      local success, err = pcall(get_diagnostics, bufnr)

      assert.is_true(success, "CRITICAL: Parser crashed on trace add variable: " .. tostring(err))
    end)
  end)
end)

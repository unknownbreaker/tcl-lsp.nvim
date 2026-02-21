-- lua/tcl-lsp/features/rename.lua
-- Rename feature for TCL LSP

local M = {}

local index = require("tcl-lsp.analyzer.index")
local notify = require("tcl-lsp.utils.notify")

--- Validate a new symbol name
---@param name string The proposed new name
---@return boolean ok True if valid
---@return string|nil error Error message if invalid
function M.validate_name(name)
  -- Check empty
  if not name or name:match("^%s*$") then
    return false, "Name cannot be empty"
  end

  -- Trim whitespace
  name = name:gsub("^%s+", ""):gsub("%s+$", "")

  -- TCL identifiers: alphanumeric, underscore, and :: for namespaces
  -- Pattern allows colons; we validate namespace separators separately below
  if not name:match("^[%a_:][%w_:]*$") then
    return false, "Invalid identifier: must contain only letters, numbers, underscores, and :: for namespaces"
  end

  -- Reject invalid colon usage (only :: is valid for namespaces)
  -- Replace all valid :: with empty, then check if any : remains
  local without_ns = name:gsub("::", "")
  if without_ns:match(":") then
    return false, "Invalid namespace separator"
  end

  return true, nil
end

--- Check if new name conflicts with existing symbols in scope
---@param new_name string The proposed new name
---@param scope string The scope to check (e.g., "::" or "::namespace")
---@param current_name string The current symbol name (to exclude from conflict check)
---@return boolean has_conflict True if conflict exists
---@return string|nil message Conflict description
function M.check_conflicts(new_name, scope, current_name)
  -- If renaming to same name, no conflict
  if new_name == current_name then
    return false, nil
  end

  -- Build qualified name to check
  local qualified_to_check
  if scope == "::" then
    qualified_to_check = "::" .. new_name
  else
    qualified_to_check = scope .. "::" .. new_name
  end

  -- Check if symbol exists
  local existing = index.find(qualified_to_check)
  if existing then
    return true, string.format("Symbol '%s' already exists in scope %s", new_name, scope)
  end

  return false, nil
end

--- Prepare workspace edit from references
---@param refs table List of references from find-references
---@param old_name string The current symbol name
---@param new_name string The new symbol name
---@return table workspace_edit LSP WorkspaceEdit structure
function M.prepare_workspace_edit(refs, old_name, new_name)
  local changes = {}

  for _, ref in ipairs(refs) do
    local uri = vim.uri_from_fname(ref.file)

    if not changes[uri] then
      changes[uri] = {}
    end

    -- Calculate the edit range
    -- Range is 0-indexed for LSP, but our refs use 1-indexed lines
    local start_line = (ref.range and ref.range.start and ref.range.start.line or 1) - 1
    local start_col = ref.range and ref.range.start and (ref.range.start.col or ref.range.start.column or 1) or 1

    -- Find where the symbol name starts in the text
    local text = ref.text or ""
    local name_start = text:find(old_name, 1, true)
    if name_start then
      start_col = start_col + name_start - 1
    end

    local end_col = start_col + #old_name

    table.insert(changes[uri], {
      range = {
        start = { line = start_line, character = start_col - 1 },
        ["end"] = { line = start_line, character = end_col - 1 },
      },
      newText = new_name,
    })
  end

  return { changes = changes }
end

local references_feature = require("tcl-lsp.features.references")

--- Handle rename request
---@param bufnr number Buffer number
---@param line number Line number (0-indexed)
---@param col number Column number (0-indexed)
---@param new_name string The new name for the symbol
---@return table result Contains either workspace_edit or error
function M.handle_rename(bufnr, line, col, new_name)
  -- Validate new name
  local valid, err = M.validate_name(new_name)
  if not valid then
    return { error = err }
  end

  -- Get current word
  local word = vim.fn.expand("<cword>")
  if not word or word == "" then
    return { error = "No symbol under cursor" }
  end

  -- Strip $ prefix from variables
  if word:sub(1, 1) == "$" then
    word = word:sub(2)
  end

  -- Check if new name is same as old
  if word == new_name then
    return { error = "New name is the same as current name" }
  end

  -- Get all references using existing infrastructure
  local refs = references_feature.handle_references(bufnr, line, col)
  if not refs or #refs == 0 then
    return { error = "Cannot rename: no references found for symbol '" .. word .. "'" }
  end

  -- Check for conflicts (get scope from first reference which is the definition)
  local scope = "::" -- Default to global scope
  -- TODO: Extract actual scope from symbol context

  local has_conflict, conflict_msg = M.check_conflicts(new_name, scope, word)
  if has_conflict then
    return { error = conflict_msg, conflict = true }
  end

  -- Generate workspace edit
  local workspace_edit = M.prepare_workspace_edit(refs, word, new_name)

  return {
    workspace_edit = workspace_edit,
    old_name = word,
    new_name = new_name,
    count = #refs,
  }
end

--- Execute rename with UI
---@param new_name string|nil Optional new name (prompts if nil)
local function execute_rename(new_name)
  local bufnr = vim.api.nvim_get_current_buf()
  local pos = vim.api.nvim_win_get_cursor(0)
  local line = pos[1] - 1 -- Convert to 0-indexed
  local col = pos[2]
  local old_word = vim.fn.expand("<cword>")

  local function do_rename(name)
    if not name or name == "" then
      return
    end

    local result = M.handle_rename(bufnr, line, col, name)

    if result.error then
      if result.conflict then
        -- Ask user to confirm despite conflict
        vim.ui.select({ "Yes", "No" }, {
          prompt = result.error .. ". Rename anyway?",
        }, function(choice)
          if choice == "Yes" then
            -- Force rename by bypassing conflict check
            local refs = require("tcl-lsp.features.references").handle_references(bufnr, line, col)
            if refs then
              local edit = M.prepare_workspace_edit(refs, old_word, name)
              vim.lsp.util.apply_workspace_edit(edit, "utf-8")
              notify.notify(string.format("Renamed '%s' to '%s'", old_word, name))
            end
          end
        end)
      else
        notify.notify("Rename failed: " .. result.error, vim.log.levels.ERROR)
      end
      return
    end

    -- Apply the workspace edit
    vim.lsp.util.apply_workspace_edit(result.workspace_edit, "utf-8")

    -- Count affected files
    local file_count = vim.tbl_count(result.workspace_edit.changes or {})
    notify.notify(
      string.format("Renamed '%s' to '%s' in %d files (%d occurrences)",
        result.old_name, result.new_name, file_count, result.count)
    )
  end

  if new_name then
    do_rename(new_name)
  else
    vim.ui.input({
      prompt = "New name: ",
      default = old_word,
    }, do_rename)
  end
end

--- Set up rename feature
function M.setup()
  -- Create user command
  vim.api.nvim_create_user_command("TclLspRename", function(opts)
    local new_name = opts.args ~= "" and opts.args or nil
    execute_rename(new_name)
  end, {
    nargs = "?",
    desc = "Rename TCL symbol",
  })

  -- Set up keymap for TCL files
  vim.api.nvim_create_autocmd("FileType", {
    pattern = { "tcl", "rvt" },
    callback = function(args)
      vim.keymap.set("n", "<leader>rn", function()
        execute_rename()
      end, {
        buffer = args.buf,
        desc = "Rename symbol",
      })
    end,
  })
end

return M

-- lua/tcl-lsp/analyzer/index.lua
-- Symbol Index - core data structure for storing and looking up symbol definitions

local M = {}

-- Primary index: qualified_name -> symbol
M.symbols = {}

-- Secondary index: file -> list of qualified names
M.files = {}

-- Reference index: qualified_name -> list of references
M.references = {}

-- Reverse index for cleanup: file -> list of {qualified_name, ref_index}
M.ref_files = {}

function M.clear()
  M.symbols = {}
  M.files = {}
  M.references = {}
  M.ref_files = {}
end

function M.add_symbol(symbol)
  if not symbol or not symbol.qualified_name then
    return false
  end

  M.symbols[symbol.qualified_name] = symbol

  -- Update file index
  local file = symbol.file
  if file then
    if not M.files[file] then
      M.files[file] = {}
    end
    table.insert(M.files[file], symbol.qualified_name)
  end

  return true
end

function M.find(qualified_name)
  return M.symbols[qualified_name]
end

function M.add_reference(qualified_name, ref)
  if not qualified_name or not ref then
    return false
  end

  -- Initialize reference list if needed
  if not M.references[qualified_name] then
    M.references[qualified_name] = {}
  end

  -- Add reference
  table.insert(M.references[qualified_name], ref)
  local ref_index = #M.references[qualified_name]

  -- Update reverse index for file-based cleanup
  local file = ref.file
  if file then
    if not M.ref_files[file] then
      M.ref_files[file] = {}
    end
    table.insert(M.ref_files[file], { qualified_name = qualified_name, ref_index = ref_index })
  end

  return true
end

function M.get_references(qualified_name)
  return M.references[qualified_name] or {}
end

function M.remove_file(filepath)
  -- Remove symbols from this file
  local symbols_in_file = M.files[filepath]
  if symbols_in_file then
    for _, qualified_name in ipairs(symbols_in_file) do
      M.symbols[qualified_name] = nil
    end
    M.files[filepath] = nil
  end

  -- Remove references from this file
  local refs_in_file = M.ref_files[filepath]
  if refs_in_file then
    -- Build a set of qualified_names that have refs to remove
    local to_clean = {}
    for _, ref_info in ipairs(refs_in_file) do
      to_clean[ref_info.qualified_name] = true
    end

    -- For each affected symbol, filter out refs from this file
    for qualified_name, _ in pairs(to_clean) do
      local refs = M.references[qualified_name]
      if refs then
        local filtered = {}
        for _, ref in ipairs(refs) do
          if ref.file ~= filepath then
            table.insert(filtered, ref)
          end
        end
        M.references[qualified_name] = filtered
      end
    end

    M.ref_files[filepath] = nil
  end
end

return M

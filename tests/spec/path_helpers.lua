-- tests/spec/path_helpers.lua
-- Path utilities for consistent cross-platform testing

local M = {}

-- Resolve symlinks to get canonical path (handles macOS /private/var vs /var)
function M.resolve_path(path)
  if not path then
    return nil
  end

  -- Use vim.fn.resolve to handle symlinks consistently
  local resolved = vim.fn.resolve(vim.fn.fnamemodify(path, ":p"))

  -- Additional macOS-specific handling
  if vim.fn.has "mac" == 1 then
    -- Handle /private/var/folders -> /var/folders symlink on macOS
    resolved = resolved:gsub("^/private(/var/folders)", "%1")
  end

  -- Remove trailing slash except for root
  if resolved ~= "/" and resolved:match "/$" then
    resolved = resolved:sub(1, -2)
  end

  return resolved
end

-- Compare paths with proper resolution
function M.paths_equal(path1, path2)
  local resolved1 = M.resolve_path(path1)
  local resolved2 = M.resolve_path(path2)
  return resolved1 == resolved2
end

-- Assert that paths are equal (for use in tests)
function M.assert_paths_equal(expected, actual, message)
  if not M.paths_equal(expected, actual) then
    local resolved_expected = M.resolve_path(expected)
    local resolved_actual = M.resolve_path(actual)
    local error_msg = string.format(
      "%s\nExpected: %s (resolved: %s)\nActual: %s (resolved: %s)",
      message or "Paths are not equal",
      expected,
      resolved_expected,
      actual,
      resolved_actual
    )
    error(error_msg)
  end
end

-- Create a temporary directory with consistent path resolution
function M.create_temp_dir(prefix)
  local temp_dir = vim.fn.tempname()
  if prefix then
    temp_dir = temp_dir .. "_" .. prefix
  end

  vim.fn.mkdir(temp_dir, "p")
  return M.resolve_path(temp_dir)
end

return M

-- tests/minimal_init.lua
-- Real Neovim initialization for testing - no mocking needed

-- Set up package path for dependencies
local function add_to_rtp(path)
  if vim.fn.isdirectory(path) == 1 then
    vim.opt.rtp:prepend(path)
    return true
  end
  return false
end

-- Try to find plenary.nvim in common locations
local plenary_locations = {
  vim.fn.stdpath "data" .. "/lazy/plenary.nvim",
  vim.fn.stdpath "data" .. "/site/pack/packer/start/plenary.nvim",
  vim.fn.stdpath "data" .. "/site/pack/*/start/plenary.nvim",
  "./deps/plenary.nvim",
  "../plenary.nvim",
}

local plenary_found = false
for _, path in ipairs(plenary_locations) do
  if path:match "%*" then
    -- Handle glob patterns
    local matches = vim.fn.glob(path, false, true)
    for _, match in ipairs(matches) do
      if add_to_rtp(match) then
        plenary_found = true
        break
      end
    end
  else
    if add_to_rtp(path) then
      plenary_found = true
      break
    end
  end
  if plenary_found then
    break
  end
end

if not plenary_found then
  error "plenary.nvim not found. Install it with your plugin manager or run: git clone https://github.com/nvim-lua/plenary.nvim.git deps/plenary.nvim"
end

-- Add current project to runtime path
local project_root = vim.fn.fnamemodify(vim.fn.expand "<sfile>", ":p:h:h")
vim.opt.rtp:prepend(project_root)

-- Minimal vim settings for consistent testing
vim.opt.compatible = false
vim.opt.hidden = true
vim.opt.swapfile = false
vim.opt.backup = false

-- Enable minimal logging for debugging if needed
if vim.env.TEST_DEBUG then
  vim.opt.verbosefile = "/tmp/nvim-test.log"
  vim.opt.verbose = 1
end

print "Real Neovim test environment initialized"

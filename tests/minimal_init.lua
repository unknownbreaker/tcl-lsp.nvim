-- Minimal init for plenary testing

-- Add current directory to runtimepath so our plugin can be found
vim.opt.runtimepath:prepend(vim.fn.getcwd())

-- Ensure plenary is available
local plenary_path = vim.fn.stdpath "data" .. "/lazy/plenary.nvim"
if vim.fn.isdirectory(plenary_path) == 0 then
  -- Clone plenary if it doesn't exist
  vim.fn.system {
    "git",
    "clone",
    "--depth",
    "1",
    "https://github.com/nvim-lua/plenary.nvim",
    plenary_path,
  }
end
vim.opt.runtimepath:prepend(plenary_path)

-- Set up basic vim options for testing
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false

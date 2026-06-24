-- Minimal init for running the plugin's Lua tests headlessly with plenary.
--
--   nvim --headless --noplugin -u tests/minimal_init.lua \
--     -c "PlenaryBustedDirectory tests/lua/ { minimal_init = 'tests/minimal_init.lua' }"
--
-- (the root Makefile's `test-unit` target does this for you).

-- Repo root: this file is <root>/tests/minimal_init.lua.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:append(root) -- makes require("tcl-lsp.*") resolve

-- Locate plenary.nvim from common plugin-manager install dirs; clone it as a
-- last resort so the suite runs on a machine without it pre-installed.
local function find_plenary()
  local data = vim.fn.stdpath("data")
  for _, p in ipairs({
    data .. "/lazy/plenary.nvim",
    data .. "/plugged/plenary.nvim",
    data .. "/site/pack/packer/start/plenary.nvim",
    root .. "/tests/.deps/plenary.nvim",
  }) do
    if (vim.uv or vim.loop).fs_stat(p) then
      return p
    end
  end
  return nil
end

local plenary = find_plenary()
if not plenary then
  plenary = root .. "/tests/.deps/plenary.nvim"
  vim.fn.system({ "git", "clone", "--depth=1", "https://github.com/nvim-lua/plenary.nvim", plenary })
end
vim.opt.runtimepath:append(plenary)
vim.cmd("runtime plugin/plenary.vim")

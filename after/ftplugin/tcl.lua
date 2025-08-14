-- This file is automatically loaded when opening TCL files

-- Set TCL-specific options
vim.opt_local.expandtab = true
vim.opt_local.shiftwidth = 4
vim.opt_local.tabstop = 4
vim.opt_local.softtabstop = 4

-- Set comment string for commenting plugins
vim.opt_local.commentstring = "# %s"

-- Set up folding for procedures
vim.opt_local.foldmethod = "expr"
vim.opt_local.foldexpr = "v:lua.tcl_fold_expr(v:lnum)"

-- TCL folding function
function _G.tcl_fold_expr(lnum)
	local line = vim.fn.getline(lnum)

	-- Start fold at proc definitions
	if line:match("^%s*proc%s+") then
		return ">1"
	end

	-- Start fold at namespace blocks
	if line:match("^%s*namespace%s+eval%s+") then
		return ">1"
	end

	-- Keep current fold level
	return "="
end

-- TCL-specific text objects (optional)
-- This would require additional setup for custom text objects

-- Auto-pairs for TCL
local pairs = {
	["{"] = "}",
	["["] = "]",
	["("] = ")",
	['"'] = '"',
}

-- Set up some basic auto-pairs if not using a plugin
for open, close in pairs(pairs) do
	vim.keymap.set("i", open, open .. close .. "<left>", { buffer = true, silent = true })
end

-- Helpful abbreviations for common TCL patterns
vim.cmd([[
  iabbrev <buffer> proc proc<space><space>{}<space>{<cr>}<up><end><left><left><left><left>
  iabbrev <buffer> if if<space>{}<space>{<cr>}<up><end><left><left><left>
  iabbrev <buffer> for for<space>{}<space>{}<space>{}<space>{<cr>}<up><end><left><left><left>
  iabbrev <buffer> while while<space>{}<space>{<cr>}<up><end><left><left><left>
  iabbrev <buffer> foreach foreach<space><space>{}<space>{<cr>}<up><end><left><left><left><left><left><left><left>
]])

-- Enhanced syntax highlighting (if needed)
vim.cmd([[
  syntax keyword tclBuiltin dict array string list file glob regexp regsub
  syntax keyword tclBuiltin namespace package source load auto_load
  syntax keyword tclBuiltin info rename eval expr clock
  highlight link tclBuiltin Function
]])

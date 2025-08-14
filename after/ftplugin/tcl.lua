-- This file is automatically loaded when opening TCL files

-- Set TCL-specific options
vim.opt_local.expandtab = true
vim.opt_local.shiftwidth = 4
vim.opt_local.tabstop = 4
vim.opt_local.softtabstop = 4

-- Set comment string for commenting plugins
vim.opt_local.commentstring = "# %s"

-- Define the folding function FIRST, before using it
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

-- NOW set up folding (after the function is defined)
vim.opt_local.foldmethod = "expr"
vim.opt_local.foldexpr = "v:lua.tcl_fold_expr(v:lnum)"

-- Set up basic auto-pairs only if no autopairs plugin is present
local function setup_basic_pairs()
	local has_autopairs = pcall(require, "nvim-autopairs")
		or pcall(require, "mini.pairs")
		or vim.g.loaded_delimitMate
		or vim.g.loaded_lexima

	if not has_autopairs then
		local pairs = {
			["{"] = "}",
			["["] = "]",
			["("] = ")",
		}

		for open, close in pairs(pairs) do
			vim.keymap.set("i", open, open .. close .. "<left>", {
				buffer = true,
				silent = true,
				desc = "TCL auto-pair " .. open .. close,
			})
		end
	end
end

-- Apply the auto-pairs
setup_basic_pairs()

-- Optional: Set up some TCL-specific abbreviations
-- Only if the user hasn't disabled them
if vim.g.tcl_abbreviations ~= false then
	-- Use 't' prefix to avoid conflicts with existing abbreviations
	vim.cmd([[
    iabbrev <buffer> tproc proc<space><space>{}<space>{<cr>}<up><end><left><left><left><left>
    iabbrev <buffer> tif if<space>{}<space>{<cr>}<up><end><left><left><left>
    iabbrev <buffer> tfor for<space>{}<space>{}<space>{}<space>{<cr>}<up><end><left><left><left>
    iabbrev <buffer> twhile while<space>{}<space>{<cr>}<up><end><left><left><left>
    iabbrev <buffer> tforeach foreach<space><space>{}<space>{<cr>}<up><end><left><left><left><left><left><left><left>
  ]])
end

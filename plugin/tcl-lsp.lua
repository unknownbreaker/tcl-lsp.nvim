if vim.g.loaded_tcl_lsp then
	return
end
vim.g.loaded_tcl_lsp = 1

-- Only load if we have nvim 0.8+
if vim.fn.has("nvim-0.8") == 0 then
	vim.api.nvim_err_writeln("tcl-lsp.nvim requires Neovim 0.8+")
	return
end

-- Set up filetype detection early
vim.filetype.add({
	extension = {
		tcl = "tcl",
		rvt = "tcl",
		tk = "tcl",
		itcl = "tcl",
		itk = "tcl",
	},
	pattern = {
		[".*%.rvt%.in"] = "tcl",
	},
})

-- Register health check
vim.health = vim.health or {}
vim.health["tcl-lsp"] = function()
	require("tcl-lsp.health").check()
end

-- Entry point for tcl-lsp.nvim plugin

if vim.g.loaded_tcl_lsp then
	return
end
vim.g.loaded_tcl_lsp = 1

-- Ensure we have the required Neovim version
if vim.fn.has("nvim-0.8") == 0 then
	vim.api.nvim_err_writeln("tcl-lsp.nvim requires Neovim 0.8+")
	return
end

-- Auto-setup for TCL files
vim.api.nvim_create_autocmd("FileType", {
	pattern = "tcl",
	callback = function()
		-- Only setup if not already done
		if not vim.g.tcl_lsp_setup_done then
			require("tcl-lsp").setup()
			vim.g.tcl_lsp_setup_done = true
		end
	end,
	desc = "Auto-setup TCL LSP",
})

-- Create user command for manual setup
vim.api.nvim_create_user_command("TclLspSetup", function()
	require("tcl-lsp").setup()
end, { desc = "Setup TCL LSP manually" })

-- Enhanced filetype detection
vim.filetype.add({
	extension = {
		tcl = "tcl",
		tk = "tcl",
		itcl = "tcl",
		itk = "tcl",
		rvt = "tcl", -- Rivet TCL files
	},
	filename = {
		["tclsh"] = "tcl",
		["wish"] = "tcl",
		[".tclshrc"] = "tcl",
		[".wishrc"] = "tcl",
	},
	pattern = {
		[".*%.tcl%.in"] = "tcl",
		[".*%.tk%.in"] = "tcl",
		[".*%.rvt%.in"] = "tcl", -- Rivet template files
		["^#!.*tclsh"] = "tcl",
		["^#!.*wish"] = "tcl",
		-- Rivet file patterns
		[".*%.rvt"] = "tcl",
	},
})

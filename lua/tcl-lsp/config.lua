local M = {}

M.defaults = {
	-- TCL interpreter settings
	tclsh_cmd = "tclsh",
	syntax_check_on_save = true,
	syntax_check_on_change = false,

	-- Syntax checking mode
	syntax_check_mode = "package_aware", -- Options: "package_aware", "parse_only", "full", "disabled"

	-- Feature toggles
	hover = true,
	diagnostics = true,
	symbol_navigation = true,
	completion = false,

	-- Symbol parsing
	symbol_update_on_change = false,

	-- Diagnostic configuration
	diagnostic_config = {
		virtual_text = true,
		signs = true,
		underline = true,
		update_in_insert = false,
	},

	-- Keymaps (set to false to disable)
	keymaps = {
		hover = "K",
		syntax_check = "<leader>tc",
		goto_definition = "gd",
		find_references = "gr",
		document_symbols = "gO",
		workspace_symbols = "<leader>ts",
	},
}

M.options = {}

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

function M.get()
	return M.options
end

return M

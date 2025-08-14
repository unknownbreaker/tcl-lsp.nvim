-- Configuration management for tcl-lsp.nvim

local M = {}

-- Default configuration
local default_config = {
	-- Feature toggles
	hover = true, -- Enable hover documentation
	diagnostics = true, -- Enable syntax checking
	completion = false, -- Completion (future feature)
	symbol_navigation = true, -- Enable go-to-definition, references, etc.

	-- Diagnostic configuration
	diagnostic_config = {
		virtual_text = true,
		signs = true,
		underline = true,
		update_in_insert = false,
		severity_sort = true,
	},

	-- Symbol parsing settings
	symbol_update_on_change = false, -- Update symbols while typing (can be noisy)

	-- TCL interpreter settings
	tclsh_cmd = "tclsh", -- Command to run TCL interpreter
	syntax_check_on_save = true, -- Check syntax when saving
	syntax_check_on_change = false, -- Check syntax while typing (can be noisy)

	-- LSP settings
	single_file_support = true, -- Support single files
	root_patterns = { ".git", "*.tcl", "pkgIndex.tcl" },

	-- UI settings
	float_config = {
		border = "rounded",
		max_width = 80,
		max_height = 20,
	},

	-- Keymaps
	keymaps = {
		hover = "K", -- Show hover documentation
		syntax_check = "<leader>tc", -- Manual syntax check
		goto_definition = "gd", -- Go to definition
		find_references = "gr", -- Find references
		document_symbols = "gO", -- Document symbols
	},
}

-- Current configuration
local current_config = {}

-- Setup configuration
function M.setup(user_config)
	current_config = vim.tbl_deep_extend("force", default_config, user_config or {})
	return current_config
end

-- Get current configuration
function M.get()
	return current_config
end

-- Get default configuration
function M.get_default()
	return vim.deepcopy(default_config)
end

-- Validate configuration
function M.validate(config)
	local errors = {}

	-- Check required fields
	if type(config.tclsh_cmd) ~= "string" then
		table.insert(errors, "tclsh_cmd must be a string")
	end

	if type(config.hover) ~= "boolean" then
		table.insert(errors, "hover must be a boolean")
	end

	if type(config.diagnostics) ~= "boolean" then
		table.insert(errors, "diagnostics must be a boolean")
	end

	-- Check diagnostic config
	if config.diagnostic_config then
		local valid_keys = { "virtual_text", "signs", "underline", "update_in_insert", "severity_sort" }
		for key, _ in pairs(config.diagnostic_config) do
			if not vim.tbl_contains(valid_keys, key) then
				table.insert(errors, "Invalid diagnostic_config key: " .. key)
			end
		end
	end

	return #errors == 0, errors
end

return M

local M = {}

-- Default configuration
M.default_config = {
	hover = true,
	diagnostics = true,
	symbol_navigation = true,
	completion = false,
	symbol_update_on_change = false,
	diagnostic_config = {
		virtual_text = {
			spacing = 4,
			prefix = "●",
			source = "if_many",
		},
		signs = {
			text = {
				[vim.diagnostic.severity.ERROR] = "✗",
				[vim.diagnostic.severity.WARN] = "▲",
				[vim.diagnostic.severity.HINT] = "⚑",
				[vim.diagnostic.severity.INFO] = "»",
			},
		},
		underline = true,
		update_in_insert = false,
		severity_sort = true,
		float = {
			focusable = false,
			style = "minimal",
			border = "rounded",
			source = "if_many",
			header = "",
			prefix = "",
		},
	},
	tclsh_cmd = "auto", -- Auto-detect the best tclsh
	syntax_check_on_save = true,
	syntax_check_on_change = false,
	keymaps = {
		hover = "K",
		syntax_check = "<leader>tc",
		goto_definition = "gd",
		find_references = "gr",
		document_symbols = "gO",
		workspace_symbols = "<leader>tw",
	},
	-- Auto-setup features
	auto_setup_filetypes = true,
	auto_setup_commands = true,
	auto_setup_autocmds = true,
}

-- Current configuration state
M.config = {}

-- Setup configuration with user overrides
function M.setup(user_config)
	M.config = vim.tbl_deep_extend("force", M.default_config, user_config or {})
	return M.config
end

-- Get current configuration
function M.get()
	return M.config
end

-- Get a specific configuration value with fallback
function M.get_value(key, fallback)
	local value = M.config
	for k in string.gmatch(key, "[^%.]+") do
		if type(value) == "table" and value[k] ~= nil then
			value = value[k]
		else
			return fallback
		end
	end
	return value
end

-- Update a configuration value
function M.set_value(key, new_value)
	local keys = {}
	for k in string.gmatch(key, "[^%.]+") do
		table.insert(keys, k)
	end

	local current = M.config
	for i = 1, #keys - 1 do
		if type(current[keys[i]]) ~= "table" then
			current[keys[i]] = {}
		end
		current = current[keys[i]]
	end

	current[keys[#keys]] = new_value
end

-- Validate configuration
function M.validate()
	local errors = {}

	-- Check required fields
	if not M.config.tclsh_cmd then
		table.insert(errors, "tclsh_cmd is required")
	end

	-- Check boolean fields
	local boolean_fields = {
		"hover",
		"diagnostics",
		"symbol_navigation",
		"completion",
		"symbol_update_on_change",
		"syntax_check_on_save",
		"syntax_check_on_change",
		"auto_setup_filetypes",
		"auto_setup_commands",
		"auto_setup_autocmds",
	}

	for _, field in ipairs(boolean_fields) do
		if M.config[field] ~= nil and type(M.config[field]) ~= "boolean" then
			table.insert(errors, field .. " must be a boolean")
		end
	end

	-- Check keymaps
	if M.config.keymaps and type(M.config.keymaps) ~= "table" then
		table.insert(errors, "keymaps must be a table")
	end

	return #errors == 0, errors
end

-- Export configuration values for easy access
function M.get_tclsh_cmd()
	return M.config.tclsh_cmd
end

function M.get_keymaps()
	return M.config.keymaps or {}
end

function M.get_diagnostic_config()
	return M.config.diagnostic_config or {}
end

function M.is_hover_enabled()
	return M.config.hover == true
end

function M.is_diagnostics_enabled()
	return M.config.diagnostics == true
end

function M.is_symbol_navigation_enabled()
	return M.config.symbol_navigation == true
end

function M.should_syntax_check_on_save()
	return M.config.syntax_check_on_save == true
end

function M.should_syntax_check_on_change()
	return M.config.syntax_check_on_change == true
end

function M.should_auto_setup_filetypes()
	return M.config.auto_setup_filetypes == true
end

function M.should_auto_setup_commands()
	return M.config.auto_setup_commands == true
end

function M.should_auto_setup_autocmds()
	return M.config.auto_setup_autocmds == true
end

return M

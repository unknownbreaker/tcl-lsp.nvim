local M = {}

-- Default configuration
local default_config = {
	server = {
		cmd = nil, -- Auto-detected
		settings = {
			tcl = {
				-- Future: TCL-specific settings
			},
		},
	},
	on_attach = nil,
	capabilities = nil,
	auto_install = {
		tcl = true,
		tcllib = true,
	},
	log_level = vim.log.levels.WARN,
}

-- Current configuration
local current_config = {}

-- Setup configuration
function M.setup(user_config)
	current_config = vim.tbl_deep_extend("force", default_config, user_config or {})
end

-- Get current configuration
function M.get()
	return current_config
end

-- Get default configuration
function M.get_default()
	return vim.deepcopy(default_config)
end

-- Update configuration
function M.update(updates)
	current_config = vim.tbl_deep_extend("force", current_config, updates)
end

return M

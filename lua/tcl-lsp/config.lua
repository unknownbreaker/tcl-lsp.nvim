local M = {}

-- Default configuration with enhanced cross-file support
M.default_config = {
	hover = true,
	diagnostics = true,
	symbol_navigation = true,
	completion = false,
	symbol_update_on_change = false,

	-- Enhanced cross-file analysis options
	cross_file_analysis = {
		enabled = true,
		max_files = 50, -- Limit number of files to analyze for performance
		cache_timeout = 300, -- Cache timeout in seconds
		follow_source_dependencies = true,
		search_common_locations = true,
		index_workspace_symbols = true,
	},

	-- Workspace search configuration
	workspace_search = {
		enabled = true,
		include_patterns = {
			"**/*.tcl",
			"**/*.tk",
			"**/*.itcl",
			"**/*.rvt",
			"lib/**/*.tcl",
			"src/**/*.tcl",
			"scripts/**/*.tcl",
		},
		exclude_patterns = {
			"**/.*", -- Hidden files
			"**/build/**",
			"**/dist/**",
			"**/node_modules/**",
			"**/*.bak",
			"**/*.tmp",
		},
		max_file_size = 1048576, -- 1MB limit
	},

	-- Symbol resolution priorities
	symbol_resolution = {
		prefer_local_file = true,
		namespace_aware = true,
		scope_aware = true,
		fuzzy_matching = false,
		case_sensitive = true,
	},

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
		workspace_definition = "<leader>tg", -- Enhanced workspace goto
		show_workspace_stats = "<leader>ts",
	},
	-- Auto-setup features
	auto_setup_filetypes = true,
	auto_setup_commands = true,
	auto_setup_autocmds = true,

	-- Performance settings
	performance = {
		debounce_delay = 300, -- ms
		max_concurrent_analysis = 3,
		enable_progressive_analysis = true,
	},
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

	-- Check cross-file analysis config
	if M.config.cross_file_analysis then
		local cf_config = M.config.cross_file_analysis
		if cf_config.max_files and type(cf_config.max_files) ~= "number" then
			table.insert(errors, "cross_file_analysis.max_files must be a number")
		end
		if cf_config.cache_timeout and type(cf_config.cache_timeout) ~= "number" then
			table.insert(errors, "cross_file_analysis.cache_timeout must be a number")
		end
	end

	-- Check workspace search config
	if M.config.workspace_search then
		local ws_config = M.config.workspace_search
		if ws_config.include_patterns and type(ws_config.include_patterns) ~= "table" then
			table.insert(errors, "workspace_search.include_patterns must be a table")
		end
		if ws_config.max_file_size and type(ws_config.max_file_size) ~= "number" then
			table.insert(errors, "workspace_search.max_file_size must be a number")
		end
	end

	-- Check keymaps
	if M.config.keymaps and type(M.config.keymaps) ~= "table" then
		table.insert(errors, "keymaps must be a table")
	end

	return #errors == 0, errors
end

-- Enhanced configuration getters
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

-- Cross-file analysis configuration getters
function M.is_cross_file_analysis_enabled()
	return M.get_value("cross_file_analysis.enabled", true)
end

function M.get_cross_file_max_files()
	return M.get_value("cross_file_analysis.max_files", 50)
end

function M.get_cross_file_cache_timeout()
	return M.get_value("cross_file_analysis.cache_timeout", 300)
end

function M.should_follow_source_dependencies()
	return M.get_value("cross_file_analysis.follow_source_dependencies", true)
end

function M.should_search_common_locations()
	return M.get_value("cross_file_analysis.search_common_locations", true)
end

function M.should_index_workspace_symbols()
	return M.get_value("cross_file_analysis.index_workspace_symbols", true)
end

-- Workspace search configuration getters
function M.is_workspace_search_enabled()
	return M.get_value("workspace_search.enabled", true)
end

function M.get_workspace_include_patterns()
	return M.get_value("workspace_search.include_patterns", { "**/*.tcl", "**/*.tk" })
end

function M.get_workspace_exclude_patterns()
	return M.get_value("workspace_search.exclude_patterns", { "**/.*", "**/build/**" })
end

function M.get_workspace_max_file_size()
	return M.get_value("workspace_search.max_file_size", 1048576)
end

-- Symbol resolution configuration getters
function M.should_prefer_local_file()
	return M.get_value("symbol_resolution.prefer_local_file", true)
end

function M.is_namespace_aware()
	return M.get_value("symbol_resolution.namespace_aware", true)
end

function M.is_scope_aware()
	return M.get_value("symbol_resolution.scope_aware", true)
end

function M.is_fuzzy_matching_enabled()
	return M.get_value("symbol_resolution.fuzzy_matching", false)
end

function M.is_case_sensitive()
	return M.get_value("symbol_resolution.case_sensitive", true)
end

-- Performance configuration getters
function M.get_debounce_delay()
	return M.get_value("performance.debounce_delay", 300)
end

function M.get_max_concurrent_analysis()
	return M.get_value("performance.max_concurrent_analysis", 3)
end

function M.is_progressive_analysis_enabled()
	return M.get_value("performance.enable_progressive_analysis", true)
end

-- Helper function to check if a file should be included in workspace analysis
function M.should_include_file(file_path)
	if not file_path then
		return false
	end

	local file_size = vim.fn.getfsize(file_path)
	if file_size > M.get_workspace_max_file_size() then
		return false
	end

	-- Check include patterns
	local include_patterns = M.get_workspace_include_patterns()
	local matches_include = false

	for _, pattern in ipairs(include_patterns) do
		if vim.fn.fnamemodify(file_path, ":t"):match(pattern:gsub("%*", ".*")) then
			matches_include = true
			break
		end
	end

	if not matches_include then
		return false
	end

	-- Check exclude patterns
	local exclude_patterns = M.get_workspace_exclude_patterns()
	for _, pattern in ipairs(exclude_patterns) do
		if file_path:match(pattern:gsub("%*", ".*")) then
			return false
		end
	end

	return true
end

-- Get effective workspace search paths based on configuration
function M.get_workspace_search_paths()
	local patterns = M.get_workspace_include_patterns()
	local all_files = {}

	for _, pattern in ipairs(patterns) do
		local files = vim.fn.glob(pattern, false, true)
		for _, file in ipairs(files) do
			if M.should_include_file(file) and not vim.tbl_contains(all_files, file) then
				table.insert(all_files, file)
			end
		end
	end

	return all_files
end

return M

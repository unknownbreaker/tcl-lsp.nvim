local M = {}

local config = require("tcl-lsp.config")
local server = require("tcl-lsp.server")

-- Default configuration
M.config = {
	-- Server settings
	server = {
		cmd = nil, -- Will be auto-detected
		settings = {
			tcl = {
				-- Future: TCL-specific settings
			},
		},
	},

	-- LSP client settings
	on_attach = nil, -- User can override
	capabilities = nil, -- Will use defaults

	-- Auto-install dependencies
	auto_install = {
		tcl = true, -- Check for tclsh
		tcllib = true, -- Check for JSON package
	},

	-- Logging
	log_level = vim.log.levels.WARN,
}

-- Setup function called by users
function M.setup(user_config)
	-- Merge user config with defaults
	M.config = vim.tbl_deep_extend("force", M.config, user_config or {})

	-- Set up configuration
	config.setup(M.config)

	-- Set up filetype detection
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

	-- Register the LSP server
	server.register()

	-- Set up autocommands
	local augroup = vim.api.nvim_create_augroup("TclLsp", { clear = true })

	vim.api.nvim_create_autocmd("FileType", {
		group = augroup,
		pattern = "tcl",
		callback = function()
			server.start()
		end,
	})

	-- Create user commands
	M.create_commands()

	-- Run health check if requested
	if M.config.auto_install.tcl or M.config.auto_install.tcllib then
		vim.defer_fn(function()
			local health_ok, health_result = pcall(require("tcl-lsp.health").check_silent)
			if not health_ok or not health_result.tcl or not health_result.tcllib then
				vim.notify(
					"TCL LSP: Some dependencies are missing. Run :checkhealth tcl-lsp for details.",
					vim.log.levels.WARN
				)
			end
		end, 1000)
	end
end

-- Create user commands
function M.create_commands()
	vim.api.nvim_create_user_command("TclLspInfo", function()
		server.show_info()
	end, { desc = "Show TCL LSP server information" })

	vim.api.nvim_create_user_command("TclLspRestart", function()
		server.restart()
	end, { desc = "Restart TCL LSP server" })

	vim.api.nvim_create_user_command("TclLspStop", function()
		server.stop()
	end, { desc = "Stop TCL LSP server" })

	vim.api.nvim_create_user_command("TclLspStart", function()
		server.start()
	end, { desc = "Start TCL LSP server" })

	vim.api.nvim_create_user_command("TclLspLog", function()
		vim.cmd("LspLog")
	end, { desc = "Show LSP log" })

	vim.api.nvim_create_user_command("TclLspInstall", function()
		require("tcl-lsp.health").install_dependencies()
	end, { desc = "Install TCL LSP dependencies" })
end

-- Get plugin information
function M.get_info()
	return {
		name = "tcl-lsp.nvim",
		version = "1.0.0",
		server_status = server.get_status(),
		config = M.config,
	}
end

return M

local M = {}

local config = require("tcl-lsp.config")

-- Server state
local server_config = nil
local client_id = nil

-- Get the path to the TCL LSP server script
function M.get_server_path()
	local plugin_path = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or ""
	local server_path = plugin_path .. "../../bin/tcl-lsp-server.tcl"

	-- Resolve the path
	server_path = vim.fn.resolve(server_path)

	if vim.fn.filereadable(server_path) == 1 then
		return server_path
	end

	-- Fallback: try relative to plugin directory
	local rtp_paths = vim.api.nvim_list_runtime_paths()
	for _, rtp in ipairs(rtp_paths) do
		local candidate = rtp .. "/bin/tcl-lsp-server.tcl"
		if vim.fn.filereadable(candidate) == 1 then
			return candidate
		end
	end

	-- Last resort: check if user has it in config
	local config_path = vim.fn.stdpath("config") .. "/tcl-lsp-server.tcl"
	if vim.fn.filereadable(config_path) == 1 then
		return config_path
	end

	return nil
end

-- Check if dependencies are available
function M.check_dependencies()
	local issues = {}

	-- Check tclsh
	if vim.fn.executable("tclsh") == 0 then
		table.insert(issues, "tclsh is not installed or not in PATH")
	end

	-- Check TCL JSON package
	local json_check = vim.fn.system('tclsh -c "package require json; puts OK" 2>&1')
	if not json_check:match("OK") then
		table.insert(issues, "TCL JSON package (tcllib) is not available")
	end

	-- Check server script
	local server_path = M.get_server_path()
	if not server_path then
		table.insert(issues, "TCL LSP server script not found")
	elseif vim.fn.executable(server_path) == 0 then
		table.insert(issues, "TCL LSP server script is not executable")
	end

	return #issues == 0, issues
end

-- Register the LSP server configuration
function M.register()
	local lspconfig = require("lspconfig")
	local configs = require("lspconfig.configs")

	-- Only register if not already registered
	if configs.tcl_lsp then
		return
	end

	local server_path = M.get_server_path()
	if not server_path then
		vim.notify("TCL LSP: Server script not found. Run :TclLspInstall", vim.log.levels.ERROR)
		return
	end

	-- Register the server configuration
	configs.tcl_lsp = {
		default_config = {
			cmd = { "tclsh", server_path },
			filetypes = { "tcl" },
			root_dir = function(fname)
				return lspconfig.util.root_pattern(".git", "tclIndex", "pkgIndex.tcl", "Makefile", "*.tcl")(fname)
					or lspconfig.util.path.dirname(fname)
			end,
			settings = config.get().server.settings or {},
			single_file_support = true,
			name = "tcl_lsp",
			log_level = config.get().log_level,
		},
	}

	server_config = configs.tcl_lsp.default_config
end

-- Start the LSP server
function M.start()
	if client_id then
		-- Already running
		return
	end

	local deps_ok, issues = M.check_dependencies()
	if not deps_ok then
		vim.notify(
			"TCL LSP: Dependencies missing:\n" .. table.concat(issues, "\n") .. "\n\nRun :checkhealth tcl-lsp",
			vim.log.levels.ERROR
		)
		return
	end

	local lspconfig = require("lspconfig")

	-- Custom on_attach function
	local function on_attach(client, bufnr)
		-- Call user's on_attach if provided
		local user_on_attach = config.get().on_attach
		if user_on_attach then
			user_on_attach(client, bufnr)
		end

		-- Set up default keymaps
		local opts = { buffer = bufnr, silent = true }

		vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
		vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
		vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts)
		vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
		vim.keymap.set("n", "gi", vim.lsp.buf.implementation, opts)
		vim.keymap.set("n", "gt", vim.lsp.buf.type_definition, opts)
		vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
		vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
		vim.keymap.set("n", "gO", vim.lsp.buf.document_symbol, opts)
		vim.keymap.set("n", "<leader>ws", vim.lsp.buf.workspace_symbol, opts)

		-- TCL-specific keymaps
		vim.keymap.set("n", "<leader>tc", function()
			-- Manual syntax check - for now just trigger hover
			vim.lsp.buf.hover()
		end, opts)

		client_id = client.id

		vim.notify("TCL LSP server started", vim.log.levels.INFO)
	end

	-- Start the LSP server
	lspconfig.tcl_lsp.setup({
		on_attach = on_attach,
		capabilities = config.get().capabilities or vim.lsp.protocol.make_client_capabilities(),
		settings = config.get().server.settings,
		cmd = server_config.cmd,
		root_dir = server_config.root_dir,
		filetypes = server_config.filetypes,
		single_file_support = server_config.single_file_support,
	})
end

-- Stop the LSP server
function M.stop()
	if client_id then
		vim.lsp.stop_client(client_id)
		client_id = nil
		vim.notify("TCL LSP server stopped", vim.log.levels.INFO)
	else
		vim.notify("TCL LSP server is not running", vim.log.levels.WARN)
	end
end

-- Restart the LSP server
function M.restart()
	M.stop()
	vim.defer_fn(function()
		M.start()
	end, 1000)
end

-- Get server status
function M.get_status()
	if not client_id then
		return { running = false, client_id = nil }
	end

	local client = vim.lsp.get_client_by_id(client_id)
	if not client then
		client_id = nil
		return { running = false, client_id = nil }
	end

	return {
		running = true,
		client_id = client_id,
		name = client.name,
		attached_buffers = client.attached_buffers,
		server_capabilities = client.server_capabilities,
	}
end

-- Show server information
function M.show_info()
	local status = M.get_status()
	local server_path = M.get_server_path()
	local deps_ok, issues = M.check_dependencies()

	print("=== TCL LSP Server Information ===")
	print("Server path: " .. (server_path or "NOT FOUND"))
	print("Running: " .. (status.running and "YES" or "NO"))

	if status.running then
		print("Client ID: " .. status.client_id)
		print("Attached buffers: " .. #vim.tbl_keys(status.attached_buffers))
	end

	print("\nDependencies:")
	if deps_ok then
		print("✅ All dependencies OK")
	else
		print("❌ Issues found:")
		for _, issue in ipairs(issues) do
			print("  - " .. issue)
		end
	end

	print("\nCommands:")
	print("  :TclLspStart    - Start server")
	print("  :TclLspStop     - Stop server")
	print("  :TclLspRestart  - Restart server")
	print("  :TclLspLog      - View logs")
	print("  :LspInfo        - General LSP info")
	print("  :checkhealth tcl-lsp - Health check")
end

return M

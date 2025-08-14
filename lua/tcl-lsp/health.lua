local M = {}

local health = vim.health

-- Check if a command is available
local function check_command(cmd, name)
	if vim.fn.executable(cmd) == 1 then
		health.ok(name .. " is installed: " .. vim.fn.exepath(cmd))
		return true
	else
		health.error(name .. " is not installed or not in PATH")
		return false
	end
end

-- Check TCL JSON package
local function check_tcl_json()
	local result = vim.fn.system('tclsh -c "package require json; puts OK" 2>&1')
	if result:match("OK") then
		health.ok("TCL JSON package is available")
		return true
	else
		health.error("TCL JSON package is not available")
		health.info("Install with: brew install tcllib (macOS) or sudo apt-get install tcllib (Ubuntu)")
		return false
	end
end

-- Check server script
local function check_server_script()
	local server = require("tcl-lsp.server")
	local server_path = server.get_server_path()

	if server_path then
		if vim.fn.filereadable(server_path) == 1 then
			health.ok("TCL LSP server script found: " .. server_path)

			if vim.fn.executable(server_path) == 1 then
				health.ok("Server script is executable")
				return true
			else
				health.warn("Server script is not executable. Run: chmod +x " .. server_path)
				return false
			end
		else
			health.error("Server script is not readable: " .. server_path)
			return false
		end
	else
		health.error("TCL LSP server script not found")
		health.info("Expected locations:")
		health.info("  - Plugin bin/tcl-lsp-server.tcl")
		health.info("  - ~/.config/nvim/tcl-lsp-server.tcl")
		return false
	end
end

-- Check LSP configuration
local function check_lsp_config()
	local has_lspconfig, _ = pcall(require, "lspconfig")
	if has_lspconfig then
		health.ok("nvim-lspconfig is available")

		local configs = require("lspconfig.configs")
		if configs.tcl_lsp then
			health.ok("TCL LSP server is registered with lspconfig")
		else
			health.warn("TCL LSP server is not yet registered (will register on first TCL file)")
		end

		return true
	else
		health.error("nvim-lspconfig is not available")
		health.info("Install with your plugin manager")
		return false
	end
end

-- Check if server is running
local function check_server_status()
	local server = require("tcl-lsp.server")
	local status = server.get_status()

	if status.running then
		health.ok("TCL LSP server is running (client ID: " .. status.client_id .. ")")
		health.info("Attached to " .. #vim.tbl_keys(status.attached_buffers) .. " buffer(s)")
	else
		health.info("TCL LSP server is not currently running")
		health.info("It will start automatically when you open a TCL file")
	end
end

-- Main health check function
function M.check()
	health.start("TCL LSP Dependencies")

	local tcl_ok = check_command("tclsh", "tclsh")
	local json_ok = tcl_ok and check_tcl_json()
	local server_ok = check_server_script()
	local lsp_ok = check_lsp_config()

	health.start("TCL LSP Server Status")
	check_server_status()

	health.start("Installation Guide")

	if not tcl_ok then
		health.info("To install TCL:")
		health.info("  macOS:   brew install tcl-tk")
		health.info("  Ubuntu:  sudo apt-get install tcl")
		health.info("  CentOS:  sudo yum install tcl")
	end

	if not json_ok then
		health.info("To install TCL JSON package:")
		health.info("  macOS:   brew install tcllib")
		health.info("  Ubuntu:  sudo apt-get install tcllib")
		health.info("  CentOS:  sudo yum install tcllib")
	end

	if not server_ok then
		health.info("The server script should be included with the plugin.")
		health.info("If missing, check your plugin installation.")
	end

	if not lsp_ok then
		health.info("Install nvim-lspconfig with your plugin manager:")
		health.info("  { 'neovim/nvim-lspconfig' }")
	end

	local all_ok = tcl_ok and json_ok and server_ok and lsp_ok

	if all_ok then
		health.start("✅ All Good!")
		health.ok("TCL LSP is ready to use")
		health.info("Open a .tcl file to start the language server")
	else
		health.start("❌ Issues Found")
		health.error("Some dependencies are missing")
		health.info("Run :TclLspInstall to try automatic installation")
	end
end

-- Silent check for internal use
function M.check_silent()
	local tcl_ok = vim.fn.executable("tclsh") == 1
	local json_ok = false
	local server_ok = false
	local lsp_ok = false

	if tcl_ok then
		local result = vim.fn.system('tclsh -c "package require json; puts OK" 2>&1')
		json_ok = result:match("OK") ~= nil
	end

	local server = require("tcl-lsp.server")
	local server_path = server.get_server_path()
	server_ok = server_path and vim.fn.filereadable(server_path) == 1

	lsp_ok = pcall(require, "lspconfig")

	return {
		tcl = tcl_ok,
		tcllib = json_ok,
		server = server_ok,
		lspconfig = lsp_ok,
		all_ok = tcl_ok and json_ok and server_ok and lsp_ok,
	}
end

-- Attempt to install dependencies
function M.install_dependencies()
	vim.notify("Attempting to install TCL LSP dependencies...", vim.log.levels.INFO)

	local function run_command(cmd, description)
		vim.notify("Running: " .. description, vim.log.levels.INFO)
		local result = vim.fn.system(cmd)
		local success = vim.v.shell_error == 0

		if success then
			vim.notify("✅ " .. description .. " completed", vim.log.levels.INFO)
		else
			vim.notify("❌ " .. description .. " failed: " .. result, vim.log.levels.ERROR)
		end

		return success
	end

	-- Detect OS and try to install
	local os_type = vim.fn.has("mac") == 1 and "mac" or "linux"

	if os_type == "mac" then
		if vim.fn.executable("brew") == 1 then
			run_command("brew install tcl-tk tcllib", "Installing TCL and tcllib via Homebrew")
		else
			vim.notify("Homebrew not found. Please install TCL manually.", vim.log.levels.WARN)
		end
	else
		-- Try different Linux package managers
		if vim.fn.executable("apt-get") == 1 then
			run_command("sudo apt-get update && sudo apt-get install -y tcl tcllib", "Installing TCL via apt")
		elseif vim.fn.executable("yum") == 1 then
			run_command("sudo yum install -y tcl tcllib", "Installing TCL via yum")
		elseif vim.fn.executable("dnf") == 1 then
			run_command("sudo dnf install -y tcl tcllib", "Installing TCL via dnf")
		else
			vim.notify("No supported package manager found. Please install TCL manually.", vim.log.levels.WARN)
		end
	end

	-- Re-run health check
	vim.defer_fn(function()
		vim.cmd("checkhealth tcl-lsp")
	end, 2000)
end

return M

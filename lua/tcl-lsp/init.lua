-- Main entry point for tcl-lsp.nvim

local M = {}

-- Import submodules
local config = require("tcl-lsp.config")
local handlers = require("tcl-lsp.handlers")
local diagnostics = require("tcl-lsp.diagnostics")

-- Plugin state
local is_setup = false

-- Setup function
function M.setup(user_config)
	-- Prevent multiple setups
	if is_setup then
		return
	end

	-- Merge user config with defaults
	local opts = config.setup(user_config or {})

	-- Check requirements
	if vim.fn.executable("tclsh") == 0 then
		vim.notify("tcl-lsp.nvim: tclsh not found in PATH. Syntax checking will be disabled.", vim.log.levels.WARN)
		opts.diagnostics = false
	end

	-- Check for lspconfig
	local lspconfig_ok, lspconfig = pcall(require, "lspconfig")
	if not lspconfig_ok then
		vim.notify(
			"tcl-lsp.nvim: nvim-lspconfig not found. Please install neovim/nvim-lspconfig.",
			vim.log.levels.ERROR
		)
		return
	end

	-- Setup LSP configuration
	local configs = require("lspconfig.configs")

	if not configs.tcl_lsp then
		configs.tcl_lsp = {
			default_config = {
				name = "tcl_lsp",
				cmd = { "tcl-lsp-dummy" }, -- Dummy command, we handle everything in on_attach
				filetypes = { "tcl" },
				root_dir = function(fname)
					local util = require("lspconfig.util")
					return util.root_pattern(".git", "*.tcl", "pkgIndex.tcl")(fname)
						or util.find_git_ancestor(fname)
						or vim.fn.getcwd()
				end,
				single_file_support = true,
				init_options = {},
				settings = {},
				capabilities = {
					textDocumentSync = vim.lsp.protocol.TextDocumentSyncKind.Full,
					hoverProvider = opts.hover,
					definitionProvider = opts.symbol_navigation,
					referencesProvider = opts.symbol_navigation,
					documentSymbolProvider = opts.symbol_navigation,
					workspaceSymbolProvider = opts.symbol_navigation,
					completionProvider = opts.completion and {
						triggerCharacters = { ".", ":" },
					} or nil,
				},
			},
			docs = {
				description = [[
TCL Language Server implemented in pure Lua for Neovim.

Features:
- Hover documentation for TCL commands
- Go to definition for procedures and variables
- Find references across workspace  
- Document and workspace symbols
- Syntax checking via tclsh  
- Integrated diagnostics
- No external dependencies

Repository: https://github.com/YOUR_USERNAME/tcl-lsp.nvim
        ]],
			},
		}
	end

	-- Setup the LSP with our custom handlers
	lspconfig.tcl_lsp.setup({
		on_attach = function(client, bufnr)
			handlers.setup_buffer(client, bufnr, opts)
		end,
		capabilities = vim.lsp.protocol.make_client_capabilities(),
	})

	-- Setup diagnostics
	if opts.diagnostics then
		diagnostics.setup(opts.diagnostic_config)
	end

	-- Mark as setup
	is_setup = true

	vim.notify("tcl-lsp.nvim: Setup complete", vim.log.levels.INFO)
end

-- Get current configuration
function M.get_config()
	return config.get()
end

-- Health check function
function M.health()
	local health = vim.health or require("health")

	health.report_start("tcl-lsp.nvim")

	-- Check Neovim version
	if vim.fn.has("nvim-0.8") == 1 then
		health.report_ok("Neovim version >= 0.8")
	else
		health.report_error("Neovim version < 0.8", "Please upgrade to Neovim 0.8+")
	end

	-- Check tclsh
	if vim.fn.executable("tclsh") == 1 then
		local handle = io.popen('tclsh -c "puts $tcl_version"')
		local version = handle and handle:read("*a"):gsub("\n", "") or "unknown"
		if handle then
			handle:close()
		end
		health.report_ok("tclsh available (version: " .. version .. ")")
	else
		health.report_warn("tclsh not found in PATH", "Syntax checking will be disabled")
	end

	-- Check lspconfig
	if pcall(require, "lspconfig") then
		health.report_ok("nvim-lspconfig available")
	else
		health.report_error("nvim-lspconfig not found", "Please install neovim/nvim-lspconfig")
	end

	-- Check setup status
	if is_setup then
		health.report_ok("tcl-lsp.nvim is set up")
	else
		health.report_warn("tcl-lsp.nvim not set up", 'Run :lua require("tcl-lsp").setup()')
	end
end

return M

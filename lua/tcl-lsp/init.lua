local M = {}

local config = require("tcl-lsp.config")
local utils = require("tcl-lsp.utils")

-- Plugin state
local attached_buffers = {}
local namespace_id = vim.api.nvim_create_namespace("tcl-lsp")

function M.setup(opts)
	-- Setup configuration
	config.setup(opts)
	local cfg = config.get()

	-- Check if tclsh is available
	local tclsh_ok, tclsh_error = utils.check_tclsh(cfg.tclsh_cmd)
	if not tclsh_ok then
		vim.notify("TCL LSP: " .. tclsh_error, vim.log.levels.WARN)
	end

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

	-- Set up autocommands
	local augroup = vim.api.nvim_create_augroup("TclLsp", { clear = true })

	-- Attach to TCL buffers
	vim.api.nvim_create_autocmd("FileType", {
		group = augroup,
		pattern = "tcl",
		callback = function(ev)
			M.attach_buffer(ev.buf)
		end,
	})

	-- Syntax check on save
	if cfg.syntax_check_on_save then
		vim.api.nvim_create_autocmd("BufWritePost", {
			group = augroup,
			pattern = { "*.tcl", "*.rvt", "*.tk", "*.itcl", "*.itk" },
			callback = function(ev)
				M.check_syntax(ev.buf)
			end,
		})
	end

	-- Update symbols on change (if enabled)
	if cfg.symbol_update_on_change then
		local debounced_update = utils.debounce(function(bufnr)
			M.update_symbols(bufnr)
		end, 500)

		vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
			group = augroup,
			pattern = { "*.tcl", "*.rvt", "*.tk", "*.itcl", "*.itk" },
			callback = function(ev)
				debounced_update(ev.buf)
			end,
		})
	end

	-- Commands
	vim.api.nvim_create_user_command("TclCheck", function()
		M.check_syntax(0)
	end, { desc = "Check TCL syntax using tclsh" })

	vim.api.nvim_create_user_command("TclSymbols", function()
		M.show_document_symbols(0)
	end, { desc = "Show document symbols" })

	vim.api.nvim_create_user_command("TclWorkspaceSymbols", function(cmd)
		M.show_workspace_symbols(cmd.args)
	end, { nargs = "?", desc = "Search workspace symbols" })

	vim.api.nvim_create_user_command("TclClearCache", function()
		require("tcl-lsp.parser").clear_cache()
		utils.cache_clear()
		vim.notify("TCL LSP cache cleared", vim.log.levels.INFO)
	end, { desc = "Clear TCL LSP cache" })
end

function M.attach_buffer(bufnr)
	if attached_buffers[bufnr] then
		return -- Already attached
	end

	attached_buffers[bufnr] = true
	local cfg = config.get()

	-- Set up keymaps
	if cfg.keymaps then
		if cfg.keymaps.hover then
			vim.keymap.set("n", cfg.keymaps.hover, function()
				M.hover()
			end, { buffer = bufnr, desc = "TCL hover documentation" })
		end

		if cfg.keymaps.goto_definition then
			vim.keymap.set("n", cfg.keymaps.goto_definition, function()
				M.goto_definition()
			end, { buffer = bufnr, desc = "TCL go to definition" })
		end

		if cfg.keymaps.find_references then
			vim.keymap.set("n", cfg.keymaps.find_references, function()
				M.find_references()
			end, { buffer = bufnr, desc = "TCL find references" })
		end

		if cfg.keymaps.document_symbols then
			vim.keymap.set("n", cfg.keymaps.document_symbols, function()
				M.show_document_symbols(bufnr)
			end, { buffer = bufnr, desc = "TCL document symbols" })
		end

		if cfg.keymaps.workspace_symbols then
			vim.keymap.set("n", cfg.keymaps.workspace_symbols, function()
				M.show_workspace_symbols()
			end, { buffer = bufnr, desc = "TCL workspace symbols" })
		end

		if cfg.keymaps.syntax_check then
			vim.keymap.set("n", cfg.keymaps.syntax_check, function()
				M.check_syntax(bufnr)
			end, { buffer = bufnr, desc = "TCL syntax check" })
		end
	end

	-- Initial symbol parse and diagnostics
	if cfg.diagnostics then
		M.update_symbols(bufnr)
	end

	-- Clean up on buffer delete
	vim.api.nvim_create_autocmd("BufDelete", {
		buffer = bufnr,
		callback = function()
			attached_buffers[bufnr] = nil
		end,
	})
end

function M.hover()
	local params = {
		textDocument = { uri = vim.uri_from_bufnr(0) },
		position = utils.get_lsp_position(),
	}

	local result = require("tcl-lsp.handlers.hover").handle(params)
	if result and result.contents then
		local lines = vim.split(result.contents.value, "\n")
		vim.lsp.util.open_floating_preview(lines, "markdown", {
			border = "rounded",
			focusable = false,
		})
	else
		vim.notify("No hover information available", vim.log.levels.INFO)
	end
end

function M.goto_definition()
	local params = {
		textDocument = { uri = vim.uri_from_bufnr(0) },
		position = utils.get_lsp_position(),
	}

	local result = require("tcl-lsp.handlers.definition").handle(params)
	if result then
		local filepath = utils.uri_to_path(result.uri)
		local line = result.range.start.line + 1
		local col = result.range.start.character

		vim.cmd(string.format("edit +%d %s", line, filepath))
		vim.api.nvim_win_set_cursor(0, { line, col })
	else
		vim.notify("Definition not found", vim.log.levels.INFO)
	end
end

function M.find_references()
	local params = {
		textDocument = { uri = vim.uri_from_bufnr(0) },
		position = utils.get_lsp_position(),
		context = { includeDeclaration = true },
	}

	local results = require("tcl-lsp.handlers.references").handle(params)
	if results and #results > 0 then
		local qflist = {}
		for _, ref in ipairs(results) do
			local filepath = utils.uri_to_path(ref.uri)
			local line = ref.range.start.line + 1
			local col = ref.range.start.character + 1

			table.insert(qflist, {
				filename = filepath,
				lnum = line,
				col = col,
				text = string.format("Reference at line %d", line),
			})
		end

		vim.fn.setqflist(qflist)
		vim.cmd("copen")
	else
		vim.notify("No references found", vim.log.levels.INFO)
	end
end

function M.show_document_symbols(bufnr)
	bufnr = bufnr or 0
	local params = {
		textDocument = { uri = vim.uri_from_bufnr(bufnr) },
	}

	local results = require("tcl-lsp.handlers.document_symbol").handle(params)
	if results and #results > 0 then
		local qflist = {}
		for _, symbol in ipairs(results) do
			local line = symbol.range.start.line + 1
			local col = symbol.range.start.character + 1

			table.insert(qflist, {
				bufnr = bufnr,
				lnum = line,
				col = col,
				text = string.format(
					"[%s] %s",
					symbol.kind == 12 and "Function"
						or symbol.kind == 13 and "Variable"
						or symbol.kind == 3 and "Namespace"
						or symbol.kind == 4 and "Package"
						or "Symbol",
					symbol.name
				),
			})
		end

		vim.fn.setqflist(qflist)
		vim.cmd("copen")
	else
		vim.notify("No symbols found in document", vim.log.levels.INFO)
	end
end

function M.show_workspace_symbols(query)
	query = query or vim.fn.input("Symbol search: ")
	if query == "" then
		return
	end

	local workspace = require("tcl-lsp.workspace")
	local all_symbols = workspace.get_all_symbols()

	local matches = {}
	query = query:lower()

	for _, symbol in ipairs(all_symbols) do
		if symbol.name:lower():find(query, 1, true) then
			table.insert(matches, symbol)
		end
	end

	if #matches > 0 then
		local qflist = {}
		for _, symbol in ipairs(matches) do
			table.insert(qflist, {
				filename = symbol.file,
				lnum = symbol.line,
				col = symbol.col,
				text = string.format("[%s] %s", symbol.type, symbol.name),
			})
		end

		vim.fn.setqflist(qflist)
		vim.cmd("copen")
	else
		vim.notify(string.format('No symbols found matching "%s"', query), vim.log.levels.INFO)
	end
end

function M.check_syntax(bufnr)
	bufnr = bufnr or 0
	local filepath = vim.api.nvim_buf_get_name(bufnr)

	if filepath == "" then
		vim.notify("Buffer has no file", vim.log.levels.WARN)
		return
	end

	local parser = require("tcl-lsp.parser")
	local cfg = config.get()
	local errors = parser.check_syntax_with_tclsh(filepath, cfg.tclsh_cmd)

	if #errors == 0 then
		vim.notify("TCL syntax OK", vim.log.levels.INFO)
		-- Clear any existing diagnostics
		vim.diagnostic.set(namespace_id, bufnr, {})
	else
		vim.notify("TCL syntax errors found", vim.log.levels.ERROR)
		M.set_diagnostics(bufnr, errors)

		-- Jump to first error
		if errors[1] then
			vim.api.nvim_win_set_cursor(0, { errors[1].line, errors[1].col - 1 })
		end
	end
end

function M.update_symbols(bufnr)
	bufnr = bufnr or 0
	local filepath = vim.api.nvim_buf_get_name(bufnr)

	if filepath == "" then
		return
	end

	local parser = require("tcl-lsp.parser")
	local symbols = parser.parse_file(filepath)

	local cfg = config.get()
	if cfg.diagnostics and symbols.errors then
		M.set_diagnostics(bufnr, symbols.errors)
	end
end

function M.set_diagnostics(bufnr, errors)
	local diagnostics = {}

	for _, error in ipairs(errors) do
		table.insert(diagnostics, {
			lnum = error.line - 1, -- 0-indexed
			col = error.col - 1, -- 0-indexed
			end_col = error.col + 10, -- Rough estimate
			severity = error.severity or vim.diagnostic.severity.ERROR,
			message = error.message,
			source = error.source or "tcl-lsp",
		})
	end

	vim.diagnostic.set(namespace_id, bufnr, diagnostics)
end

return M

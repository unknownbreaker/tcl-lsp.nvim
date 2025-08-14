-- Knows about built-in TCL commands and won't jump to variables with the same name

local M = {}
local utils = require("tcl-lsp.utils")

-- List of built-in TCL commands that should NOT jump to variable definitions
local builtin_commands = {
	-- Core commands
	"puts",
	"set",
	"unset",
	"proc",
	"return",
	"if",
	"else",
	"elseif",
	"for",
	"while",
	"foreach",
	"break",
	"continue",
	"switch",
	"catch",
	"error",
	"eval",
	"expr",
	"incr",
	"append",

	-- String commands
	"string",
	"format",
	"scan",
	"binary",
	"encoding",

	-- List commands
	"list",
	"lappend",
	"linsert",
	"lreplace",
	"lset",
	"lassign",
	"lindex",
	"llength",
	"lrange",
	"lsearch",
	"lsort",
	"split",
	"join",
	"concat",

	-- Array and dict commands
	"array",
	"dict",
	"parray",

	-- Variable commands
	"global",
	"variable",
	"upvar",
	"uplevel",

	-- Control and info
	"info",
	"rename",
	"namespace",
	"package",
	"source",
	"load",
	"auto_load",

	-- File and I/O
	"file",
	"glob",
	"pwd",
	"cd",
	"open",
	"close",
	"read",
	"gets",
	"puts",
	"seek",
	"tell",
	"eof",
	"flush",
	"fconfigure",
	"fcopy",
	"chan",
	"socket",

	-- Process and system
	"exec",
	"pid",
	"exit",
	"time",
	"after",
	"update",
	"vwait",

	-- Regular expressions
	"regexp",
	"regsub",

	-- Math
	"clock",
	"expr",

	-- Tk commands (if applicable)
	"wm",
	"bind",
	"event",
	"focus",
	"grab",
	"selection",
	"clipboard",
	"font",
	"image",
	"option",
	"pack",
	"grid",
	"place",
	"destroy",
	"winfo",
	"tk",
	"tkwait",

	-- Common widgets
	"button",
	"label",
	"entry",
	"text",
	"listbox",
	"frame",
	"toplevel",
	"canvas",
	"scrollbar",
	"scale",
	"menubutton",
	"menu",
	"checkbutton",
	"radiobutton",
}

-- Convert to a set for faster lookup
local builtin_set = {}
for _, cmd in ipairs(builtin_commands) do
	builtin_set[cmd] = true
end

-- Check if a word is likely being used as a command vs a variable
function M.is_command_usage(line, word_start_pos)
	-- Get the context around the word
	local before_word = line:sub(1, word_start_pos - 1)
	local trimmed_before = before_word:match("^%s*(.-)%s*$")

	-- If the word is at the start of a line (after whitespace), it's likely a command
	if trimmed_before == "" then
		return true
	end

	-- If it's after certain characters, it's likely a command
	if trimmed_before:match("[{;}]%s*$") then
		return true
	end

	-- If it's after a pipe or inside command substitution, it's likely a command
	if trimmed_before:match("|%s*$") or trimmed_before:match("%[%s*$") then
		return true
	end

	-- If it's after 'if', 'while', 'for', etc., might be a command
	if trimmed_before:match("%s(if|while|for|foreach)%s+.*$") then
		return true
	end

	-- Otherwise, assume it's being used as a variable/argument
	return false
end

function M.handle(params)
	local uri = params.textDocument.uri
	local position = params.position

	local filepath = utils.uri_to_path(uri)
	local bufnr = vim.uri_to_bufnr(uri)

	-- Safely get buffer lines
	local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, 0, -1, false)
	if not ok or not lines then
		return nil
	end

	local line = lines[position.line + 1] or ""
	local word = utils.get_word_at_position(line, position.character)

	if not word then
		return nil
	end

	-- Check if this is a built-in command
	if builtin_set[word] then
		-- Determine if it's being used as a command or variable
		local word_start = line:find(word, 1, true)
		local is_command = M.is_command_usage(line, word_start or position.character)

		if is_command then
			-- Don't jump anywhere for built-in commands - they're built-in!
			vim.notify(
				string.format("'%s' is a built-in TCL command. Press K for documentation.", word),
				vim.log.levels.INFO
			)
			return nil
		end
	end

	-- Find definition in workspace
	local workspace_ok, workspace = pcall(require, "tcl-lsp.workspace")
	if not workspace_ok then
		return nil
	end

	local definition_ok, definition = pcall(workspace.find_definition, word, filepath)
	if not definition_ok or not definition then
		return nil
	end

	-- If we found a variable definition but the word is a built-in command,
	-- check the context to see if we should ignore the variable
	if definition.type == "variable" and builtin_set[word] then
		local word_start = line:find(word, 1, true)
		local is_command = M.is_command_usage(line, word_start or position.character)

		if is_command then
			vim.notify(
				string.format(
					"'%s' appears to be used as a command here, not the variable defined at %s:%d",
					word,
					definition.file,
					definition.line
				),
				vim.log.levels.INFO
			)
			return nil
		end
	end

	-- For procedures, find the exact line to avoid jumping to comments
	local target_line = definition.line
	if definition.type == "procedure" then
		local parser = require("tcl-lsp.parser")
		target_line = parser.find_exact_definition_line(definition.file, definition.name, definition.line)
	end

	return {
		uri = utils.path_to_uri(definition.file),
		range = {
			start = { line = target_line - 1, character = 0 },
			["end"] = { line = target_line - 1, character = 0 },
		},
	}
end

return M

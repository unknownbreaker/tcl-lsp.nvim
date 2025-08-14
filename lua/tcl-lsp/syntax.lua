local M = {}

function M.check_syntax(filepath)
	local cmd = string.format('tclsh -c "source %s" 2>&1', vim.fn.shellescape(filepath))
	local output = vim.fn.system(cmd)
	local success = vim.v.shell_error == 0

	return {
		success = success,
		output = output,
		errors = success and {} or M.parse_errors(output),
	}
end

function M.parse_errors(output)
	local errors = {}
	for line in output:gmatch("[^\r\n]+") do
		local line_num = line:match("line (%d+)")
		if line_num then
			table.insert(errors, {
				line = tonumber(line_num),
				message = line,
				severity = vim.diagnostic.severity.ERROR,
			})
		end
	end
	return errors
end

return M

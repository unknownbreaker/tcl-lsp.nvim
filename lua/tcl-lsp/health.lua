local utils = require("tcl-lsp.utils")
local health = vim.health or require("health")

local M = {}

-- Check if a tclsh command works
local function check_tclsh(tclsh_cmd, callback)
	local test_script = [[
puts "VERSION:[info patchlevel]"
puts "EXECUTABLE:[info nameofexecutable]"
]]

	utils.execute_tcl_script_async(test_script, tclsh_cmd, function(result, success)
		if result and success then
			local version = result:match("VERSION:([^\n]+)")
			local executable = result:match("EXECUTABLE:([^\n]+)")
			callback(true, version, executable)
		end
		callback(false, result)
	end)
end

-- Check tcllib availability
local function check_tcllib(tclsh_cmd)
	local test_script = [[
if {[catch {package require json} err]} {
    puts "ERROR:$err"
    exit 1
} else {
    puts "SUCCESS"
    puts "VERSION:[package provide json]"
}
]]

	local result, success = utils.execute_tcl_script(test_script, tclsh_cmd)
	if result and success and result:match("SUCCESS") then
		local version = result:match("VERSION:([^\n]+)")
		return true, version
	else
		local error = result and result:match("ERROR:([^\n]+)") or "Unknown error"
		return false, error
	end
end

-- Main health check function
function M.check()
	health.start("TCL LSP Health Check")

	-- List of Tcl commands to check
	local tclsh_candidates = {
		"tclsh",
		"tclsh8.6",
		"tclsh8.5",
		"/opt/homebrew/bin/tclsh8.6",
		"/opt/homebrew/Cellar/tcl-tk@8/8.6.16/bin/tclsh8.6",
		"/opt/local/bin/tclsh",
		"/usr/local/bin/tclsh",
		"/usr/bin/tclsh",
	}

	local working_tclsh = {}
	local best_tclsh = nil

	-- Test each Tcl installation
	for _, tclsh_cmd in ipairs(tclsh_candidates) do
		-- Check if command exists
		local exists = os.execute("command -v " .. tclsh_cmd .. " >/dev/null 2>&1") == 0

		if exists then
			local works, version, executable = check_tclsh(tclsh_cmd)

			if works then
				health.ok(string.format("%s found (version: %s)", tclsh_cmd, version or "unknown"))

				-- Check tcllib for this installation
				local has_tcllib, tcllib_info = check_tcllib(tclsh_cmd)

				if has_tcllib then
					health.ok(string.format("  ✅ tcllib JSON package available (version: %s)", tcllib_info))
					table.insert(working_tclsh, {
						cmd = tclsh_cmd,
						version = version,
						tcllib_version = tcllib_info,
						executable = executable,
					})
					if not best_tclsh then
						best_tclsh = working_tclsh[#working_tclsh]
					end
				else
					health.warn(string.format("  ❌ tcllib not available: %s", tcllib_info))
				end
			else
				health.error(string.format("%s exists but doesn't work: %s", tclsh_cmd, version or "unknown error"))
			end
		end
	end

	-- Summary
	if #working_tclsh == 0 then
		health.error("No working Tcl installation with tcllib found", {
			"Install Tcl: brew install tcl-tk",
			"Install tcllib: see installation instructions",
		})
	else
		health.ok(string.format("Found %d working Tcl installation(s) with tcllib", #working_tclsh))

		if best_tclsh then
			health.info(
				string.format(
					"Recommended: %s (Tcl %s, JSON %s)",
					best_tclsh.cmd,
					best_tclsh.version,
					best_tclsh.tcllib_version
				)
			)
		end
	end

	-- Check current file type
	if vim.bo.filetype == "tcl" then
		health.ok("Current file detected as TCL")

		-- Check if LSP is attached
		local clients = vim.lsp.get_clients({ bufnr = 0 })
		local tcl_clients = {}

		for _, client in ipairs(clients) do
			if client.name and (client.name:lower():match("tcl") or client.name:lower():match("lsp")) then
				table.insert(tcl_clients, client.name)
			end
		end

		if #tcl_clients > 0 then
			health.ok("LSP clients attached: " .. table.concat(tcl_clients, ", "))
		else
			health.warn("No TCL LSP clients attached to current buffer")
		end
	else
		health.info("Open a .tcl file to test LSP attachment")
	end

	-- Test JSON functionality with best Tcl
	if best_tclsh then
		local json_test_script = [[
set test_data {{"test": "health_check", "status": "working"}}
if {[catch {set result [json::json2dict $test_data]} err]} {
    puts "JSON_ERROR:$err"
} else {
    puts "JSON_SUCCESS:$result"
}
]]

		local result, success = utils.execute_tcl_script(json_test_script, best_tclsh.cmd)

		if result and success and result:match("JSON_SUCCESS") then
			health.ok("JSON functionality test passed")
		else
			local error = result and result:match("JSON_ERROR:([^\n]+)") or "Unknown error"
			health.warn("JSON functionality test failed: " .. error)
		end
	end
end

return M

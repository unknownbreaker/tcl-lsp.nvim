-- tests/spec/test_helpers.lua
-- Shared utilities and helpers for testing TCL LSP
-- Following modern Neovim testing patterns with comprehensive mocking

local M = {}

-- Logging utilities for test debugging
M.log_level = os.getenv "TCL_LSP_TEST_LOG_LEVEL" or "warn"

function M.log(level, message, ...)
  local levels = { debug = 1, info = 2, warn = 3, error = 4 }
  local current_level = levels[M.log_level] or 3

  if levels[level] and levels[level] >= current_level then
    local formatted = string.format(message, ...)
    io.stderr:write(string.format("[%s] %s: %s\n", os.date "%H:%M:%S", level:upper(), formatted))
  end
end

function M.debug(message, ...)
  M.log("debug", message, ...)
end
function M.info(message, ...)
  M.log("info", message, ...)
end
function M.warn(message, ...)
  M.log("warn", message, ...)
end
function M.error(message, ...)
  M.log("error", message, ...)
end

-- File system utilities
function M.write_file(filepath, content)
  local dir = vim.fn.fnamemodify(filepath, ":h")
  if vim.fn.isdirectory(dir) == 0 then
    local ok = vim.fn.mkdir(dir, "p")
    if ok == 0 then
      error("Failed to create directory: " .. dir)
    end
  end

  local file = io.open(filepath, "w")
  if not file then
    error("Could not open file for writing: " .. filepath)
  end

  file:write(content or "")
  file:close()
  M.debug("Wrote file: %s (%d bytes)", filepath, #(content or ""))
end

function M.read_file(filepath)
  local file = io.open(filepath, "r")
  if not file then
    return nil, "Could not open file: " .. filepath
  end

  local content = file:read "*all"
  file:close()
  return content
end

function M.file_exists(filepath)
  return vim.fn.filereadable(filepath) == 1
end

function M.create_temp_dir(prefix)
  local temp_dir = vim.fn.tempname()
  if prefix then
    temp_dir = temp_dir .. "_" .. prefix
  end

  vim.fn.mkdir(temp_dir, "p")
  M.debug("Created temp directory: %s", temp_dir)
  return temp_dir
end

function M.cleanup_temp_dir(temp_dir)
  if temp_dir and vim.fn.isdirectory(temp_dir) == 1 then
    vim.fn.delete(temp_dir, "rf")
    M.debug("Cleaned up temp directory: %s", temp_dir)
  end
end

-- Project creation utilities
function M.create_tcl_project(base_dir, options)
  options = options or {}

  local project_files = options.files
    or {
      ["main.tcl"] = [[
# Main TCL file
proc main {} {
    puts "Hello from TCL project"
    set result [calculate 42]
    puts "Result: $result"
}

proc calculate {input} {
    return [expr {$input * 2}]
}

main
]],
      ["utils.tcl"] = [[
# Utility procedures
namespace eval ::utils {
    proc string_utils {str} {
        return [string toupper $str]
    }

    proc list_utils {lst} {
        return [llength $lst]
    }
}
]],
      ["config.tcl"] = [[
# Configuration
set ::config::app_name "TCL LSP Test"
set ::config::version "1.0.0"
set ::config::debug_mode 1
]],
    }

  -- Add root markers based on options
  local root_markers = options.root_markers or { ".git" }
  for _, marker in ipairs(root_markers) do
    if marker == ".git" then
      project_files[".git/config"] = "[core]\nrepositoryformatversion = 0"
    elseif marker == "tcl.toml" then
      project_files["tcl.toml"] = [[
[project]
name = "test-project"
version = "1.0.0"
description = "Test TCL project for LSP testing"

[build]
target = "executable"
]]
    elseif marker == "project.tcl" then
      project_files["project.tcl"] = [[
# Project configuration file
set project_name "test-project"
set project_version "1.0.0"
]]
    else
      project_files[marker] = "# Custom marker file"
    end
  end

  -- Create all files
  vim.fn.mkdir(base_dir, "p")
  for filepath, content in pairs(project_files) do
    M.write_file(base_dir .. "/" .. filepath, content)
  end

  M.debug("Created TCL project at: %s", base_dir)
  return base_dir
end

-- Async utilities for LSP testing
function M.wait_for(condition, timeout_ms, error_msg)
  timeout_ms = timeout_ms or 5000
  error_msg = error_msg or "Timeout waiting for condition"

  local start_time = vim.loop.hrtime()
  local timeout_ns = timeout_ms * 1000000 -- Convert to nanoseconds

  while true do
    if condition() then
      local elapsed_ms = (vim.loop.hrtime() - start_time) / 1000000
      M.debug("Condition met after %d ms", elapsed_ms)
      return true
    end

    local elapsed = vim.loop.hrtime() - start_time
    if elapsed > timeout_ns then
      local elapsed_ms = elapsed / 1000000
      M.error("Timeout after %d ms: %s", elapsed_ms, error_msg)
      error(error_msg .. " (timeout: " .. elapsed_ms .. "ms)")
    end

    vim.wait(50) -- Wait 50ms before checking again
    vim.cmd "redraw" -- Allow Neovim to process events
  end
end

function M.wait_for_lsp_client(client_id, timeout_ms)
  return M.wait_for(function()
    local client = vim.lsp.get_client_by_id(client_id)
    return client and client.initialized
  end, timeout_ms, "LSP client failed to initialize")
end

function M.wait_for_lsp_attach(bufnr, server_name, timeout_ms)
  return M.wait_for(function()
    local clients = vim.lsp.get_clients { bufnr = bufnr, name = server_name }
    return #clients > 0
  end, timeout_ms, "LSP client failed to attach to buffer")
end

-- Performance measurement utilities
function M.measure_time(func, ...)
  local start_time = vim.loop.hrtime()
  local results = { func(...) }
  local end_time = vim.loop.hrtime()
  local duration_ms = (end_time - start_time) / 1000000

  return results, duration_ms
end

function M.measure_memory(func, ...)
  collectgarbage "collect" -- Force garbage collection
  local mem_before = collectgarbage "count"

  local results = { func(...) }

  collectgarbage "collect"
  local mem_after = collectgarbage "count"
  local mem_used = mem_after - mem_before

  return results, mem_used
end

-- Test environment validation
function M.validate_test_environment()
  local issues = {}

  -- Check Neovim version
  if vim.version then
    local version = vim.version()
    if version.major == 0 and version.minor < 8 then
      table.insert(
        issues,
        "Neovim version too old (need 0.8+), got " .. version.major .. "." .. version.minor
      )
    end
  end

  -- Check for required executables
  if vim.fn.executable "tclsh" == 0 then
    table.insert(issues, "tclsh executable not found in PATH")
  end

  -- Check for write permissions
  local temp_test = vim.fn.tempname() .. "_test"
  local success, err = pcall(M.write_file, temp_test, "test")
  if not success then
    table.insert(issues, "Cannot write to temporary directory: " .. (err or "unknown error"))
  else
    pcall(vim.fn.delete, temp_test)
  end

  -- Check LSP support
  if not vim.lsp then
    table.insert(issues, "Neovim LSP support not available")
  end

  return issues
end

-- Test data generators
function M.generate_tcl_content(options)
  options = options or {}
  local procs = options.proc_count or 3
  local vars = options.var_count or 5
  local complexity = options.complexity or "simple"

  local content = {}

  -- Add header comment
  table.insert(content, "# Generated TCL content for testing")
  table.insert(content, "# Complexity: " .. complexity)
  table.insert(content, "")

  -- Generate variables
  for i = 1, vars do
    table.insert(content, string.format('set test_var_%d "value_%d"', i, i))
  end
  table.insert(content, "")

  -- Generate procedures
  for i = 1, procs do
    if complexity == "simple" then
      table.insert(content, string.format("proc test_proc_%d {} {", i))
      table.insert(content, string.format('    puts "Test procedure %d"', i))
      table.insert(content, "    return " .. i)
      table.insert(content, "}")
    elseif complexity == "medium" then
      table.insert(content, string.format('proc test_proc_%d {arg1 {arg2 "default"}} {', i))
      table.insert(content, "    upvar test_var_1 local_var")
      table.insert(content, string.format("    set result [expr {$arg1 + %d}]", i))
      table.insert(content, "    if {$result > 10} {")
      table.insert(content, '        puts "Large result: $result"')
      table.insert(content, "    }")
      table.insert(content, "    return $result")
      table.insert(content, "}")
    else -- complex
      table.insert(content, string.format("proc test_proc_%d {args} {", i))
      table.insert(content, "    global test_var_1")
      table.insert(content, "    array set options $args")
      table.insert(content, "    ")
      table.insert(content, "    for {set j 0} {$j < [llength $args]} {incr j} {")
      table.insert(content, "        set item [lindex $args $j]")
      table.insert(content, "        switch -glob $item {")
      table.insert(content, '            -*  { puts "Option: $item" }')
      table.insert(content, '            default { puts "Value: $item" }')
      table.insert(content, "        }")
      table.insert(content, "    }")
      table.insert(content, "    return [array size options]")
      table.insert(content, "}")
    end
    table.insert(content, "")
  end

  -- Add namespace if complex
  if complexity == "complex" then
    table.insert(content, "namespace eval ::test {")
    table.insert(content, "    variable counter 0")
    table.insert(content, "    ")
    table.insert(content, "    proc increment {} {")
    table.insert(content, "        variable counter")
    table.insert(content, "        incr counter")
    table.insert(content, "        return $counter")
    table.insert(content, "    }")
    table.insert(content, "}")
  end

  return table.concat(content, "\n")
end

-- Test fixtures
M.fixtures = {
  simple_tcl = [[
proc hello {} {
    puts "Hello, World!"
}

set greeting "Hello"
hello
]],

  complex_tcl = [[
# Complex TCL example with multiple features
package require Tcl 8.5

namespace eval ::example {
    variable counter 0
    variable data [dict create]

    proc init {config} {
        variable data
        variable counter

        dict for {key value} $config {
            dict set data $key $value
        }

        set counter 0
        return [dict size $data]
    }

    proc process {input args} {
        variable counter

        array set options {
            -verbose false
            -format "default"
        }
        array set options $args

        incr counter

        if {$options(-verbose)} {
            puts "Processing input: $input (iteration $counter)"
        }

        switch -exact $options(-format) {
            "upper" {
                return [string toupper $input]
            }
            "lower" {
                return [string tolower $input]
            }
            default {
                return $input
            }
        }
    }
}

# Usage example
::example::init {name "test" version "1.0"}
set result [::example::process "Hello World" -verbose true -format upper]
puts "Result: $result"
]],

  syntax_error_tcl = [[
proc broken {
    # Missing closing brace
    puts "This will cause a syntax error"

set incomplete_var
# Missing value

if {$undefined_var == "test"} {
    puts "This references undefined variable"
}
]],

  rvt_template = [[
<html>
<head>
    <title><?= $page_title ?></title>
</head>
<body>
    <h1>Welcome to <?= $site_name ?></h1>

    <?
    set users [db_query "SELECT * FROM users"]
    foreach user $users {
        puts "<p>User: [dict get $user name]</p>"
    }
    ?>

    <div class="content">
        <?= [format_content $main_content] ?>
    </div>
</body>
</html>
]],
}

-- Export all utilities
return M

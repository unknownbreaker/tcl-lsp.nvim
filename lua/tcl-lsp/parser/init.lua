-- lua/tcl-lsp/parser/init.lua
-- Parser module entry point
-- This module coordinates between Lua and TCL parsing components

local M = {}

-- Load sub-modules
M.ast = require "tcl-lsp.parser.ast"

-- Re-export common functions for convenience
M.parse = M.ast.parse
M.parse_file = M.ast.parse_file

return M

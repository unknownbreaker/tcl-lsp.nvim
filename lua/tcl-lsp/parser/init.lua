-- lua/tcl-lsp/parser/init.lua
-- Parser module entry point
-- This module coordinates between Lua and TCL parsing components

local M = {}

-- Load sub-modules
M.ast = require "tcl-lsp.parser.ast"
M.schema = require "tcl-lsp.parser.schema"
M.validator = require "tcl-lsp.parser.validator"

-- Re-export common functions for convenience
M.parse = M.ast.parse
M.parse_file = M.ast.parse_file

-- Re-export validation functions
M.validate_ast = M.validator.validate_ast
M.validate_file = M.validator.validate_file
M.validate_node = M.validator.validate_node

return M

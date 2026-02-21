--- Static list of TCL builtin commands for completion and lookup
--- @module tcl-lsp.data.builtins

local M = {}

-- stylua: ignore
M.list = {
  -- I/O commands
  { name = "puts", type = "builtin" },
  { name = "gets", type = "builtin" },
  { name = "read", type = "builtin" },
  { name = "open", type = "builtin" },
  { name = "close", type = "builtin" },
  { name = "eof", type = "builtin" },
  { name = "flush", type = "builtin" },
  { name = "seek", type = "builtin" },
  { name = "tell", type = "builtin" },
  { name = "fconfigure", type = "builtin" },
  { name = "fcopy", type = "builtin" },
  { name = "fileevent", type = "builtin" },
  { name = "fblocked", type = "builtin" },
  { name = "chan", type = "builtin" },

  -- Variables
  { name = "set", type = "builtin" },
  { name = "unset", type = "builtin" },
  { name = "global", type = "builtin" },
  { name = "variable", type = "builtin" },
  { name = "upvar", type = "builtin" },
  { name = "incr", type = "builtin" },
  { name = "append", type = "builtin" },

  -- Control flow
  { name = "if", type = "builtin" },
  { name = "else", type = "builtin" },
  { name = "elseif", type = "builtin" },
  { name = "for", type = "builtin" },
  { name = "foreach", type = "builtin" },
  { name = "while", type = "builtin" },
  { name = "switch", type = "builtin" },
  { name = "break", type = "builtin" },
  { name = "continue", type = "builtin" },
  { name = "return", type = "builtin" },
  { name = "exit", type = "builtin" },

  -- Procedures
  { name = "proc", type = "builtin" },
  { name = "uplevel", type = "builtin" },
  { name = "tailcall", type = "builtin" },
  { name = "apply", type = "builtin" },
  { name = "rename", type = "builtin" },

  -- Error handling
  { name = "catch", type = "builtin" },
  { name = "try", type = "builtin" },
  { name = "throw", type = "builtin" },
  { name = "error", type = "builtin" },

  -- Expressions
  { name = "expr", type = "builtin" },

  -- List commands
  { name = "list", type = "builtin" },
  { name = "lindex", type = "builtin" },
  { name = "lappend", type = "builtin" },
  { name = "llength", type = "builtin" },
  { name = "lsort", type = "builtin" },
  { name = "lsearch", type = "builtin" },
  { name = "lrange", type = "builtin" },
  { name = "lreplace", type = "builtin" },
  { name = "linsert", type = "builtin" },
  { name = "lmap", type = "builtin" },
  { name = "lset", type = "builtin" },
  { name = "lrepeat", type = "builtin" },
  { name = "lreverse", type = "builtin" },
  { name = "lassign", type = "builtin" },
  { name = "concat", type = "builtin" },
  { name = "join", type = "builtin" },
  { name = "split", type = "builtin" },

  -- Dictionary commands
  { name = "dict", type = "builtin" },

  -- Array commands
  { name = "array", type = "builtin" },
  { name = "parray", type = "builtin" },

  -- String commands
  { name = "string", type = "builtin" },
  { name = "regexp", type = "builtin" },
  { name = "regsub", type = "builtin" },
  { name = "format", type = "builtin" },
  { name = "scan", type = "builtin" },
  { name = "subst", type = "builtin" },

  -- Info and introspection
  { name = "info", type = "builtin" },
  { name = "trace", type = "builtin" },

  -- Namespace and packages
  { name = "namespace", type = "builtin" },
  { name = "package", type = "builtin" },
  { name = "source", type = "builtin" },
  { name = "load", type = "builtin" },
  { name = "unload", type = "builtin" },

  -- File system
  { name = "file", type = "builtin" },
  { name = "glob", type = "builtin" },
  { name = "cd", type = "builtin" },
  { name = "pwd", type = "builtin" },

  -- Process control
  { name = "exec", type = "builtin" },
  { name = "pid", type = "builtin" },

  -- Event loop
  { name = "after", type = "builtin" },
  { name = "update", type = "builtin" },
  { name = "vwait", type = "builtin" },

  -- Interpreter
  { name = "interp", type = "builtin" },
  { name = "eval", type = "builtin" },

  -- Encoding and binary
  { name = "encoding", type = "builtin" },
  { name = "binary", type = "builtin" },

  -- Time
  { name = "clock", type = "builtin" },
  { name = "time", type = "builtin" },

  -- Networking
  { name = "socket", type = "builtin" },
  { name = "http", type = "builtin" },

  -- Math functions (commonly used)
  { name = "abs", type = "builtin" },
  { name = "acos", type = "builtin" },
  { name = "asin", type = "builtin" },
  { name = "atan", type = "builtin" },
  { name = "ceil", type = "builtin" },
  { name = "cos", type = "builtin" },
  { name = "exp", type = "builtin" },
  { name = "floor", type = "builtin" },
  { name = "log", type = "builtin" },
  { name = "pow", type = "builtin" },
  { name = "rand", type = "builtin" },
  { name = "round", type = "builtin" },
  { name = "sin", type = "builtin" },
  { name = "sqrt", type = "builtin" },
  { name = "tan", type = "builtin" },

  -- Object-oriented (TclOO)
  { name = "oo::class", type = "builtin" },
  { name = "oo::object", type = "builtin" },
  { name = "oo::define", type = "builtin" },
  { name = "oo::copy", type = "builtin" },

  -- Misc
  { name = "unknown", type = "builtin" },
  { name = "auto_load", type = "builtin" },
  { name = "auto_import", type = "builtin" },
  { name = "memory", type = "builtin" },
}

-- Auto-generated O(1) lookup: builtins.is_builtin["puts"] == true
M.is_builtin = {}
for _, item in ipairs(M.list) do
  M.is_builtin[item.name] = true
end

return M

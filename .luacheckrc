std = luajit
cache = true

read_globals = {
	"vim",
	"describe",
	"it",
	"before_each",
	"after_each",
	"setup",
	"teardown",
	"pending",
	"finally",
}

globals = {
	"vim.g",
	"vim.b",
	"vim.w",
	"vim.t",
	"vim.v",
	"vim.env",
}

ignore = {
	"631", -- max_line_length
	"212/_.*", -- unused argument, for vars with "_" prefix
}

exclude_files = {
	"lua/tcl-lsp/vendor/",
}

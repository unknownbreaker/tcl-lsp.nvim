# tcl-lsp.nvim

Language Server Protocol (LSP) implementation for TCL, built for Neovim.

Provides intelligent editing features for `.tcl` and `.rvt` (Rivet template) files.

## Features

- **Go to definition** (`gd`) — jump to proc, variable, or namespace definitions
- **Find references** — locate all usages of a symbol across files
- **Hover** — view proc signatures, parameter info, and documentation
- **Diagnostics** — syntax error reporting with line/column positions
- **Rename** — safely rename symbols across the project
- **Code completion** — proc names, variables, namespaces, packages
- **Formatting** — consistent code style
- **Folding** — collapse procs, namespaces, control flow blocks
- **Semantic highlighting** — context-aware syntax coloring

## Requirements

- Neovim 0.11.3+
- TCL 8.6+ (`tclsh` must be in PATH)

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "FlightAware/tcl-lsp.nvim",
  ft = { "tcl", "rvt" },
  config = function()
    require("tcl-lsp").setup({})
  end,
}
```

## Configuration

```lua
require("tcl-lsp").setup({
  -- Auto-start LSP when opening TCL/RVT files (default: true)
  auto_start = true,

  -- Root directory markers (default: { ".git", "tcl.toml", "project.tcl" })
  root_markers = { ".git", "tcl.toml", "project.tcl", "Makefile" },

  -- Background indexer (default: disabled, can cause UI lag)
  indexer = {
    enabled = false,
  },
})
```

## Usage

The plugin auto-starts when you open a `.tcl` or `.rvt` file. Default keymaps are set for TCL buffers:

| Key | Action |
|-----|--------|
| `gd` | Go to definition |

### Commands

| Command | Description |
|---------|-------------|
| `:TclLspStart` | Start the LSP server |
| `:TclLspStop` | Stop the LSP server |
| `:TclLspRestart` | Restart the LSP server |
| `:TclLspStatus` | Show server status |
| `:TclIndexStatus` | Show background indexer status |

## Architecture

Two-language design: TCL handles parsing (it's the best at its own syntax), Lua handles Neovim integration. They communicate via JSON over stdio.

See [CLAUDE.md](CLAUDE.md) for the full architecture overview, module map, and design rationale.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines and [DEVELOPMENT.md](DEVELOPMENT.md) for the development workflow.

## Status

Active development. Core LSP features are implemented and working. Version: 0.1.0-dev.

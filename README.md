# TCL LSP for Neovim

A Language Server Protocol (LSP) implementation for TCL/Tk in Neovim. Works out of the box with **any** Tcl installation!

## ✨ Features

- 🔍 **Hover Documentation** - Built-in help for 25+ TCL commands
- 🎯 **Go to Definition** - Jump to procedure and variable definitions
- 🔗 **Find References** - Find all usages of symbols across workspace
- 📋 **Document Symbols** - Outline view of procedures, variables, and namespaces
- 🔎 **Workspace Symbols** - Search symbols across all TCL files
- 🐛 **Syntax Checking** - Real-time error detection
- ⚡ **Auto-Detection** - Automatically finds your Tcl installation
- 🔧 **Zero Config** - Works immediately with sensible defaults

## 🚀 Installation

### LazyVim (Recommended)

```lua
{
  "unknownbreaker/tcl-lsp.nvim",
  ft = "tcl",
  dependencies = { "neovim/nvim-lspconfig" },
  config = function()
    require("tcl-lsp").setup()
  end,
}
```

### Packer

```lua
use {
  'unknownbreaker/tcl-lsp.nvim',
  ft = 'tcl',
  requires = { 'neovim/nvim-lspconfig' },
  config = function()
    require('tcl-lsp').setup()
  end
}
```

### vim-plug

```vim
Plug 'unknownbreaker/tcl-lsp.nvim'
Plug 'neovim/nvim-lspconfig'

lua require('tcl-lsp').setup()
```

## 🎯 That's It!

The plugin automatically:

- ✅ Finds your Tcl installation (system, Homebrew, MacPorts, custom)
- ✅ Detects tcllib and JSON package support
- ✅ Sets up all keymaps and commands
- ✅ Configures beautiful diagnostics
- ✅ Enables syntax checking on save
- ✅ Supports `.tcl`, `.tk`, `.itcl`, `.rvt` files

## 📋 Commands & Keymaps

| Command         | Keymap       | Description                     |
| --------------- | ------------ | ------------------------------- |
| `:TclCheck`     | `<leader>tc` | Check syntax of current file    |
| `:TclInfo`      | `<leader>ti` | Show Tcl system information     |
| `:TclJsonTest`  | `<leader>tj` | Test JSON package functionality |
| `:TclLspStatus` | -            | Show LSP status                 |
| -               | `K`          | Hover documentation             |
| -               | `gd`         | Go to definition                |
| -               | `gr`         | Find references                 |
| -               | `gO`         | Document symbols                |

## 🔧 Requirements

- **Neovim 0.8+**
- **Tcl with tcllib** (any installation method):
  - System: `sudo apt install tcl tcllib` (Ubuntu/Debian)
  - Homebrew: `brew install tcl-tk` + install tcllib
  - MacPorts: `sudo port install tcllib`
  - Manual: Download from tcllib.sourceforge.net

## ⚡ Health Check

Run `:checkhealth tcl-lsp` to verify your setup and see all detected Tcl installations.

## 🎛️ Configuration (Optional)

The plugin works perfectly with zero configuration, but you can customize:

```lua
require("tcl-lsp").setup({
  -- Tcl detection (default: "auto")
  tclsh_cmd = "auto",  -- or "/path/to/specific/tclsh"

  -- Features (all default: true)
  hover = true,
  diagnostics = true,
  symbol_navigation = true,

  -- Syntax checking
  syntax_check_on_save = true,
  syntax_check_on_change = false,

  -- Keymaps (set to false to disable)
  keymaps = {
    hover = "K",
    syntax_check = "<leader>tc",
    goto_definition = "gd",
    find_references = "gr",
    document_symbols = "gO",
  },

  -- Auto-setup (default: true for all)
  auto_setup_filetypes = true,  -- .tcl, .tk, .rvt detection
  auto_setup_commands = true,   -- :TclCheck, :TclInfo commands
  auto_setup_autocmds = true,   -- Syntax check on save, keymaps
})
```

## 🐛 Troubleshooting

1. **"No suitable Tcl installation found"**
   - Install Tcl: `brew install tcl-tk` (macOS) or `sudo apt install tcl` (Linux)
   - Install tcllib: See installation instructions above

2. **"JSON package not available"**
   - Install tcllib package: `sudo port install tcllib` or manual installation
   - Run `:TclJsonTest` to verify

3. **LSP not working**
   - Run `:checkhealth tcl-lsp` for detailed diagnosis
   - Check `:TclLspStatus` for current configuration

## 🎨 Supported File Types

- `.tcl` - TCL script files
- `.tk` - Tk GUI scripts
- `.itcl` - Incr TCL object-oriented extension
- `.rvt` - Rivet template files (TCL embedded in HTML)
- `.tclshrc`, `.wishrc` - TCL startup files

## 🤝 Contributing

Contributions welcome! The plugin is designed to be robust and work across different systems and Tcl installations.

## 📜 License

MIT License - see LICENSE file for details.

# tcl-lsp.nvim

A Language Server Protocol (LSP) implementation for TCL/Tk in Neovim, featuring a real TCL-based LSP server that leverages `tclsh`'s native introspection capabilities.

## ✨ Features

- 🚀 **Real LSP Server** - Proper background LSP server written in TCL
- 🔍 **Native TCL Introspection** - Uses `tclsh`'s built-in capabilities for accurate parsing
- 🎯 **Go to Definition** - Jump to procedure and variable definitions
- 🔗 **Find References** - Find all usages of symbols across workspace
- 📋 **Document Symbols** - Outline view of procedures, variables, and namespaces
- 🔎 **Workspace Symbols** - Search symbols across all TCL files
- 🐛 **Hover Documentation** - Built-in help for 25+ TCL commands
- ⚡ **Performance** - Background processing with persistent symbol database
- 🔧 **Easy Setup** - Works out of the box with LazyVim and nvim-lspconfig
- 🎯 **TCL/Rivet Focused** - Designed specifically for TCL/Tk and Apache Rivet development
- 🏥 **Health Check** - Built-in dependency verification and installation

## 📦 Installation

### With [lazy.nvim](https://github.com/folke/lazy.nvim) (Recommended)

```lua
{
  "unknownbreaker/tcl-lsp.nvim",
  ft = { "tcl" },
  dependencies = { "neovim/nvim-lspconfig" },
  config = function()
    require("tcl-lsp").setup()
  end,
}
```

### With [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'unknownbreaker/tcl-lsp.nvim',
  ft = { 'tcl' },
  requires = { 'neovim/nvim-lspconfig' },
  config = function()
    require('tcl-lsp').setup()
  end
}
```

## 🔧 Dependencies

The plugin automatically checks and can install dependencies:

- **tclsh** - TCL interpreter (required)
- **tcllib** - TCL standard library for JSON support (required)
- **nvim-lspconfig** - Neovim LSP configuration (required)

### Installation Commands

```bash
# macOS
brew install tcl-tk tcllib

# Ubuntu/Debian
sudo apt-get install tcl tcllib

# CentOS/RHEL/Fedora
sudo yum install tcl tcllib
# or
sudo dnf install tcl tcllib
```

Or run `:TclLspInstall` for automatic installation.

## ⚙️ Configuration

### Basic Setup

```lua
require("tcl-lsp").setup()
```

### Advanced Configuration

```lua
require("tcl-lsp").setup({
  -- Server configuration
  server = {
    settings = {
      tcl = {
        -- Future: TCL-specific settings
      }
    }
  },

  -- Custom on_attach function
  on_attach = function(client, bufnr)
    -- Your custom keymaps or configurations
    vim.keymap.set('n', '<leader>tc', function()
      vim.lsp.buf.hover()
    end, { buffer = bufnr, desc = 'TCL hover' })
  end,

  -- LSP capabilities (optional)
  capabilities = vim.lsp.protocol.make_client_capabilities(),

  -- Auto-install dependencies
  auto_install = {
    tcl = true,     -- Check for tclsh
    tcllib = true,  -- Check for JSON package
  },

  -- Logging level
  log_level = vim.log.levels.INFO,
})
```

## 🎮 Usage

### Default Keymaps

When the LSP attaches to a TCL buffer, these keymaps are automatically set:

| Key          | Action               | Description                                |
| ------------ | -------------------- | ------------------------------------------ |
| `K`          | Hover                | Show documentation for symbol under cursor |
| `gd`         | Go to Definition     | Jump to symbol definition                  |
| `gD`         | Go to Declaration    | Jump to symbol declaration                 |
| `gr`         | Find References      | Find all references to symbol              |
| `gi`         | Go to Implementation | Jump to implementation                     |
| `gt`         | Type Definition      | Jump to type definition                    |
| `<leader>rn` | Rename               | Rename symbol                              |
| `<leader>ca` | Code Actions         | Show available code actions                |
| `gO`         | Document Symbols     | Show document outline                      |
| `<leader>ws` | Workspace Symbols    | Search workspace symbols                   |
| `<leader>tc` | TCL Check            | Manual syntax check                        |

### Commands

| Command                | Description                            |
| ---------------------- | -------------------------------------- |
| `:TclLspInfo`          | Show LSP server status and information |
| `:TclLspStart`         | Start the TCL LSP server               |
| `:TclLspStop`          | Stop the TCL LSP server                |
| `:TclLspRestart`       | Restart the TCL LSP server             |
| `:TclLspLog`           | View LSP logs                          |
| `:TclLspInstall`       | Install missing dependencies           |
| `:checkhealth tcl-lsp` | Run health check                       |

### File Types Supported

- `.tcl` - TCL script files
- `.tk` - Tk GUI scripts
- `.rvt` - Apache Rivet template files
- `.rvt.in` - Rivet template input files
- `.itcl` - Incr TCL object-oriented extension
- `.itk` - Incr Tk widget extension

## 🏥 Health Check

Run `:checkhealth tcl-lsp` to verify your installation:

```vim
:checkhealth tcl-lsp
```

This will check:

- ✅ tclsh installation
- ✅ TCL JSON package availability
- ✅ LSP server script
- ✅ nvim-lspconfig integration
- ✅ Server status

## 🐛 Troubleshooting

### Common Issues

1. **"tclsh not found"**

   ```bash
   # Install TCL
   brew install tcl-tk  # macOS
   sudo apt-get install tcl  # Ubuntu
   ```

2. **"TCL JSON package not available"**

   ```bash
   # Install tcllib
   brew install tcllib  # macOS
   sudo apt-get install tcllib  # Ubuntu
   ```

3. **"Server script not found"**
   - Verify plugin installation
   - Check if `bin/tcl-lsp-server.tcl` exists in plugin directory
   - Run `:TclLspInfo` for diagnostics

4. **Server won't start**
   - Run `:checkhealth tcl-lsp`
   - Check `:TclLspLog` for errors
   - Verify file permissions: `chmod +x path/to/tcl-lsp-server.tcl`

### Debug Mode

Enable debug logging:

```lua
require("tcl-lsp").setup({
  log_level = vim.log.levels.DEBUG,
})
```

Then check logs with `:TclLspLog` or `:LspLog`.

## 🚀 Performance

This plugin uses a real LSP server architecture for optimal performance:

- **Background Processing** - Server runs independently of Neovim
- **Persistent Symbol Database** - Symbols cached across sessions
- **Incremental Updates** - Only re-parses changed files
- **Native TCL Parsing** - Leverages `tclsh`'s introspection capabilities
- **Efficient Protocol** - Standard LSP JSON-RPC communication

## 🤝 Contributing

Contributions are welcome! Here are some ways to help:

1. **Report Issues** - Bug reports and feature requests
2. **Add TCL Commands** - Expand the built-in documentation
3. **Improve Parsing** - Enhance symbol detection
4. **Add Tests** - Help improve reliability
5. **Documentation** - Improve docs and examples

### Development Setup

```bash
# Clone the repository
git clone https://github.com/your-username/tcl-lsp.nvim.git
cd tcl-lsp.nvim

# Test locally
ln -s $(pwd) ~/.local/share/nvim/lazy/tcl-lsp.nvim

# Make server script executable
chmod +x bin/tcl-lsp-server.tcl

# Test the server
tclsh bin/tcl-lsp-server.tcl --test
```

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Inspired by the [Language Server Protocol](https://microsoft.github.io/language-server-protocol/)
- Built for the [Neovim](https://neovim.io/) and [TCL/Tk](https://www.tcl.tk/) communities
- Uses [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) for LSP integration

## 📚 Related Projects

- [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) - LSP configurations for Neovim
- [LazyVim](https://github.com/LazyVim/LazyVim) - Neovim setup powered by lazy.nvim
- [TCL/Tk Documentation](https://www.tcl.tk/doc/) - Official TCL documentation

---

Made with ❤️ for the TCL and Neovim communities

# tcl-lsp.nvim

A Language Server Protocol (LSP) implementation for TCL/Tk in Neovim, written in pure Lua.

## ✨ Features

- 🔍 **Hover Documentation** - Built-in help for 25+ TCL commands
- 🎯 **Go to Definition** - Jump to procedure and variable definitions
- 🔗 **Find References** - Find all usages of symbols across workspace
- 📋 **Document Symbols** - Outline view of procedures, variables, and namespaces
- 🔎 **Workspace Symbols** - Search symbols across all TCL files
- 🐛 **Syntax Checking** - Real-time error detection using `tclsh`
- 📝 **Diagnostics** - Integrated with Neovim's diagnostic system
- ⚡ **Fast & Lightweight** - Pure Lua implementation, no external dependencies
- 🔧 **Easy Setup** - Works out of the box with LazyVim and nvim-lspconfig
- 🎯 **TCL/Rivet Focused** - Designed specifically for TCL/Tk and Apache Rivet development

## 📦 Installation

### With [lazy.nvim](https://github.com/folke/lazy.nvim) (Recommended for LazyVim)

```lua
{
  "YOUR_USERNAME/tcl-lsp.nvim",
  ft = "tcl",
  dependencies = { "neovim/nvim-lspconfig" },
  config = function()
    require("tcl-lsp").setup()
  end,
}
```

### With [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'YOUR_USERNAME/tcl-lsp.nvim',
  ft = 'tcl',
  requires = { 'neovim/nvim-lspconfig' },
  config = function()
    require('tcl-lsp').setup()
  end
}
```

### With [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'YOUR_USERNAME/tcl-lsp.nvim'
Plug 'neovim/nvim-lspconfig'
```

Then add to your Neovim config:

```lua
require('tcl-lsp').setup()
```

## ⚙️ Configuration

### Basic Setup

```lua
require("tcl-lsp").setup()
```

### Advanced Configuration

```lua
require("tcl-lsp").setup({
  -- Enable/disable features
  hover = true,                    -- Enable hover documentation
  diagnostics = true,              -- Enable syntax checking
  symbol_navigation = true,        -- Enable go-to-definition, references, etc.
  completion = false,              -- Completion (future feature)

  -- Symbol parsing
  symbol_update_on_change = false, -- Update symbols while typing

  -- Diagnostic configuration
  diagnostic_config = {
    virtual_text = true,
    signs = true,
    underline = true,
    update_in_insert = false,
  },

  -- TCL interpreter settings
  tclsh_cmd = "tclsh",            -- Command to run TCL interpreter
  syntax_check_on_save = true,    -- Check syntax when saving
  syntax_check_on_change = false, -- Check syntax while typing

  -- Keymaps (set to false to disable)
  keymaps = {
    hover = "K",                  -- Show hover documentation
    syntax_check = "<leader>tc",  -- Manual syntax check
    goto_definition = "gd",       -- Go to definition
    find_references = "gr",       -- Find references
    document_symbols = "gO",      -- Document symbols
  },
})
```

## 🚀 Usage

### Symbol Navigation

Navigate your TCL/Rivet codebase with full LSP support:

```tcl
# Regular TCL file (.tcl)
proc calculate {x y} {
    set result [expr $x + $y]  # 'gd' on 'result' jumps to definition
    return $result
}

# Use the procedure
set value [calculate 10 20]   # 'gd' on 'calculate' jumps to proc definition
                              # 'gr' finds all references to 'calculate'
```

```html
<!-- Rivet template file (.rvt) -->
<html>
  <body>
    <h1>Welcome to Rivet</h1>

    <? # TCL code within Rivet tags - full LSP support! proc greet {name} {
    return "Hello, $name!" } set user_name [var_qs "name" "World"] #
    Rivet-specific commands supported hputs [greet $user_name] # 'gd' works on
    'greet' here too ?> <%@ include file="header.rvt" %>
    <!-- Include directives tracked -->
  </body>
</html>
```

### Hover Documentation

Place your cursor on any TCL command and press `K` to see documentation:

```tcl
puts "Hello World"  # Hover over 'puts' for documentation
set var 123         # Hover over 'set' for help
proc myproc {} {}   # Hover over 'proc' for syntax info
```

### Document Symbols

Press `gO` to see an outline of your TCL file:

- 📋 **Procedures** - All proc definitions
- 📊 **Variables** - set commands
- 📦 **Namespaces** - namespace eval blocks
- 📄 **Source Files** - source commands
- 📚 **Packages** - package require statements

### Workspace Symbols

Search across all TCL files in your workspace:

- `:TclWorkspaceSymbols` - List all symbols
- `:TclWorkspaceSymbols proc_name` - Search for specific symbols

### Syntax Checking

Errors are automatically highlighted:

```tcl
# This will show an error
if {$x > 5          # Missing closing brace
    puts "error"
```

### Custom Commands

- `:TclCheck` - Manual syntax check
- `:TclSymbols` - Show symbols in current buffer
- `:TclWorkspaceSymbols` - Search workspace symbols
- `:TclInfo` - Show LSP status information
- `<leader>tc` - Quick syntax check keymap

## 📋 Requirements

- Neovim 0.8+
- `tclsh` available in PATH (for syntax checking)
- [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig)

### Supported File Types

**✅ Standard TCL Files:**

- `.tcl` - TCL script files
- `.tk` - Tk GUI scripts
- `.itcl` - Incr TCL object-oriented extension
- `.itk` - Incr Tk widget extension

**✅ Apache Rivet Files:**

- `.rvt` - Rivet template files (TCL embedded in HTML)
- `.rvt.in` - Rivet template input files

**✅ TCL Configuration:**

- `tclsh`, `wish` - TCL interpreter files
- `.tclshrc`, `.wishrc` - TCL startup files

### Rivet-Specific Features

For `.rvt` files, the plugin provides additional support:

**🏷️ Rivet Tag Parsing:**

- `<? tcl_code ?>` - TCL code blocks within HTML
- `<%@ include file="..." %>` - Include directives
- `<%@ parse file="..." %>` - Parse directives

**📚 Rivet Commands Documentation:**

- `hputs` - HTML output without escaping
- `hesc` - HTML character escaping
- `makeurl` - URL generation with parameters
- `var_qs` / `var_post` - Form data access
- `import_keyvalue_pairs` - Form data import
  ✅ **Single File Support** - Works without project structure

### Symbol Detection

The plugin automatically detects and indexes:

**Procedures:** `proc name args body`  
**Variables:** `set varname value`  
**Namespaces:** `namespace eval name { ... }`  
**Source Files:** `source filename.tcl`  
**Packages:** `package require packagename`

### Supported TCL Commands

The plugin provides hover documentation for 25+ TCL commands including:

**Core Commands:** `set`, `puts`, `if`, `for`, `while`, `proc`, `return`  
**String/List:** `string`, `list`, `split`, `join`, `lappend`, `llength`  
**Control Flow:** `switch`, `catch`, `error`, `eval`  
**File Operations:** `file`, `glob`, `source`  
**Advanced:** `namespace`, `package`, `regexp`, `regsub`

## 🤝 Contributing

Contributions are welcome! Here are some ways to help:

1. **Add more TCL commands** to the documentation
2. **Improve error parsing** for better diagnostics
3. **Add completion support** for TCL commands
4. **Enhance syntax checking** with more detailed error reporting
5. **Add tests** for the plugin functionality

### Development Setup

```bash
git clone https://github.com/YOUR_USERNAME/tcl-lsp.nvim.git
cd tcl-lsp.nvim

# Make changes to lua/tcl-lsp/
# Test in Neovim by symlinking to your config
ln -s $(pwd) ~/.local/share/nvim/lazy/tcl-lsp.nvim
```

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Inspired by the [jdc8/lsp](https://github.com/jdc8/lsp) TCL LSP implementation
- Built for the [LazyVim](https://github.com/LazyVim/LazyVim) ecosystem
- Uses [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) for LSP integration

## 📚 Related Projects

- [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) - LSP configurations for Neovim
- [LazyVim](https://github.com/LazyVim/LazyVim) - Neovim setup powered by lazy.nvim
- [TCL/Tk Documentation](https://www.tcl.tk/doc/) - Official TCL documentation

---

**Made with ❤️ for the TCL and Neovim communities**

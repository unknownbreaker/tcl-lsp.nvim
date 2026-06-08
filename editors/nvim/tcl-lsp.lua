-- tcl-lsp client config for Neovim 0.11+ (works with LazyVim).
--
-- Install: copy this file to ~/.config/nvim/lua/plugins/tcl-lsp.lua and set
-- `cmd` to wherever you installed the `tcl-lsp` binary (e.g. ~/.local/bin).
--
-- It uses Neovim 0.11's native vim.lsp.config/vim.lsp.enable, so it does not
-- depend on nvim-lspconfig internals. It is attached to the nvim-lspconfig spec
-- only to guarantee load ordering within LazyVim.
return {
  "neovim/nvim-lspconfig",
  init = function()
    -- Recognize .tcl and .rvt files.
    vim.filetype.add({ extension = { tcl = "tcl", rvt = "rvt" } })

    vim.lsp.config("tcl_lsp", {
      cmd = { vim.fn.expand("~/.local/bin/tcl-lsp") },
      filetypes = { "tcl", "rvt" },
      root_markers = { "pkgIndex.tcl", ".git" },
    })
    vim.lsp.enable("tcl_lsp")
  end,
}

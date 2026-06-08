-- tcl-lsp client config for Neovim 0.11+ / LazyVim.
--
-- Install: copy this file to ~/.config/nvim/lua/plugins/tcl-lsp.lua, set
-- `repo` below to where you cloned tcl-lsp.nvim, and ensure the `tcl-lsp`
-- binary is installed (default: ~/.local/bin/tcl-lsp; build it with
-- `cd server && make build`).
--
-- This is a self-contained LOCAL plugin spec (lazy.nvim treats a `dir` spec as a
-- local plugin and just runs its `config`). It deliberately does NOT attach to
-- the `neovim/nvim-lspconfig` spec: LazyVim owns that spec, and merging an
-- `init`/`config` fragment into it does not reliably run, so the server never
-- starts. A standalone spec loads at startup and is not overridden.
--
-- It uses Neovim 0.11's native vim.lsp.config/vim.lsp.enable (no nvim-lspconfig
-- dependency).

-- EDIT THIS to your clone path:
local repo = vim.fn.expand("~/Repos/FlightAware/2tcl-lsp.nvim")

return {
  {
    name = "tcl-lsp",
    dir = repo .. "/editors/nvim", -- any stable existing dir; marks this a local plugin
    lazy = false,
    priority = 100,
    config = function()
      -- Recognize .tcl and .rvt files.
      vim.filetype.add({ extension = { tcl = "tcl", rvt = "rvt" } })

      vim.lsp.config("tcl_lsp", {
        cmd = { vim.fn.expand("~/.local/bin/tcl-lsp") },
        filetypes = { "tcl", "rvt" },
        root_markers = { "pkgIndex.tcl", ".git" },
      })
      vim.lsp.enable("tcl_lsp")
    end,
  },
}

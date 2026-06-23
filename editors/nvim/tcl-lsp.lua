-- tcl-lsp client spec for Neovim 0.11+ / lazy.nvim.
--
-- Install: copy this file to ~/.config/nvim/lua/plugins/tcl-lsp.lua and restart.
-- lazy.nvim clones the repo, then (because of `opts`) calls
-- require("tcl-lsp").setup(opts). All the real work -- finding/building the
-- bundled Go server and wiring it into Neovim's native LSP -- lives in the
-- plugin's lua/tcl-lsp module, so this spec stays tiny.
--
-- The server is built from source on first use; that needs `go` + `make` on the
-- machine (the plugin tells you if they're missing). No `make install`, no PATH
-- setup, no binary path to maintain.

return {
  {
    -- MODE A (default): lazy.nvim manages the clone. Works on any machine with
    -- go + make. `rebuild` is now the default branch, so no branch pin needed.
    "unknownbreaker/tcl-lsp.nvim",

    -- Load only when you open a TCL/RVT buffer (the idiomatic lazy pattern for a
    -- filetype-scoped LSP). vim.lsp.enable doesn't spawn the server until a
    -- buffer attaches, so deferring the plugin's Lua is the only thing this saves
    -- -- but it keeps startup clean and signals intent.
    ft = { "tcl", "rvt" },

    -- `init` runs at startup (even though the plugin is lazy), so the .rvt
    -- extension is mapped before any file opens -- otherwise the `ft` trigger
    -- above could never fire for a .rvt buffer. (.tcl is a built-in filetype;
    -- we set it too for self-containment.)
    init = function()
      vim.filetype.add({ extension = { tcl = "tcl", rvt = "rvt" } })
    end,

    -- Defaults shown; everything is optional. Uncomment a line to change it.
    -- `opts` makes lazy.nvim call require("tcl-lsp").setup(opts) on load.
    opts = {
      -- filetypes    = { "tcl", "rvt" },           -- buffers the server attaches to
      -- root_markers = { "pkgIndex.tcl", ".git" },  -- how the project root is found
      -- cmd          = nil,   -- path to a server binary to use instead of the
      --                       -- bundled one (string or list); nil = bundled
      -- auto_build   = true,  -- build the bundled Go server on first use if missing
    },
  },

  -- MODE B (developing the LSP itself): point at your working clone instead of a
  -- lazy-managed one, so your edits drive the server. Comment out Mode A above,
  -- uncomment this, and set `dir` to your clone. Same module, same opts; rebuild
  -- with :TclLspRebuild (or `make watch` in server/) then :LspRestart.
  --
  -- {
  --   dir = vim.fn.expand("~/Repos/FlightAware/2tcl-lsp.nvim"), -- your clone (repo ROOT)
  --   name = "tcl-lsp",
  --   ft = { "tcl", "rvt" },
  --   init = function()
  --     vim.filetype.add({ extension = { tcl = "tcl", rvt = "rvt" } })
  --   end,
  --   opts = {},
  -- },
}

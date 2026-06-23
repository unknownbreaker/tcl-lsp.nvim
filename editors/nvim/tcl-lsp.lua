-- tcl-lsp client config for Neovim 0.11+ / LazyVim (lazy.nvim).
--
-- Install: copy this file to ~/.config/nvim/lua/plugins/tcl-lsp.lua. That's it.
-- lazy.nvim clones the repo, the `build` hook compiles the Go server, and the
-- config points the LSP at the freshly built binary inside the clone -- no
-- `make install`, no PATH setup, no hand-editing a binary path.
--
-- Requirements on the machine: `go` and `make` (to build the server). If they
-- are missing, the config warns and tells you how to drop in a prebuilt binary
-- instead of failing silently.
--
-- Uses Neovim 0.11's native vim.lsp.config/vim.lsp.enable (no nvim-lspconfig
-- dependency). It is a standalone spec on purpose: merging an init/config
-- fragment into LazyVim's nvim-lspconfig spec does not reliably run, so the
-- server would never start.

-- ensure_built returns the path to the server binary inside the plugin dir,
-- building it on first use if absent (a one-time cost on a fresh machine).
-- Returns nil (after notifying) if the binary is missing and cannot be built.
local function ensure_built(dir)
  local bin = dir .. "/server/tcl-lsp"
  local uv = vim.uv or vim.loop
  if uv.fs_stat(bin) then
    return bin
  end
  if vim.fn.executable("go") == 0 or vim.fn.executable("make") == 0 then
    vim.notify(
      "tcl-lsp: server binary missing and `go`/`make` not found.\n"
        .. "Install Go + make and run `make -C server build` in the plugin dir,\n"
        .. "or copy a prebuilt binary (server/dist/tcl-lsp-<os>-<arch>) to:\n  "
        .. bin,
      vim.log.levels.ERROR
    )
    return nil
  end
  vim.notify("tcl-lsp: building server binary (one-time)…", vim.log.levels.INFO)
  local res = vim.system({ "make", "-C", dir .. "/server", "build" }, { text = true }):wait()
  if res.code ~= 0 then
    vim.notify("tcl-lsp: build failed:\n" .. (res.stderr ~= "" and res.stderr or res.stdout), vim.log.levels.ERROR)
    return nil
  end
  vim.notify("tcl-lsp: server built.", vim.log.levels.INFO)
  return bin
end

-- Shared setup: register filetypes, locate/build the binary, enable the LSP.
local function setup(plugin)
  vim.filetype.add({ extension = { tcl = "tcl", rvt = "rvt" } })

  local bin = ensure_built(plugin.dir)
  if not bin then
    return
  end

  vim.lsp.config("tcl_lsp", {
    cmd = { bin },
    filetypes = { "tcl", "rvt" },
    root_markers = { "pkgIndex.tcl", ".git" },
  })
  vim.lsp.enable("tcl_lsp")

  -- Rebuild on demand after pulling new server code (lazy also rebuilds on
  -- `:Lazy update` / `:Lazy build tcl-lsp.nvim`).
  vim.api.nvim_create_user_command("TclLspRebuild", function()
    vim.system({ "make", "-C", plugin.dir .. "/server", "build" }, { text = true }, function(out)
      vim.schedule(function()
        if out.code == 0 then
          vim.notify("tcl-lsp: rebuilt. Run :LspRestart to load it.", vim.log.levels.INFO)
        else
          vim.notify("tcl-lsp: rebuild failed:\n" .. (out.stderr or ""), vim.log.levels.ERROR)
        end
      end)
    end)
  end, { desc = "Rebuild the tcl-lsp server binary" })
end

return {
  {
    -- MODE A (default): let lazy.nvim manage the clone + build. Drop this file
    -- in and it just works on any machine with go + make.
    "unknownbreaker/tcl-lsp.nvim",
    branch = "rebuild", -- the v2 Go server lives on `rebuild`; GitHub's default
    -- branch is still the old v1 tree. Drop this once `rebuild` becomes default.
    build = "make -C server build", -- runs on install and on :Lazy update/build
    lazy = false,
    priority = 100,
    config = function(plugin)
      setup(plugin)
    end,
  },

  -- MODE B (developing the LSP itself): point at your working clone instead of a
  -- lazy-managed one. Comment out Mode A above and uncomment this. The same
  -- setup() runs; `:TclLspRebuild` (or `make watch` in server/) rebuilds.
  --
  -- {
  --   name = "tcl-lsp",
  --   dir = vim.fn.expand("~/Repos/FlightAware/2tcl-lsp.nvim"), -- your clone
  --   lazy = false,
  --   priority = 100,
  --   config = function(plugin)
  --     setup(plugin)
  --   end,
  -- },
}

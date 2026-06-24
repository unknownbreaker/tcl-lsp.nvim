-- tcl-lsp: Neovim client for the bundled TCL/RVT language server.
--
-- This module is the whole client. A plugin spec only needs to call
-- `require("tcl-lsp").setup(opts)` (lazy.nvim does that for you when you pass
-- `opts`). Everything else -- locating/building the bundled Go server, wiring
-- it into Neovim's native LSP, and a rebuild command -- lives here, so the
-- user-facing config stays tiny. See editors/nvim/tcl-lsp.lua for the spec.
--
-- Requires Neovim 0.11+ (native vim.lsp.config / vim.lsp.enable).

local build = require("tcl-lsp.build")

local M = {}

-- plugin_root resolves this file's install dir up to the repo root
-- (<root>/lua/tcl-lsp/init.lua -> <root>), so the bundled server binary and
-- Makefile are found wherever the plugin was cloned -- no hardcoded paths.
local function plugin_root()
  local src = debug.getinfo(1, "S").source:sub(2) -- strip leading "@"
  return vim.fn.fnamemodify(src, ":p:h:h:h")
end

-- Defaults. Every field is overridable via the `opts` table a user passes to
-- setup() (see editors/nvim/tcl-lsp.lua for documented examples).
local defaults = {
  filetypes = { "tcl", "rvt" }, -- buffers the server attaches to
  -- How the project root is detected. ORDER IS PRIORITY (Neovim 0.11+): the
  -- repo root (.git) MUST come first. The server indexes its root's whole
  -- subtree, and cross-file resolution (.tcl proc <-> .rvt call site) only works
  -- when both files share one server/index. TCL projects put a pkgIndex.tcl in
  -- every package dir; if that marker wins, each package spawns its own server
  -- rooted at a narrow subtree that excludes the .rvt pages, so find-references
  -- from a .tcl silently misses .rvt call sites (goto-def the other way still
  -- works, which is the confusing asymmetry). pkgIndex.tcl stays only as a
  -- fallback for non-git checkouts.
  root_markers = { ".git", "pkgIndex.tcl" },
  cmd = nil, -- override the server binary (string or list); nil = bundled binary
  auto_build = true, -- build the bundled Go server on first use if missing
}

function M.setup(opts)
  opts = vim.tbl_deep_extend("force", defaults, opts or {})
  local root = plugin_root()

  local cmd = opts.cmd
  if type(cmd) == "string" then
    cmd = { cmd }
  end
  if not cmd then
    local bin = build.ensure_built(root, opts.auto_build)
    if not bin then
      return -- ensure_built already told the user what to do
    end
    cmd = { bin }
  end

  vim.lsp.config("tcl_lsp", {
    cmd = cmd,
    filetypes = opts.filetypes,
    root_markers = opts.root_markers,
  })
  vim.lsp.enable("tcl_lsp")

  -- Rebuild after pulling new server code, then :LspRestart to load it.
  vim.api.nvim_create_user_command("TclLspRebuild", function()
    vim.system({ "make", "-C", root .. "/server", "build" }, { text = true }, function(out)
      vim.schedule(function()
        if out.code == 0 then
          vim.notify("tcl-lsp: rebuilt — run :LspRestart to load it.", vim.log.levels.INFO)
        else
          vim.notify("tcl-lsp: rebuild failed:\n" .. (out.stderr or ""), vim.log.levels.ERROR)
        end
      end)
    end)
  end, { desc = "Rebuild the tcl-lsp server binary" })
end

return M

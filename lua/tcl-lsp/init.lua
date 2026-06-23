-- tcl-lsp: Neovim client for the bundled TCL/RVT language server.
--
-- This module is the whole client. A plugin spec only needs to call
-- `require("tcl-lsp").setup(opts)` (lazy.nvim does that for you when you pass
-- `opts`). Everything else -- locating/building the bundled Go server, wiring
-- it into Neovim's native LSP, and a rebuild command -- lives here, so the
-- user-facing config stays tiny. See editors/nvim/tcl-lsp.lua for the spec.
--
-- Requires Neovim 0.11+ (native vim.lsp.config / vim.lsp.enable).

local M = {}

-- plugin_root resolves this file's install dir up to the repo root
-- (<root>/lua/tcl-lsp/init.lua -> <root>), so the bundled server binary and
-- Makefile are found wherever the plugin was cloned -- no hardcoded paths.
local function plugin_root()
  local src = debug.getinfo(1, "S").source:sub(2) -- strip leading "@"
  return vim.fn.fnamemodify(src, ":p:h:h:h")
end

-- ensure_built returns the path to the server binary, building it from the
-- bundled `server/` on first use if it is missing (a one-time, ~seconds cost).
-- Returns nil (after notifying) if the binary is absent and cannot be built.
local function ensure_built(root, auto_build)
  local bin = root .. "/server/tcl-lsp"
  if (vim.uv or vim.loop).fs_stat(bin) then
    return bin
  end
  if not auto_build then
    return nil
  end
  if vim.fn.executable("go") == 0 or vim.fn.executable("make") == 0 then
    vim.notify(
      "tcl-lsp: server binary missing and `go`/`make` not found.\n"
        .. "Build it once with:  make -C " .. root .. "/server build",
      vim.log.levels.ERROR
    )
    return nil
  end
  vim.notify("tcl-lsp: building server (one-time)…", vim.log.levels.INFO)
  local res = vim.system({ "make", "-C", root .. "/server", "build" }, { text = true }):wait()
  if res.code ~= 0 then
    vim.notify("tcl-lsp: build failed:\n" .. (res.stderr ~= "" and res.stderr or res.stdout), vim.log.levels.ERROR)
    return nil
  end
  vim.notify("tcl-lsp: server built.", vim.log.levels.INFO)
  return bin
end

-- Defaults. Every field is overridable via the `opts` table a user passes to
-- setup() (see editors/nvim/tcl-lsp.lua for documented examples).
local defaults = {
  filetypes = { "tcl", "rvt" }, -- buffers the server attaches to
  root_markers = { "pkgIndex.tcl", ".git" }, -- how the project root is detected
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
    local bin = ensure_built(root, opts.auto_build)
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

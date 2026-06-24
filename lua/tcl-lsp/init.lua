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

-- mtime returns a file's modification time in epoch seconds, or nil if absent.
local function mtime(path)
  local st = (vim.uv or vim.loop).fs_stat(path)
  return st and st.mtime.sec or nil
end

-- is_stale reports whether the binary (built at bin_mtime) predates any server
-- source file, i.e. the plugin was updated but the binary was not rebuilt. This
-- is what makes auto-rebuild work under ANY plugin manager (or a manual git
-- pull), not just lazy.nvim's `build` hook: the check runs at load time and
-- triggers a rebuild whenever the sources are newer than the binary.
local function is_stale(bin_mtime, server_dir)
  local sources = vim.fn.globpath(server_dir, "**/*.go", false, true)
  for _, extra in ipairs({ "go.mod", "go.sum", "Makefile" }) do
    table.insert(sources, server_dir .. "/" .. extra)
  end
  for _, f in ipairs(sources) do
    local m = mtime(f)
    if m and m > bin_mtime then
      return true
    end
  end
  return false
end

-- ensure_built returns the path to the server binary, building it from the
-- bundled `server/` when it is missing OR stale (older than the server source,
-- e.g. after the plugin was updated). A build is a one-time, ~seconds cost.
-- Returns nil (after notifying) only when no binary exists and one cannot be
-- built; a stale binary that cannot be rebuilt is used as-is.
local function ensure_built(root, auto_build)
  local bin = root .. "/server/tcl-lsp"
  local server_dir = root .. "/server"
  local bin_mtime = mtime(bin)
  local exists = bin_mtime ~= nil
  if exists and not is_stale(bin_mtime, server_dir) then
    return bin -- present and up to date
  end
  if not auto_build then
    return exists and bin or nil -- opted out: use a stale binary if we have one
  end
  if vim.fn.executable("go") == 0 or vim.fn.executable("make") == 0 then
    if exists then
      return bin -- can't rebuild a stale binary; run it rather than fail
    end
    vim.notify(
      "tcl-lsp: server binary missing and `go`/`make` not found.\n"
        .. "Build it once with:  make -C " .. server_dir .. " build",
      vim.log.levels.ERROR
    )
    return nil
  end
  vim.notify(
    exists and "tcl-lsp: server sources changed — rebuilding…" or "tcl-lsp: building server (one-time)…",
    vim.log.levels.INFO
  )
  local res = vim.system({ "make", "-C", server_dir, "build" }, { text = true }):wait()
  if res.code ~= 0 then
    vim.notify("tcl-lsp: build failed:\n" .. (res.stderr ~= "" and res.stderr or res.stdout), vim.log.levels.ERROR)
    return exists and bin or nil -- fall back to the stale binary if the rebuild failed
  end
  vim.notify("tcl-lsp: server built.", vim.log.levels.INFO)
  return bin
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

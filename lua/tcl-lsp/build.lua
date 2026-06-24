-- tcl-lsp.build: locating, freshness-checking, and (re)building the bundled Go
-- server binary. Split out from init.lua so the freshness logic is unit-testable
-- without spinning up the LSP. Pure-ish: filesystem reads via vim.uv/vim.fn, and
-- the side-effecting bits of ensure_built (executable probe, build command,
-- notifications) are injectable so tests need not shell out or stub the whole
-- vim API.

local M = {}

local function uv()
  return vim.uv or vim.loop
end

-- mtime returns a file's modification time in epoch seconds, or nil if absent.
function M.mtime(path)
  local st = uv().fs_stat(path)
  return st and st.mtime.sec or nil
end

-- sources lists the server files whose changes warrant a rebuild: every .go file
-- plus the build inputs. Used to decide whether a compiled binary is stale.
function M.sources(server_dir)
  local list = vim.fn.globpath(server_dir, "**/*.go", false, true)
  for _, extra in ipairs({ "go.mod", "go.sum", "Makefile" }) do
    table.insert(list, server_dir .. "/" .. extra)
  end
  return list
end

-- is_stale reports whether any source file is newer than bin_mtime, i.e. the
-- sources were updated (a pull/checkout/edit) but the binary was not rebuilt.
function M.is_stale(bin_mtime, sources)
  for _, f in ipairs(sources) do
    local m = M.mtime(f)
    if m and m > bin_mtime then
      return true
    end
  end
  return false
end

-- ensure_built returns the path to the server binary, building it from
-- <root>/server when the binary is missing OR stale (older than the server
-- sources -- e.g. after the plugin was updated by any means). This load-time
-- check is what makes auto-rebuild work under any plugin manager or a manual
-- git pull, not just lazy.nvim's `build` hook.
--
-- Degrades safely: a stale binary that cannot be rebuilt (no go/make, or the
-- build failed) is returned as-is rather than refusing to start; a missing
-- binary that cannot be built yields nil (after notifying).
--
-- deps lets tests inject the side-effecting pieces; production passes nothing:
--   deps.executable(name) -> bool   (default: vim.fn.executable(name) == 1)
--   deps.run(cmd)         -> table  (default: vim.system(cmd,{text=true}):wait())
--   deps.notify(msg, lvl)           (default: vim.notify)
function M.ensure_built(root, auto_build, deps)
  deps = deps or {}
  local executable = deps.executable or function(x)
    return vim.fn.executable(x) == 1
  end
  local run = deps.run or function(cmd)
    return vim.system(cmd, { text = true }):wait()
  end
  local notify = deps.notify or vim.notify

  local server_dir = root .. "/server"
  local bin = server_dir .. "/tcl-lsp"
  local bin_mtime = M.mtime(bin)
  local exists = bin_mtime ~= nil

  if exists and not M.is_stale(bin_mtime, M.sources(server_dir)) then
    return bin -- present and up to date
  end
  if not auto_build then
    return exists and bin or nil -- opted out: use a stale binary if we have one
  end
  if not (executable("go") and executable("make")) then
    if exists then
      return bin -- can't rebuild a stale binary; run it rather than fail
    end
    notify(
      "tcl-lsp: server binary missing and `go`/`make` not found.\n"
        .. "Build it once with:  make -C " .. server_dir .. " build",
      vim.log.levels.ERROR
    )
    return nil
  end

  notify(
    exists and "tcl-lsp: server sources changed — rebuilding…" or "tcl-lsp: building server (one-time)…",
    vim.log.levels.INFO
  )
  local res = run({ "make", "-C", server_dir, "build" })
  if res.code ~= 0 then
    local detail = (res.stderr and res.stderr ~= "" and res.stderr) or res.stdout or ""
    notify("tcl-lsp: build failed:\n" .. detail, vim.log.levels.ERROR)
    return exists and bin or nil -- fall back to the stale binary if the rebuild failed
  end
  notify("tcl-lsp: server built.", vim.log.levels.INFO)
  return bin
end

return M

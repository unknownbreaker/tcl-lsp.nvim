-- Tests for tcl-lsp.build: the freshness check and the rebuild decision tree
-- that keep the bundled server binary in sync with its source after an update.

local build = require("tcl-lsp.build")
local uv = vim.uv or vim.loop

-- write creates (or truncates) a file with optional content.
local function write(path, content)
  local fd = assert(uv.fs_open(path, "w", 420))
  assert(uv.fs_write(fd, content or ""))
  assert(uv.fs_close(fd))
end

-- set_mtime stamps a file's atime/mtime to a fixed epoch second, so staleness is
-- deterministic regardless of how fast the test runs.
local function set_mtime(path, t)
  assert(uv.fs_utime(path, t, t))
end

local function tmpdir()
  local d = vim.fn.tempname()
  vim.fn.mkdir(d, "p")
  return d
end

-- noop deps: never let tests actually probe the system or shell out.
local function deps(overrides)
  local d = {
    executable = function()
      return true
    end,
    run = function()
      return { code = 0 }
    end,
    notify = function() end,
  }
  return vim.tbl_extend("force", d, overrides or {})
end

describe("build.is_stale", function()
  it("is true when a source is newer than the binary", function()
    local d = tmpdir()
    write(d .. "/a.go")
    set_mtime(d .. "/a.go", 2000)
    assert.is_true(build.is_stale(1000, { d .. "/a.go" }))
  end)

  it("is false when every source is older than the binary", function()
    local d = tmpdir()
    write(d .. "/a.go")
    set_mtime(d .. "/a.go", 500)
    assert.is_false(build.is_stale(1000, { d .. "/a.go" }))
  end)

  it("ignores missing source files", function()
    assert.is_false(build.is_stale(1000, { "/no/such/file.go" }))
  end)
end)

describe("build.ensure_built", function()
  -- prepare a fake server tree with a binary and one source, at given mtimes.
  local function server(bin_mtime, src_mtime)
    local root = tmpdir()
    vim.fn.mkdir(root .. "/server", "p")
    write(root .. "/server/tcl-lsp")
    set_mtime(root .. "/server/tcl-lsp", bin_mtime)
    write(root .. "/server/main.go")
    set_mtime(root .. "/server/main.go", src_mtime)
    return root, root .. "/server/tcl-lsp"
  end

  it("rebuilds when the sources are newer than the binary", function()
    local root, bin = server(1000, 2000)
    local built = false
    local got = build.ensure_built(root, true, deps({
      run = function()
        built = true
        return { code = 0 }
      end,
    }))
    assert.is_true(built)
    assert.equals(bin, got)
  end)

  it("does not rebuild when the binary is up to date", function()
    local root, bin = server(2000, 1000)
    local built = false
    local got = build.ensure_built(root, true, deps({
      run = function()
        built = true
        return { code = 0 }
      end,
    }))
    assert.is_false(built)
    assert.equals(bin, got)
  end)

  it("uses the stale binary (no rebuild) when go/make are missing", function()
    local root, bin = server(1000, 2000)
    local built = false
    local got = build.ensure_built(root, true, deps({
      executable = function()
        return false
      end,
      run = function()
        built = true
        return { code = 0 }
      end,
    }))
    assert.is_false(built)
    assert.equals(bin, got)
  end)

  it("returns the stale binary when a rebuild fails", function()
    local root, bin = server(1000, 2000)
    local got = build.ensure_built(root, true, deps({
      run = function()
        return { code = 1, stderr = "boom" }
      end,
    }))
    assert.equals(bin, got)
  end)

  it("returns nil when no binary exists and it cannot be built", function()
    local root = tmpdir()
    vim.fn.mkdir(root .. "/server", "p") -- no binary, no sources
    local got = build.ensure_built(root, true, deps({
      executable = function()
        return false
      end,
    }))
    assert.is_nil(got)
  end)

  it("with auto_build=false, never builds but still returns a stale binary", function()
    local root, bin = server(1000, 2000)
    local built = false
    local got = build.ensure_built(root, false, deps({
      run = function()
        built = true
        return { code = 0 }
      end,
    }))
    assert.is_false(built)
    assert.equals(bin, got)
  end)
end)

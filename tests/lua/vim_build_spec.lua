-- Tests for autoload/tcl_lsp.vim (the Vim build/freshness port), exercised
-- through vim.fn so they run in the existing plenary harness -- no vader needed.
-- These mirror tests/lua/build_spec.lua to keep the Vim and Lua ports in sync.

local uv = vim.uv or vim.loop

local function write(path, content)
  local fd = assert(uv.fs_open(path, "w", 420))
  assert(uv.fs_write(fd, content or ""))
  assert(uv.fs_close(fd))
end

local function set_mtime(path, t)
  assert(uv.fs_utime(path, t, t))
end

local function tmpdir()
  local d = vim.fn.tempname()
  vim.fn.mkdir(d, "p")
  return d
end

describe("tcl_lsp#is_stale (vimscript)", function()
  it("is true when a source is newer than the binary", function()
    local d = tmpdir()
    write(d .. "/a.go")
    set_mtime(d .. "/a.go", 2000)
    assert.equals(1, vim.fn["tcl_lsp#is_stale"](1000, { d .. "/a.go" }))
  end)

  it("is false when every source is older than the binary", function()
    local d = tmpdir()
    write(d .. "/a.go")
    set_mtime(d .. "/a.go", 500)
    assert.equals(0, vim.fn["tcl_lsp#is_stale"](1000, { d .. "/a.go" }))
  end)

  it("ignores missing source files", function()
    assert.equals(0, vim.fn["tcl_lsp#is_stale"](1000, { "/no/such/file.go" }))
  end)
end)

describe("tcl_lsp#_decide (vimscript) — the rebuild decision tree", function()
  local function decide(exists, stale, auto_build, has_tools)
    return vim.fn["tcl_lsp#_decide"](exists, stale, auto_build, has_tools)
  end

  it("uses a fresh existing binary", function()
    assert.equals("use", decide(1, 0, 1, 1))
  end)

  it("builds when the binary is stale and tools are present", function()
    assert.equals("build", decide(1, 1, 1, 1))
  end)

  it("uses the stale binary when go/make are missing", function()
    assert.equals("use", decide(1, 1, 1, 0))
  end)

  it("uses the stale binary when auto_build is off", function()
    assert.equals("use", decide(1, 1, 0, 1))
  end)

  it("builds when the binary is missing and tools are present", function()
    assert.equals("build", decide(0, 0, 1, 1))
  end)

  it("is 'none' when missing and no tools", function()
    assert.equals("none", decide(0, 0, 1, 0))
  end)

  it("is 'none' when missing and auto_build is off", function()
    assert.equals("none", decide(0, 0, 0, 1))
  end)
end)

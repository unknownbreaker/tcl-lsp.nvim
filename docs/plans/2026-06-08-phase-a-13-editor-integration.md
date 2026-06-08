# Phase A — Plan 13: Build tooling + editor integration

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the `tcl-lsp` server installable and usable from Neovim/LazyVim and Vim: a build/cross-compile Makefile, an end-to-end smoke test of the real binary, the editor client configs, and an install README.

**Architecture:** Adds build tooling and editor glue around the Plan 12 binary. The smoke test execs the compiled binary and drives a real LSP session over its stdio (proving the binary, not just the package). Editor configs are provided as drop-in files; the README documents build + install + use.

**Tech Stack:** Go 1.23+ (local 1.26.4), `make`, Lua (Neovim), Vimscript (Vim).

---

## File structure

- `server/Makefile` — `build`, `dist` (cross-compile), `test`, `vet`, `clean`.
- `server/cmd/tcl-lsp/main_test.go` — end-to-end smoke test of the built binary.
- `editors/nvim/tcl-lsp.lua` — Neovim 0.11 / LazyVim client spec.
- `editors/vim/tcl-lsp.vim` — classic Vim (vim-lsp) client config.
- `editors/README.md` — build + install + configure + smoke instructions.
- `examples/` — a tiny 2-file TCL project to try goto-def/ref against.
- Modify `.gitignore` — ignore build outputs.

---

## Task 1: Build Makefile + gitignore

**Files:**
- Create: `server/Makefile`
- Modify: `.gitignore`

- [ ] **Step 1: Create the Makefile**

Create `server/Makefile` (recipe lines MUST be indented with a real TAB, not spaces):

```makefile
BINARY := tcl-lsp
PKG := ./cmd/tcl-lsp
DIST := dist

.PHONY: build dist test vet clean

build:
	go build -o $(BINARY) $(PKG)

test:
	go test ./...

vet:
	go vet ./...

# Cross-compiled release binaries (no cgo, so this just works).
dist:
	mkdir -p $(DIST)
	GOOS=darwin  GOARCH=arm64 go build -o $(DIST)/$(BINARY)-darwin-arm64 $(PKG)
	GOOS=darwin  GOARCH=amd64 go build -o $(DIST)/$(BINARY)-darwin-amd64 $(PKG)
	GOOS=linux   GOARCH=arm64 go build -o $(DIST)/$(BINARY)-linux-arm64 $(PKG)
	GOOS=linux   GOARCH=amd64 go build -o $(DIST)/$(BINARY)-linux-amd64 $(PKG)
	GOOS=windows GOARCH=amd64 go build -o $(DIST)/$(BINARY)-windows-amd64.exe $(PKG)

clean:
	rm -f $(BINARY)
	rm -rf $(DIST)
```

- [ ] **Step 2: Update .gitignore**

Add to the repo-root `.gitignore` (append at the end):

```
# Go server build outputs
/server/tcl-lsp
/server/dist/
```

- [ ] **Step 3: Verify build + cross-compile**

Run: `make -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server build`
Then: `ls -la /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server/tcl-lsp`
Expected: builds; binary exists, non-zero size.

Run: `make -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server dist`
Then: `ls -la /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server/dist`
Expected: five cross-compiled binaries.

Then clean the local build so it is not committed: `make -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server clean`

- [ ] **Step 4: Confirm git sees only the Makefile + .gitignore**

Run: `git -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim status --short`
Expected: only `server/Makefile` (untracked) and modified `.gitignore` — no binaries.

- [ ] **Step 5: Commit**

```bash
git add server/Makefile .gitignore
git commit -m "build(server): Makefile with build/dist cross-compile targets"
```

---

## Task 2: End-to-end binary smoke test

This builds the real binary and drives an LSP session over its stdio, proving the compiled server (not just the package) resolves a cross-file definition.

**Files:**
- Create: `server/cmd/tcl-lsp/main_test.go`

- [ ] **Step 1: Write the test**

Create `server/cmd/tcl-lsp/main_test.go`:

```go
package main

import (
	"bytes"
	"encoding/json"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"

	"github.com/unknownbreaker/tcl-lsp/internal/lsp"
)

// TestBinaryEndToEnd builds the tcl-lsp binary and drives a real LSP session
// over its stdin/stdout, asserting a cross-file goto-definition resolves.
func TestBinaryEndToEnd(t *testing.T) {
	bin := filepath.Join(t.TempDir(), "tcl-lsp")
	if out, err := exec.Command("go", "build", "-o", bin, ".").CombinedOutput(); err != nil {
		t.Fatalf("build failed: %v\n%s", err, out)
	}

	cmd := exec.Command(bin)
	stdin, err := cmd.StdinPipe()
	if err != nil {
		t.Fatal(err)
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	cmd.Stderr = os.Stderr
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() {
		_ = stdin.Close()
		_ = cmd.Wait()
	}()

	w := lsp.NewConn(bytes.NewReader(nil), stdin)
	r := lsp.NewConn(stdout, io.Discard)

	send := func(method string, id, params any) {
		m := &lsp.Message{Method: method}
		if id != nil {
			b, _ := json.Marshal(id)
			m.ID = b
		}
		if params != nil {
			b, _ := json.Marshal(params)
			m.Params = b
		}
		if err := w.Write(m); err != nil {
			t.Fatalf("write %s: %v", method, err)
		}
	}

	send("initialize", 1, lsp.InitializeParams{})
	send("textDocument/didOpen", nil, lsp.DidOpenParams{
		TextDocument: lsp.TextDocumentItem{URI: "file:///lib.tcl", Text: "proc greet {} {}"}})
	send("textDocument/didOpen", nil, lsp.DidOpenParams{
		TextDocument: lsp.TextDocumentItem{URI: "file:///main.tcl", Text: "greet"}})
	send("textDocument/definition", 2, lsp.TextDocumentPositionParams{
		TextDocument: lsp.TextDocumentIdentifier{URI: "file:///main.tcl"},
		Position:     lsp.Position{Line: 0, Character: 0}})
	send("exit", nil, nil)

	// Read responses until we see id 2 (with a guard against hanging).
	done := make(chan []lsp.Location, 1)
	go func() {
		for {
			m, err := r.Read()
			if err != nil {
				done <- nil
				return
			}
			if string(m.ID) == "2" {
				var locs []lsp.Location
				_ = json.Unmarshal(m.Result, &locs)
				done <- locs
				return
			}
		}
	}()

	select {
	case locs := <-done:
		if len(locs) != 1 || locs[0].URI != "file:///lib.tcl" {
			t.Fatalf("definition over binary = %#v", locs)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("timed out waiting for definition response")
	}
}
```

- [ ] **Step 2: Run the test**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./cmd/tcl-lsp/`
Expected: PASS (builds the binary, drives a session, resolves `greet` to lib.tcl).

- [ ] **Step 3: Commit**

```bash
git add server/cmd/tcl-lsp/main_test.go
git commit -m "test(cmd): end-to-end smoke test of the tcl-lsp binary over stdio"
```

---

## Task 3: Editor client configs

**Files:**
- Create: `editors/nvim/tcl-lsp.lua`
- Create: `editors/vim/tcl-lsp.vim`

- [ ] **Step 1: Create the Neovim/LazyVim config**

Create `editors/nvim/tcl-lsp.lua`:

```lua
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
```

- [ ] **Step 2: Create the Vim config**

Create `editors/vim/tcl-lsp.vim`:

```vim
" tcl-lsp client config for classic Vim using vim-lsp
" (https://github.com/prabirshrestha/vim-lsp).
"
" Install: ensure `tcl-lsp` is on your PATH, then source this file from your
" vimrc (or copy its contents in). Requires the vim-lsp plugin.

if executable('tcl-lsp')
  augroup tcl_lsp
    autocmd!
    autocmd User lsp_setup call lsp#register_server({
      \ 'name': 'tcl-lsp',
      \ 'cmd': {server_info->['tcl-lsp']},
      \ 'allowlist': ['tcl', 'rvt'],
      \ })
  augroup END
endif

" Recognize .rvt as tcl-family (vim already knows .tcl).
autocmd BufRead,BufNewFile *.rvt setfiletype rvt
```

- [ ] **Step 3: Lint-check the Lua (best effort)**

Run: `luacheck /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/editors/nvim/tcl-lsp.lua --no-global 2>&1 || true`
Expected: no syntax errors (warnings about the global `vim` are fine / ignored). If `luacheck` is not installed, skip this step.

- [ ] **Step 4: Commit**

```bash
git add editors/nvim/tcl-lsp.lua editors/vim/tcl-lsp.vim
git commit -m "feat(editors): Neovim/LazyVim and Vim client configs"
```

---

## Task 4: Install README + example project

**Files:**
- Create: `editors/README.md`
- Create: `examples/math.tcl`
- Create: `examples/main.tcl`

- [ ] **Step 1: Create the example project**

Create `examples/math.tcl`:

```tcl
namespace eval ::math {
    variable pi 3.14159

    proc square {x} {
        return [expr {$x * $x}]
    }
}
```

Create `examples/main.tcl`:

```tcl
source math.tcl

set area [::math::square 3]
puts "pi is $::math::pi"
puts "area is $area"
```

- [ ] **Step 2: Create the install README**

Create `editors/README.md`:

```markdown
# tcl-lsp — editor setup

A Language Server for TCL/RVT providing **goto-definition** and
**goto-references** across a workspace. (See the repo root `CLAUDE.md` /
`docs/plans/` for status and scope; `.rvt`/Rivet is Phase B.)

## 1. Build the binary

Requires Go 1.23+.

```sh
cd server
make build            # produces ./tcl-lsp for your platform
# or cross-compile all platforms into ./dist:
make dist
```

Install it on your PATH, e.g.:

```sh
mkdir -p ~/.local/bin
cp server/tcl-lsp ~/.local/bin/tcl-lsp
```

## 2. Configure your editor

### Neovim / LazyVim (0.11+)

Copy `editors/nvim/tcl-lsp.lua` to `~/.config/nvim/lua/plugins/tcl-lsp.lua`
and adjust `cmd` to your binary path. Restart Neovim, open a `.tcl` file, and
use `gd` (goto-definition) / `grr` or `<leader>cR` (references) per your LazyVim
keymaps.

> The Lua snippet uses Neovim 0.11's native `vim.lsp.config`/`vim.lsp.enable`.
> On older Neovim, register the server through `nvim-lspconfig` instead.

### Vim (vim-lsp)

Ensure `tcl-lsp` is on your PATH and `vim-lsp` is installed, then source
`editors/vim/tcl-lsp.vim` from your vimrc. Use `:LspDefinition` / `:LspReferences`.

## 3. Try it

Open `examples/main.tcl`, put the cursor on `::math::square` and goto-definition
— it should jump to `examples/math.tcl`. Goto-references on `square` (in
`math.tcl`) should list the call in `main.tcl`.

## Verify the server itself

```sh
cd server
go test ./...          # unit + end-to-end (the cmd/tcl-lsp smoke test builds and drives the binary)
```

## Known limitations (Phase A)

- Bare proc-local variables, `set x`/`incr x` bareword variable-name arguments,
  and `namespace path` command search are not yet resolved.
- `.rvt` / Rivet templates are Phase B (needs the production Rivet version + a
  representative template).
```

- [ ] **Step 3: Commit**

```bash
git add editors/README.md examples/math.tcl examples/main.tcl
git commit -m "docs(editors): install README and example TCL project"
```

---

## Done criteria for Plan 13

- `make -C server build` and `make -C server dist` produce the binary / cross-compiled binaries; `go test ./...` (incl. the end-to-end binary smoke test) passes.
- Drop-in editor configs exist for Neovim/LazyVim and Vim, plus an install README and a runnable example project.

**This completes Phase A (the index-resolvable goto-definition + goto-references LSP).** Follow-ups (separate efforts): the deferred resolution enhancements (proc-locals, `namespace path`, bareword var-name args), the `forEachBody` refactor (task #11), and `.rvt`/Rivet Phase B (needs FlightAware confirms).


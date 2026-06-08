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
use `gd` (goto-definition) and your references keymap (LazyVim: `grr`; stock Neovim: `:lua vim.lsp.buf.references()`, or `gd` via `:lua vim.lsp.buf.definition()`).

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

# tcl-lsp — editor setup

A Language Server for TCL/RVT providing **goto-definition** and
**goto-references** across a workspace. Both `.tcl` and `.rvt` (Rivet)
files are supported.

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

Copy `editors/nvim/tcl-lsp.lua` to `~/.config/nvim/lua/plugins/tcl-lsp.lua`,
set the `repo` path at the top to your clone (and `cmd` if the binary is not at
`~/.local/bin/tcl-lsp`). Restart Neovim, open a `.tcl` file, and use `gd`
(goto-definition) and your references keymap (LazyVim: `grr`; stock Neovim:
`:lua vim.lsp.buf.references()`).

> The snippet is a self-contained local plugin spec using Neovim 0.11's native
> `vim.lsp.config`/`vim.lsp.enable`. It deliberately does NOT merge into the
> `nvim-lspconfig` spec (LazyVim owns that, and the merge does not reliably run
> the setup — the server would never start). Confirm attachment with
> `:checkhealth lsp` (look for `tcl_lsp`).

### Vim (vim-lsp)

Ensure `tcl-lsp` is on your PATH and `vim-lsp` is installed, then source
`editors/vim/tcl-lsp.vim` from your vimrc. Use `:LspDefinition` / `:LspReferences`.

## 3. Try it

Open `examples/main.tcl`, put the cursor on `::math::square` and goto-definition
— it should jump to `examples/math.tcl`. Goto-references on `square` (in
`math.tcl`) should list the call in `main.tcl`.

For `.rvt` templates, open `examples/page.rvt`, put the cursor on `render_title`
in the `<?= [render_title $title] ?>` line and goto-definition — it should jump to
the `proc render_title` definition earlier in the same file.

## Verify the server itself

```sh
cd server
go test ./...          # unit + end-to-end (the cmd/tcl-lsp smoke test builds and drives the binary)
```

## Known limitations

- Bare proc-local variables, `set x`/`incr x` bareword variable-name arguments,
  and `namespace path` command search are not yet resolved.
- `source` include-following and `::rivet::` built-in command resolution are
  deferred (see `docs/plans/2026-06-08-phase-b-rvt-design.md` §9).

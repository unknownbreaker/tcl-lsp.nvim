# tcl-lsp — editor setup

A Language Server for TCL/RVT providing **goto-definition** and
**goto-references** across a workspace. Both `.tcl` and `.rvt` (Rivet)
files are supported.

## 1. Build the binary

**Neovim / lazy.nvim users can skip this** — the plugin builds the server
automatically the first time you open a TCL/RVT file (see step 2). You need this
section only for Vim, for a manual install, or for a machine with no Go toolchain.

Requires Go 1.23+ and `make`.

```sh
cd server
make build            # produces ./tcl-lsp for your platform
# or cross-compile every platform into ./dist:
make dist             # ./dist/tcl-lsp-{linux,darwin}-{amd64,arm64}, windows-amd64.exe
```

Install it on your PATH, e.g.:

```sh
mkdir -p ~/.local/bin
cp server/tcl-lsp ~/.local/bin/tcl-lsp
```

**No Go on the target machine?** Cross-compile elsewhere with `make dist`, then
copy the matching static binary over (`uname -m`: `x86_64` → `-linux-amd64`,
`aarch64` → `-linux-arm64`):

```sh
scp server/dist/tcl-lsp-linux-amd64  <host>:~/.local/bin/tcl-lsp
ssh <host> chmod +x ~/.local/bin/tcl-lsp
```

## 2. Configure your editor

### Neovim / LazyVim (0.11+, lazy.nvim)

Copy `editors/nvim/tcl-lsp.lua` to `~/.config/nvim/lua/plugins/tcl-lsp.lua` and
restart Neovim. That's the whole install. lazy.nvim clones the repo and, via the
spec's `opts`, calls `require("tcl-lsp").setup(opts)`; the plugin then builds the
bundled Go server **from source on install** (and the `build` directive rebuilds
it on every `:Lazy update`, so you never run a stale server after pulling new
server code) and wires it into Neovim's native LSP. No `make install`, no PATH
setup, no binary path to maintain. Building needs `go` + `make` on the machine; if
they're absent the plugin tells you to build it once by hand (or drop in a
prebuilt binary from step 1).

The spec loads on the `tcl`/`rvt` filetypes (`ft = { "tcl", "rvt" }`) and exposes
a documented `opts` table — `filetypes`, `root_markers`, `cmd` (override the
binary), `auto_build` — all optional, defaults shown inline. Edit those to
customize; leave `opts = {}` for defaults.

Open a `.tcl` file and use `gd` (goto-definition) and your references keymap
(LazyVim: `grr`; stock Neovim: `:lua vim.lsp.buf.references()`).

A `:Lazy update` rebuilds the server automatically (via `build`); run
`:LspRestart` afterward to swap the running process. If you pull server code
some other way (or you're in Mode B below), run `:TclLspRebuild` then
`:LspRestart`.

> **Developing the LSP itself?** The file ships a commented **Mode B** spec that
> points at your local working clone (`dir = …`) instead of a lazy-managed one —
> swap to it so your edits + `make watch` / `:TclLspRebuild` drive the server.
>
> The spec is standalone (Neovim 0.11 native `vim.lsp.config`/`vim.lsp.enable`)
> on purpose: merging into LazyVim's `nvim-lspconfig` spec does not reliably run
> the setup, so the server would never start. Confirm attachment with
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

- Array-element locals (`set arr(i)` / `$arr(i)`) are not yet resolved (a
  high-priority follow-up; see
  `docs/superpowers/specs/2026-06-22-proc-local-variable-resolution-design.md`).
- `namespace path` command search, `source` include-following, and `::rivet::`
  built-in command resolution are deferred (see
  `docs/plans/2026-06-08-phase-b-rvt-design.md` §9).

Proc-local variables (params, `set`/`incr`/`append`/`lappend`,
`foreach`/`lmap`/`lassign`/`dict for` targets, `upvar`/`global`/`variable`
links) now resolve within their enclosing proc.

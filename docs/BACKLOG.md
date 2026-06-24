# Backlog

Deferred work that is understood but intentionally not done yet. Each item notes
why it's deferred and the rough shape of the fix, so picking it up later is cheap.

## coc.nvim auto-build / rebuild-on-update

**Status:** deferred. **Editor:** Vim/Neovim via coc.nvim.

vim-lsp users get auto-build + rebuild-when-stale (the bundled
`editors/vim/tcl-lsp.vim` runs `autoload/tcl_lsp.vim#ensure_built` before
registering). coc users don't, because coc's integration is **declarative JSON**
(`coc-settings.json`) — there's no seam where our code runs before coc launches
the server, so we can't call the build step. coc users currently build by hand
(`make -C server build`) and rebuild after pulling.

Two ways to add it when wanted:
1. **Wrapper command (lightweight).** Ship `editors/vim/tcl-lsp-coc.sh` that runs
   `make -C <repo>/server build` (a no-op when fresh) then `exec`s the binary, and
   point coc's `command` at it. Caveats: no Windows `sh`; runs `make` on every
   server start (cheap when up to date); the wrapper must locate the repo.
2. **coc extension (`coc-tcl-lsp`).** A Node/TS package with an `activate()` hook
   that builds, then registers the language client. Full parity, but a whole
   package to publish and maintain.

Lean toward (1) if coc demand appears; (2) only if a coc extension is wanted for
other reasons.

## vim-lsp live on-disk re-indexing (external changes)

**Status:** deferred / likely won't-fix. **Editor:** Vim via vim-lsp.

The server registers for `workspace/didChangeWatchedFiles`, but vim-lsp implements
neither `client/registerCapability` nor file watching (confirmed: both absent from
its source), so files changed on disk **while not open** aren't re-indexed until
opened. Open-buffer edits/saves/opens DO re-index live (via `didChange`/`didOpen`),
so only external changes to unopened files are missed. coc handles this natively.

A fix would require Vimscript-side mtime polling (classic Vim has no native fs
watch) plus a way to push notifications through vim-lsp — hacky and low value.
Recommend leaving it; document the limitation (done, see `editors/README.md`).

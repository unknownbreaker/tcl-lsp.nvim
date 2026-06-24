" autoload/tcl_lsp.vim — locate / freshness-check / (re)build the bundled Go
" server binary for Vim users, mirroring lua/tcl-lsp/build.lua so Vim gets the
" same auto-rebuild-on-update behavior Neovim has. Portable classic Vimscript
" (Vim 8.1+ / Neovim). Keep the two ports' behavior in sync.

" tcl_lsp#sources: the server files whose change warrants a rebuild — every .go
" file plus the build inputs.
function! tcl_lsp#sources(server_dir) abort
  let l:list = split(globpath(a:server_dir, '**/*.go'), "\n")
  for l:extra in ['go.mod', 'go.sum', 'Makefile']
    call add(l:list, a:server_dir . '/' . l:extra)
  endfor
  return l:list
endfunction

" tcl_lsp#is_stale: 1 if any source is newer than bin_mtime, else 0. getftime()
" returns -1 for a missing file, which is never newer than a real mtime, so
" missing sources are ignored automatically.
function! tcl_lsp#is_stale(bin_mtime, sources) abort
  for l:f in a:sources
    if getftime(l:f) > a:bin_mtime
      return 1
    endif
  endfor
  return 0
endfunction

" tcl_lsp#_decide: the rebuild decision tree as a PURE function (no filesystem,
" no shelling out) so it is unit-testable. All args are 0/1. Returns:
"   'use'   — a usable binary exists (fresh, or stale but unbuildable): run it
"   'build' — (re)build, then run
"   'none'  — no binary and it cannot be built
function! tcl_lsp#_decide(exists, stale, auto_build, has_tools) abort
  if a:exists && !a:stale
    return 'use'
  endif
  if !a:auto_build || !a:has_tools
    return a:exists ? 'use' : 'none'
  endif
  return 'build'
endfunction

" tcl_lsp#ensure_built: return the server binary path, building it from
" <root>/server when missing or stale (sources newer than the binary). Returns
" '' when no binary exists and one cannot be built; a stale binary that cannot be
" rebuilt is returned as-is. Synchronous — a one-time, ~seconds cost, matching
" the Neovim plugin.
function! tcl_lsp#ensure_built(root, auto_build) abort
  let l:server_dir = a:root . '/server'
  let l:bin = l:server_dir . '/tcl-lsp'
  let l:bin_mtime = getftime(l:bin)
  let l:exists = l:bin_mtime >= 0
  let l:stale = l:exists ? tcl_lsp#is_stale(l:bin_mtime, tcl_lsp#sources(l:server_dir)) : 0
  let l:has_tools = executable('go') && executable('make')

  let l:action = tcl_lsp#_decide(l:exists, l:stale, a:auto_build ? 1 : 0, l:has_tools ? 1 : 0)
  if l:action ==# 'use'
    return l:bin
  elseif l:action ==# 'none'
    if a:auto_build && !l:has_tools
      echohl WarningMsg
      echomsg 'tcl-lsp: server binary missing and go/make not found. Build: make -C ' . l:server_dir . ' build'
      echohl None
    endif
    return ''
  endif

  " l:action ==# 'build'
  echomsg l:exists ? 'tcl-lsp: server sources changed — rebuilding…' : 'tcl-lsp: building server (one-time)…'
  let l:out = system('make -C ' . shellescape(l:server_dir) . ' build')
  if v:shell_error != 0
    echohl ErrorMsg
    echomsg 'tcl-lsp: build failed: ' . l:out
    echohl None
    return l:exists ? l:bin : ''
  endif
  echomsg 'tcl-lsp: server built.'
  return l:bin
endfunction

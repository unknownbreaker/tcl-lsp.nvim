" tcl-lsp for Vim via vim-lsp (prabirshrestha/vim-lsp).
"
" Classic Vimscript — works in Vim and Neovim. Source this from your vimrc:
"     source /path/to/tcl-lsp.nvim/editors/vim/tcl-lsp.vim
"
" Prerequisites:
"   1. Build the server once (needs go + make):  make -C /path/to/tcl-lsp.nvim/server build
"      Then either put `tcl-lsp` on your PATH, or set g:tcl_lsp_cmd (below) to the
"      absolute path of server/tcl-lsp.
"   2. vim-lsp (+ async.vim) installed.
"   3. .rvt filetype detection — shipped in this repo's ftdetect/rvt.vim if you
"      install the repo as a plugin; otherwise add to your vimrc:
"          autocmd BufRead,BufNewFile *.rvt setfiletype rvt
"
" Use :LspDefinition and :LspReferences (or your vim-lsp keymaps).

if exists('g:loaded_tcl_lsp_vim')
  finish
endif
let g:loaded_tcl_lsp_vim = 1

" Path to the server binary. Default assumes `tcl-lsp` is on $PATH; override in
" your vimrc before sourcing this file if it lives elsewhere, e.g.
"     let g:tcl_lsp_cmd = expand('~/Repos/tcl-lsp.nvim/server/tcl-lsp')
if !exists('g:tcl_lsp_cmd')
  let g:tcl_lsp_cmd = 'tcl-lsp'
endif

" Resolve the project root. .git wins so ONE server indexes the whole repo
" (TCL/RVT cross-file resolution needs the .tcl definitions and the .rvt call
" sites in a single index). pkgIndex.tcl is only a fallback for non-git
" checkouts: listing both together would let a nearer pkgIndex.tcl win and
" fragment the project into per-package servers — the exact failure that hides
" .rvt references from a .tcl definition.
function! s:tcl_lsp_root_uri(...) abort
  let l:path = lsp#utils#get_buffer_path()
  let l:dir = lsp#utils#find_nearest_parent_file_directory(l:path, ['.git/'])
  if empty(l:dir)
    let l:dir = lsp#utils#find_nearest_parent_file_directory(l:path, ['pkgIndex.tcl'])
  endif
  return empty(l:dir) ? '' : lsp#utils#path_to_uri(l:dir)
endfunction

function! s:tcl_lsp_register() abort
  if !executable(g:tcl_lsp_cmd)
    echohl WarningMsg
    echomsg 'tcl-lsp: server not found (' . g:tcl_lsp_cmd . '). Build it: make -C <repo>/server build'
    echohl None
    return
  endif
  call lsp#register_server({
    \ 'name': 'tcl-lsp',
    \ 'cmd': {server_info -> [g:tcl_lsp_cmd]},
    \ 'allowlist': ['tcl', 'rvt'],
    \ 'root_uri': function('s:tcl_lsp_root_uri'),
    \ })
endfunction

augroup tcl_lsp_vim_lsp
  autocmd!
  autocmd User lsp_setup call s:tcl_lsp_register()
augroup END

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

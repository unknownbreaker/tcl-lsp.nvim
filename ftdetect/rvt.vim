" Detect Apache Rivet templates (.rvt) as filetype 'rvt'.
"
" Portable classic Vimscript so it works in BOTH Vim and Neovim. (.tcl is a
" built-in filetype in both editors, so only .rvt needs detection here.) The
" Neovim/lazy.nvim spec also registers this via vim.filetype.add for lazy-load
" timing; this ftdetect file covers Vim and non-lazy setups. Both are idempotent.
autocmd BufRead,BufNewFile *.rvt setfiletype rvt

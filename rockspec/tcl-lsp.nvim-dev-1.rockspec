package = "tcl-lsp.nvim"
version = "dev-1"
source = {
  url = "git+https://github.com/unknownbreaker/tcl-lsp.nvim.git",
}
description = {
  summary = "TCL Language Server Protocol implementation for Neovim",
  detailed = [[
      A comprehensive LSP implementation for TCL language with support for
      all modern LSP features including completion, hover, diagnostics,
      go-to-definition, references, and more.
   ]],
  homepage = "https://github.com/unknownbreaker/tcl-lsp.nvim",
  license = "MIT",
}
dependencies = {
  "lua >= 5.1",
}
build = {
  type = "builtin",
  modules = {},
}

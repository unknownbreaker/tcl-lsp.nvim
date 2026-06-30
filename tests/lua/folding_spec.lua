-- Tests for the folding option's pure piece: the window-local option values that
-- route folding through this server. Pins the exact expr string against typos
-- (e.g. vim.lsp vs vim.treesitter), which is the regression that would silently
-- disable LSP folding.

local tcl = require("tcl-lsp")

describe("tcl-lsp fold opts", function()
  it("routes folding through the LSP foldexpr, not Treesitter", function()
    local o = tcl._fold_opts()
    assert.are.equal("expr", o.foldmethod)
    assert.are.equal("v:lua.vim.lsp.foldexpr()", o.foldexpr)
  end)
end)

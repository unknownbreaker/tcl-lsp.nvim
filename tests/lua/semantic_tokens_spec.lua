-- tests/lua/semantic_tokens_spec.lua
describe("Semantic Tokens", function()
  local semantic_tokens

  before_each(function()
    package.loaded["tcl-lsp.analyzer.semantic_tokens"] = nil
    semantic_tokens = require("tcl-lsp.analyzer.semantic_tokens")
  end)

  describe("Token Types", function()
    it("should define standard LSP token types", function()
      assert.is_table(semantic_tokens.token_types)
      assert.equals(0, semantic_tokens.token_types.namespace)
      assert.equals(1, semantic_tokens.token_types.type)
      assert.equals(2, semantic_tokens.token_types.class)
      assert.equals(5, semantic_tokens.token_types.function_)
      assert.equals(8, semantic_tokens.token_types.variable)
      assert.equals(10, semantic_tokens.token_types.parameter)
    end)

    it("should define custom token types", function()
      assert.is_number(semantic_tokens.token_types.macro)
      assert.is_number(semantic_tokens.token_types.decorator)
    end)

    it("should provide token_types_legend array", function()
      assert.is_table(semantic_tokens.token_types_legend)
      assert.equals("namespace", semantic_tokens.token_types_legend[1])
      assert.equals("function", semantic_tokens.token_types_legend[6])
    end)
  end)
end)

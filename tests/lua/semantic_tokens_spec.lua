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

  describe("Token Modifiers", function()
    it("should define modifier bitmasks", function()
      assert.is_table(semantic_tokens.token_modifiers)
      assert.equals(1, semantic_tokens.token_modifiers.declaration)      -- bit 0
      assert.equals(2, semantic_tokens.token_modifiers.definition)       -- bit 1
      assert.equals(4, semantic_tokens.token_modifiers.readonly)         -- bit 2
      assert.equals(32, semantic_tokens.token_modifiers.modification)    -- bit 5
      assert.equals(64, semantic_tokens.token_modifiers.defaultLibrary)  -- bit 6
      assert.equals(256, semantic_tokens.token_modifiers.async)          -- bit 8
    end)

    it("should provide token_modifiers_legend array", function()
      assert.is_table(semantic_tokens.token_modifiers_legend)
      assert.equals("declaration", semantic_tokens.token_modifiers_legend[1])
      assert.equals("definition", semantic_tokens.token_modifiers_legend[2])
    end)

    it("should combine modifiers with bitwise OR", function()
      local mods = semantic_tokens.token_modifiers
      local combined = semantic_tokens.combine_modifiers({ "definition", "readonly" })
      assert.equals(mods.definition + mods.readonly, combined)
    end)
  end)
end)

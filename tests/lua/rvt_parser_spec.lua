-- tests/lua/rvt_parser_spec.lua
describe("RVT Parser", function()
  local rvt

  before_each(function()
    package.loaded["tcl-lsp.parser.rvt"] = nil
    rvt = require("tcl-lsp.parser.rvt")
  end)

  describe("find_blocks", function()
    it("should detect TCL code blocks", function()
      local content = [[<html>
<? set name "World" ?>
<h1>Hello</h1>
<?= $name ?>
</html>]]
      local blocks = rvt.find_blocks(content)

      assert.equals(2, #blocks)
      assert.equals("code", blocks[1].type)
      assert.equals("expr", blocks[2].type)
    end)

    it("should extract TCL code from blocks", function()
      local content = [[<? set x 1 ?>]]
      local blocks = rvt.find_blocks(content)

      assert.equals(1, #blocks)
      assert.equals(' set x 1 ', blocks[1].code)
      assert.equals(1, blocks[1].start_line)
      assert.equals(3, blocks[1].start_col)  -- after "<?"
    end)

    it("should extract expression blocks with correct offset", function()
      local content = [[<?= $name ?>]]
      local blocks = rvt.find_blocks(content)

      assert.equals(1, #blocks)
      assert.equals("expr", blocks[1].type)
      assert.equals(' $name ', blocks[1].code)
      assert.equals(1, blocks[1].start_line)
      assert.equals(4, blocks[1].start_col)  -- after "<?="
    end)

    it("should handle multi-line code blocks", function()
      local content = [[<html>
<?
set x 1
set y 2
?>
</html>]]
      local blocks = rvt.find_blocks(content)

      assert.equals(1, #blocks)
      assert.equals("code", blocks[1].type)
      assert.equals(2, blocks[1].start_line)
      assert.equals(3, blocks[1].start_col)
      -- Code should include the newlines
      assert.is_true(blocks[1].code:find("set x 1") ~= nil)
      assert.is_true(blocks[1].code:find("set y 2") ~= nil)
    end)

    it("should track end_line for multi-line blocks", function()
      local content = [[<?
proc hello {} {
    puts "hi"
}
?>]]
      local blocks = rvt.find_blocks(content)

      assert.equals(1, #blocks)
      assert.equals(1, blocks[1].start_line)
      assert.equals(5, blocks[1].end_line)
    end)

    it("should handle multiple blocks on same line", function()
      local content = [[<td><?= $x ?></td><td><?= $y ?></td>]]
      local blocks = rvt.find_blocks(content)

      assert.equals(2, #blocks)
      assert.equals("expr", blocks[1].type)
      assert.equals("expr", blocks[2].type)
      assert.equals(' $x ', blocks[1].code)
      assert.equals(' $y ', blocks[2].code)
      -- Both on line 1
      assert.equals(1, blocks[1].start_line)
      assert.equals(1, blocks[2].start_line)
      -- Different columns
      assert.equals(8, blocks[1].start_col)  -- after "<td><?="
      assert.equals(26, blocks[2].start_col)  -- after "</td><td><?="
    end)

    it("should return empty table for no blocks", function()
      local content = [[<html><body>Hello</body></html>]]
      local blocks = rvt.find_blocks(content)

      assert.is_table(blocks)
      assert.equals(0, #blocks)
    end)

    it("should handle empty content", function()
      local blocks = rvt.find_blocks("")
      assert.is_table(blocks)
      assert.equals(0, #blocks)
    end)

    it("should handle unclosed block gracefully", function()
      local content = [[<? set x 1]]
      local blocks = rvt.find_blocks(content)

      -- Should skip unclosed blocks
      assert.is_table(blocks)
      assert.equals(0, #blocks)
    end)

    it("should handle real-world RVT patterns", function()
      local content = [[<?
# Pet Detail View
set pet_id "pet_1"
set pet [get_pet $pet_id]
?>
<html>
<head>
    <title><?= [dict get $pet name] ?></title>
</head>
<body>
    <h1><?= [dict get $pet name] ?></h1>
    <? if {$stock > 0} { ?>
        <button>Add to Cart</button>
    <? } ?>
</body>
</html>]]
      local blocks = rvt.find_blocks(content)

      assert.equals(5, #blocks)
      -- First block: code
      assert.equals("code", blocks[1].type)
      assert.equals(1, blocks[1].start_line)
      -- Title expression
      assert.equals("expr", blocks[2].type)
      -- h1 expression
      assert.equals("expr", blocks[3].type)
      -- if block
      assert.equals("code", blocks[4].type)
      assert.is_true(blocks[4].code:find("if {$stock > 0}") ~= nil)
      -- closing brace
      assert.equals("code", blocks[5].type)
    end)
  end)

  describe("is_rvt_file", function()
    it("should return true for .rvt extension", function()
      assert.is_true(rvt.is_rvt_file("template.rvt"))
      assert.is_true(rvt.is_rvt_file("/path/to/views/list.rvt"))
    end)

    it("should return false for non-rvt files", function()
      assert.is_false(rvt.is_rvt_file("script.tcl"))
      assert.is_false(rvt.is_rvt_file("page.html"))
      assert.is_false(rvt.is_rvt_file("rvt.txt"))
    end)
  end)
end)

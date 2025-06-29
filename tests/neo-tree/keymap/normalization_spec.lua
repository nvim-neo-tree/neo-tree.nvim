local helper = require("neo-tree.setup.mapping-helper")
describe("keymap normalization", function()
  it("should work", function()
    local tests = {
      { "<BS>", "<bs>" },
      { "<Backspace>", "<bs>" },
      { "<Enter>", "<cr>" },
      { "<C-W>", "<c-W>" },
      { "<A-q>", "<m-q>" },
      { "<C-Left>", "<c-left>" },
      { "<C-Right>", "<c-right>" },
      { "<C-Up>", "<c-up>" },
    }
    for _, test in ipairs(tests) do
      local key = helper.normalize_map_key(test[1])
      assert(key == test[2], string.format("%s != %s", key, test[2]))
    end
  end)
end)

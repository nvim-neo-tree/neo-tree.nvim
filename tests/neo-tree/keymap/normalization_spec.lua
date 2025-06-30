local helper = require("neo-tree.setup.mapping-helper")
describe("keymap normalization", function()
  it("passes basic tests", function()
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
  it("allows for proper merging", function()
    local defaults = helper.normalize_mappings({
      ["n"] = "n",
      ["<Esc>"] = "escape",
      ["<C-j>"] = "j",
      ["<c-J>"] = "capital_j",
      ["a"] = "keep_this",
    })
    local new = helper.normalize_mappings({
      ["n"] = "n",
      ["<ESC>"] = "escape",
      ["<c-j>"] = "j",
      ["b"] = "override_this",
    })
    local merged = vim.tbl_deep_extend("force", defaults, new)
    assert.are.same({
      ["n"] = "n",
      ["<esc>"] = "escape",
      ["<c-j>"] = "j",
      ["<c-J>"] = "capital_j",
      ["a"] = "keep_this",
      ["b"] = "override_this",
    }, merged)
  end)
end)

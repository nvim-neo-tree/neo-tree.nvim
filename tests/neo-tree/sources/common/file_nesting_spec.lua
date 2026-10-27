local u = require("tests.utils")
local utils = require("neo-tree.utils")
local file_items = require("neo-tree.sources.common.file-items")
local nesting = require("neo-tree.sources.common.file-nesting")

describe("File nesting", function()
  local root

  before_each(function()
    root = u.fs.create_temp_dir()
  end)

  after_each(function()
    nesting.setup({})
    u.fs.remove_dir(root, true)
  end)

  local function nest_files(rules, names)
    nesting.setup(rules)
    local state = { path = root }
    ---@cast state neotree.State
    local context = file_items.create_context(state)
    local items = {}
    for _, name in ipairs(names) do
      local path = utils.path_join(root, name)
      u.fs.write_file(path)
      items[name] = file_items.create_item(context, path, "file")
    end
    nesting.nest_items(context)
    return context, items
  end

  it("nests files using the documented extension rule", function()
    local context, items = nest_files({ js = { "js.map" } }, { "example.js", "example.js.map" })
    local parent, child = items["example.js"], items["example.js.map"]

    assert.are.equal(1, #parent.children)
    assert.are.equal(child, parent.children[1])
    assert.are.equal(parent, child.nesting_parent)
    assert.are.equal(1, #context.folders[root].children)
  end)

  it("combines extension and pattern rules for the same parent", function()
    local context, items = nest_files({
      js = { "js.map" },
      ["js-pattern"] = { pattern = "^example%.js$", files = { "example.min.js" } },
    }, { "example.js", "example.js.map", "example.min.js" })
    local parent = items["example.js"]

    assert.are.equal(2, #parent.children)
    assert.are.equal(parent, items["example.js.map"].nesting_parent)
    assert.are.equal(parent, items["example.min.js"].nesting_parent)
    assert.are.equal(1, #context.folders[root].children)
  end)
end)

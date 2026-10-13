local u = require("tests.utils")
local utils = require("neo-tree.utils")
local ignored = require("neo-tree.sources.filesystem.lib.ignored")

describe("Filesystem ignore file precedence", function()
  local root

  before_each(function()
    root = u.fs.create_temp_dir()
  end)

  after_each(function()
    u.fs.remove_dir(root, true)
  end)

  local function write_rules(relative_path, rules)
    u.fs.write_file(utils.path_join(root, relative_path), rules)
  end

  local function check_file(relative_path)
    local path = utils.path_join(root, relative_path)
    u.fs.write_file(path, { "test file" })
    local item = { path = path, type = "file" }
    ---@cast item neotree.FileItem
    local state = {
      path = root,
      filtered_items = { ignore_files = { ".neotreeignore", ".ignore" } },
    }
    ---@cast state neotree.State
    ignored.mark_ignored(state, { item })
    return assert(item.filtered_by)
  end

  it("keeps an exception from a higher-priority ignore file", function()
    write_rules(".neotreeignore", { "!keep.txt" })
    write_rules(".ignore", { "*.txt" })

    local result = check_file("keep.txt")

    assert.is_false(result.ignored)
    assert.are.equal(utils.path_join(root, ".neotreeignore"), result.ignore_file)
  end)

  it("keeps an ignore match from a higher-priority ignore file", function()
    write_rules(".neotreeignore", { "*.txt" })
    write_rules(".ignore", { "!keep.txt" })

    local result = check_file("keep.txt")

    assert.is_true(result.ignored)
    assert.are.equal(utils.path_join(root, ".neotreeignore"), result.ignore_file)
  end)

  it("falls back when a higher-priority ignore file has no matching rule", function()
    write_rules(".neotreeignore", { "*.log" })
    write_rules(".ignore", { "*.txt" })

    local result = check_file("keep.txt")

    assert.is_true(result.ignored)
    assert.are.equal(utils.path_join(root, ".ignore"), result.ignore_file)
  end)

  it("keeps a child directory's exception over an ancestor's rule", function()
    write_rules(".ignore", { "*.txt" })
    write_rules("child/.ignore", { "!keep.txt" })

    local result = check_file("child/keep.txt")

    assert.is_false(result.ignored)
    assert.are.equal(utils.path_join(root, "child", ".ignore"), result.ignore_file)
  end)
end)

pcall(require, "luacov")
local utils = require("neo-tree.utils")
local uv = vim.uv or vim.loop

describe("fs_parent", function()
  it("works", function()
    assert.are.same(nil, utils.fs_parent("/"))
    assert.are.same(utils.path_separator, utils.fs_parent("/foo"))
    assert.are.same(utils.path_separator, utils.fs_parent("/foo/bar", true))
    assert.are.same(nil, utils.fs_parent("/foo/bar", false))
  end)
end)

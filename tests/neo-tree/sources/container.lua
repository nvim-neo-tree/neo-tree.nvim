pcall(require, "luacov")

local ns_id = require("neo-tree.ui.highlights").ns_id
local u = require("tests.utils")

local config = {
  directory = {
    {
      "container",
      content = {
        { "indent", zindex = 10 },
        { "icon", zindex = 10 },
        { "name", zindex = 10 },
        { "name", zindex = 5, align = "right" },
      },
    },
  },
  file = {
    {
      "container",
      content = {
        { "indent", zindex = 10 },
        { "icon", zindex = 10 },
        { "name", zindex = 10 },
        { "bufnr", zindex = 20, align = "right" },
      },
    },
  },
}

local test_dir = {
  items = {
    {
      name = "foo",
      type = "dir",
      items = {
        {
          name = "bar",
          type = "dir",
          items = {
            { name = "bar1.txt", type = "file" },
            { name = "barbarbarbarbar2.txt", type = "file" },
          },
        },
        { name = "foo1.lua", type = "file" },
      },
    },
    { name = "bazbazbazbazbazbazbazbazbazbazbazbazbazbazbazbazbaz", type = "dir" },
    { name = "1.md", type = "file" },
  },
}

describe("sources/components/container", function()
  local req_switch = u.get_require_switch()

  local test = u.fs.init_test(test_dir)
  test.setup()

  before_each(function()
    require("neo-tree").setup(config)
  end)

  after_each(function()
    if req_switch then
      req_switch.restore()
    end

    u.clear_environment()
  end)

  it("container should extend", function()
    vim.cmd([[Neotree]])
    u.wait_for(function()
      return vim.bo.filetype == "neo-tree"
    end)

    assert.equals(vim.bo.filetype, "neo-tree")

    for pow = 1, 8 do
      vim.api.nvim_win_set_width(0, 2 ^ pow)
      local width = vim.api.nvim_win_get_width(0)
      local lines = vim.api.nvim_buf_get_lines(0, 2, -1, false)
      assert.equals(lines, { "hello" })
    end
  end)
  test.teardown()
end)

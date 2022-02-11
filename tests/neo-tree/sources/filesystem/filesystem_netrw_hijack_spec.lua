local util = require("tests.helpers.util")
local verify = require("tests.helpers.verify")
local utils = require("neo-tree.utils")

describe("Filesystem netrw hijack", function()
  after_each(function()
    util.clear_test_state()
  end)

  require("neo-tree").setup({
    filesystem = {
      hijack_netrw_behavior = "disabled",
      window = {
        position = "left",
      },
    },
  })
  it("does not interfere with netrw when disabled", function()
    vim.cmd("edit .")
    assert(#vim.api.nvim_list_wins() == 1, "there should only be one window")
    verify.after(100, function()
      local name = vim.api.nvim_buf_get_name(0)
      print("name: " .. name)
      return name ~= "neo-tree filesystem [1]"
    end, "the buffer should not be neo-tree")
  end)

  local file = "Makefile"
  vim.cmd("edit " .. file)
  require("neo-tree").setup({
    filesystem = {
      hijack_netrw_behavior = "open_default",
      window = {
        position = "left",
      },
    },
  })
  it("opens in sidebar when behavior is open_default", function()
    vim.cmd("edit .")
    verify.after(100, function()
      assert(#vim.api.nvim_list_wins() == 2, "There should be 2 windows open")
      local expected_buf_name = "Makefile"
      local buf_at_2 = vim.api.nvim_win_get_buf(vim.fn.win_getid(2))
      local name_at_2 = vim.api.nvim_buf_get_name(buf_at_2)
      if name_at_2:sub(-#expected_buf_name) == expected_buf_name then
        return true
      else
        return false
      end
      verify.buf_name_endswith("neo-tree filesystem [1]")
    end, file .. " is not at window 2")
  end)

  vim.cmd("edit " .. file)
  require("neo-tree").setup({
    filesystem = {
      hijack_netrw_behavior = "open_split",
    },
  })
  it("opens in in splits when behavior is open_split", function()
    vim.cmd("edit .")
    verify.eventually(100, function()
      if #vim.api.nvim_list_wins() ~= 1 then
        return false
      end
      return vim.api.nvim_buf_get_option(0, "filetype") == "neo-tree"
    end, "neotree is not the only window")

    vim.cmd("split .")
    verify.eventually(150, function()
      if #vim.api.nvim_list_wins() ~= 2 then
        return false
      end
      return vim.api.nvim_buf_get_option(0, "filetype") == "neo-tree"
    end, "neotree is not in the second window")
  end)
end)

local Path = require('plenary.path')
local util = require("tests.helpers.util")
local verify = require("tests.helpers.verify")
local config = require("neo-tree").config
local get_value = require("neo-tree.utils").get_value

local run_in_current_command = function(command, expected_tree_node)
  local winid = vim.api.nvim_get_current_win()

  vim.cmd(command)
  verify.window_handle_is(winid)
  verify.buf_name_endswith(string.format("neo-tree filesystem [%s]", winid), 1000)
  if expected_tree_node then
    verify.filesystem_tree_node_is(expected_tree_node, winid)
  end
end

describe("Command", function()
  local fs = util.setup_test_fs()
  local is_follow = get_value(config, "filesystem.follow_current_file", false)

  after_each(function()
    util.clear_test_state()
  end)

  describe("netrw style:", function()
    it("`:Neotree current` should show neo-tree in current window", function()
      local cmd = "Neotree current"
      run_in_current_command(cmd)
    end)

    it("`:Neotree current reveal` should show neo-tree and reveal file in current window", function()
      local cmd = "Neotree current reveal"
      local testfile = fs.lookup["topfile1"].abspath
      util.editfile(testfile)
      run_in_current_command(cmd, testfile)
    end)

    it("`:Neotree current reveal toggle` should toggle neo-tree in current window", function()
      local cmd = "Neotree current reveal toggle"
      local testfile = fs.lookup["topfile1"].abspath
      util.editfile(testfile)
      local tree_winid = vim.api.nvim_get_current_win()

      -- toggle OPEN
      run_in_current_command(cmd, testfile)

      -- toggle CLOSE
      vim.cmd(cmd)
      verify.window_handle_is(tree_winid)
      verify.buf_name_is(testfile)
    end)

    it("`:Neotree current reveal_force_cwd reveal_file=xyz` should reveal file current window if cwd is not a parent of file", function()
      vim.cmd("cd ~")
      local testfile = fs.lookup["deepfile2"].abspath
      local cmd = "Neotree current reveal_force_cwd reveal_file=" .. testfile
      run_in_current_command(cmd, testfile)
    end)

    it("`:Neotree current reveal_force_cwd reveal_file=xyz` should reveal file current window if cwd is a parent of file", function()
      local testfile = fs.lookup["deepfile2"].abspath
      local testfile_dir = Path:new(testfile):parent().filename
      vim.cmd(string.format("cd %s", testfile_dir))
      local cmd = "Neotree current reveal_force_cwd reveal_file=" .. testfile
      run_in_current_command(cmd, testfile)
    end)
  end)

  util.teardown_test_fs()
end)

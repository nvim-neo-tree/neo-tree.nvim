local utils = {}

local fs = require("tests.helpers.fs")

local testdir = fs.create_temp_dir()

local function rm_test_dir()
  fs.remove_dir(testdir, true)
end

utils.setup_test_fs = function()
  rm_test_dir()

  -- Need a list-style map here to ensure that things happen in the correct order.
  --
  -- When/if editing this, be cautious as (for now) other tests might be accessing
  -- files from within this array by index
  local fs_tree = {
    abspath = testdir,
    items = {
      {
        name = "foo",
        type = "dir",
        items = {
          {
            name = "bar",
            type = "dir",
            items = {
              { name = "baz1.txt", type = "file" },
              { name = "baz2.txt", type = "file", id = "deepfile2" },
            },
          },
          { name = "foofile1.txt", type = "file" },
          { name = "foofile2.txt", type = "file" },
        },
      },
      { name = "bar", type = "dir", id = "empty_dir" },
      { name = "topfile1.txt", type = "file", id = "topfile1" },
      { name = "topfile2.txt", type = "file", id = "topfile2" },
    },
    lookup = {},
  }

  fs.create_fs_tree(fs_tree)

  vim.cmd("tcd " .. testdir)
  return fs_tree
end

utils.teardown_test_fs = function()
  rm_test_dir()
end

utils.clear_test_state = function()
  -- Create fresh window
  vim.cmd("top new | wincmd o")
  local keepbufnr = vim.api.nvim_get_current_buf()
  -- Clear ALL neo-tree state
  require("neo-tree.sources.manager")._clear_state()
  -- Cleanup any remaining buffers
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if bufnr ~= keepbufnr then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end
  assert(#vim.api.nvim_tabpage_list_wins(0) == 1, "Failed to properly clear tab")
  assert(#vim.api.nvim_list_bufs() == 1, "Failed to properly clear buffers")
end

utils.editfile = function(testfile)
  vim.cmd("e " .. testfile)
  assert.are.same(
    vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":p"),
    vim.fn.fnamemodify(testfile, ":p")
  )
end

return utils

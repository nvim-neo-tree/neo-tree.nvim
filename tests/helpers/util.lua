local utils = {}

local Path = require("plenary.path")
local testdir = Path:new(vim.env.TMPDIR or "/tmp", "neo-tree-testing"):absolute()

local function rm_test_dir()
  if vim.fn.isdirectory(testdir) == 1 then
    vim.fn.delete(testdir, "rf")
  end
end

utils.setup_test_fs = function()
  rm_test_dir()

  -- Need a list-style map here to ensure that things happen in the correct order.
  --
  -- When/if editing this, be cautious as (for now) other tests might be accessing
  -- files from within this array by index
  local fs = {
    basedir = testdir,
    content = {
      {
        name = "foo",
        type = "dir",
        content = {
          { name = "foofile1.txt", type = "file" },
          { name = "foofile2.txt", type = "file" },
        },
      },
      { name = "bar", type = "dir" },
      { name = "topfile1.txt", type = "file" },
    },
  }
  local function makefs(content, basedir)
    for _, info in ipairs(content) do
      if info.type == "dir" then
        info.abspath = Path:new(basedir, info.name):absolute()
        vim.fn.mkdir(info.abspath, "p")
        if info.content then
          makefs(info.content, info.abspath)
        end
      elseif info.type == "file" then
        info.abspath = Path:new(basedir, info.name):absolute()
        vim.fn.writefile({}, info.abspath)
      end
    end
  end
  makefs(fs.content, testdir)
  vim.cmd("tcd " .. testdir)
  return fs
end

utils.teardown_test_fs = function()
  rm_test_dir()
end

utils.clear_test_state = function()
  -- TODO: Clear internal state?
  vim.cmd("top new | wincmd o")
  local keepbufnr = vim.api.nvim_get_current_buf()
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
  assert.are.same(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":p"), vim.fn.fnamemodify(testfile, ":p"))
end

return utils

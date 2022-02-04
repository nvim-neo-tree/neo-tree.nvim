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
          {
            name = "bar",
            type = "dir",
            content = {
              { name = "baz1.txt", type = "file" },
              { name = "baz2.txt", type = "file" },
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

  local function makefs(content, basedir, relative_root_path)
    relative_root_path = relative_root_path or "."
    for _, info in ipairs(content) do
      local relative_path = relative_root_path .. "/" .. info.name
      -- create lookups
      fs.lookup[relative_path] = info
      if info.id then
        fs.lookup[info.id] = info
      end
      -- create actual files and directories
      if info.type == "dir" then
        info.abspath = Path:new(basedir, info.name):absolute()
        vim.fn.mkdir(info.abspath, "p")
        if info.content then
          makefs(info.content, info.abspath, relative_path)
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

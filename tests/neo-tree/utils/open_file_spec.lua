pcall(require, "luacov")

local utils = require("neo-tree.utils")
local u = require("tests.utils")
local uv = vim.uv or vim.loop

describe("open_file", function()
  local directory
  local hidden
  local cwd
  local state = { current_position = "current" }

  local function file(name)
    local path = utils.path_join(directory, name or "a.txt")
    u.fs.write_file(path, { "hello" })
    return path
  end

  before_each(function()
    directory = u.fs.create_temp_dir()
    cwd = vim.fn.getcwd()
    hidden = vim.o.hidden
    vim.o.hidden = true
    require("neo-tree").setup({})
    require("neo-tree").ensure_config()
  end)

  after_each(function()
    vim.cmd("silent! tabonly!")
    u.clear_environment()
    vim.api.nvim_set_current_dir(cwd)
    vim.o.hidden = hidden
    u.fs.remove_dir(directory, true)
  end)

  it("reuses an empty unnamed buffer when editing a new file", function()
    local empty_buffer = vim.api.nvim_get_current_buf()
    local path = file()

    utils.open_file(state, path)

    u.eq(empty_buffer, vim.api.nvim_get_current_buf())
    u.eq(path, vim.api.nvim_buf_get_name(0))
    u.assert_buf_lines(0, { "hello" })
  end)

  it("leaves only the opened file listed after a directory hijack", function()
    local path = file()
    vim.cmd.edit(directory)
    local manager = require("neo-tree.sources.manager")
    u.wait_for(function()
      local fs_state = manager.get_state("filesystem")
      return fs_state.tree and fs_state.tree:get_node(path) ~= nil
    end)
    vim.cmd("Neotree")
    local fs_state = manager.get_state("filesystem")
    require("neo-tree.ui.renderer").focus_node(fs_state, path)

    require("neo-tree.sources.common.commands").open(fs_state)

    u.eq(path, vim.api.nvim_buf_get_name(0))
    local listed = vim.fn.getbufinfo({ buflisted = 1 })
    u.eq(1, #listed)
    u.eq(path, listed[1].name)
  end)

  it("preserves modified unnamed buffers", function()
    local modified_buffer = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "unsaved text" })

    utils.open_file(state, file())

    assert.is_true(vim.bo[modified_buffer].buflisted)
    assert.is_true(vim.bo[modified_buffer].modified)
    u.assert_buf_lines(modified_buffer, { "unsaved text" })
  end)

  it("preserves named empty buffers", function()
    local named_buffer = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_name(named_buffer, utils.path_join(directory, "empty.txt"))

    utils.open_file(state, file())

    assert.is_true(vim.bo[named_buffer].buflisted)
    u.assert_buf_lines(named_buffer, { "" })
  end)

  it("switches to an existing buffer without losing its changes", function()
    local path = file()
    vim.cmd.edit(path)
    local existing_buffer = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "unsaved changes" })
    vim.cmd.enew()

    utils.open_file(state, path)

    u.eq(existing_buffer, vim.api.nvim_get_current_buf())
    u.assert_buf_lines(0, { "unsaved changes" })
    assert.is_true(vim.bo.modified)
  end)

  it("opens an explicitly selected unnamed buffer", function()
    local unnamed_buffer = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(unnamed_buffer, 0, -1, false, { "unnamed contents" })

    utils.open_file(state, "[No Name]", "edit", unnamed_buffer)

    u.eq(unnamed_buffer, vim.api.nvim_get_current_buf())
    u.assert_buf_lines(0, { "unnamed contents" })
  end)

  it("opens a new split when only the sidebar remains", function()
    local path = file()
    local original_window = vim.api.nvim_get_current_win()
    require("neo-tree.command").execute({ dir = directory })
    u.wait_for(function()
      local fs_state = require("neo-tree.sources.manager").get_state("filesystem")
      return fs_state.tree and fs_state.tree:get_node(path) ~= nil
    end)
    local fs_state = require("neo-tree.sources.manager").get_state("filesystem")
    vim.api.nvim_win_close(original_window, true)
    require("neo-tree.ui.renderer").focus_node(fs_state, path)

    require("neo-tree.sources.common.commands").open(fs_state)

    u.eq(path, vim.api.nvim_buf_get_name(0))
    u.eq(2, #vim.api.nvim_list_wins())
    assert.is_true(vim.api.nvim_win_is_valid(fs_state.winid))
  end)

  it("opens literal relative paths", function()
    local path = file("+file # % ' +.txt")
    vim.api.nvim_set_current_dir(directory)
    require("neo-tree").config.open_files_using_relative_paths = true

    utils.open_file(state, path)

    -- Windows may use an 8.3 alias for the temporary directory.
    u.eq(assert(uv.fs_realpath(path)), assert(uv.fs_realpath(vim.api.nvim_buf_get_name(0))))
    u.assert_buf_lines(0, { "hello" })
  end)

  for _, command in ipairs({ "split", "vsplit", "tabnew" }) do
    it("preserves the original buffer when opening with " .. command, function()
      local original_buffer = vim.api.nvim_get_current_buf()
      local path = file()

      utils.open_file(state, path, command)

      u.eq(path, vim.api.nvim_buf_get_name(0))
      assert.is_true(vim.bo[original_buffer].buflisted)
      u.eq(2, #vim.api.nvim_list_wins())
    end)
  end

  local names = { "file with spaces.txt", "file # % ' +.txt" }
  if not utils.is_windows then
    names[#names + 1] = "file | $HOME \\ bar.txt"
    names[#names + 1] = "file\nwith\nnewlines.txt"
  end
  for _, name in ipairs(names) do
    for _, command in ipairs({ "edit", "split", "vsplit", "tabnew" }) do
      it("opens literal filenames with " .. command .. ": " .. vim.inspect(name), function()
        local path = file(name)

        utils.open_file(state, path, command)

        u.eq(path, vim.api.nvim_buf_get_name(0))
        u.assert_buf_lines(0, { "hello" })
      end)
    end
  end
end)

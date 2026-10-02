local u = require("tests.utils")
local utils = require("neo-tree.utils")
local fs_actions = require("neo-tree.sources.filesystem.lib.fs_actions")
local uv = vim.uv or vim.loop

describe("Filesystem deletion", function()
  local root
  local original_execute_command = utils.execute_command
  local original_unlink = uv.fs_unlink

  local function directory_link(target, path)
    local flags = utils.is_windows and { junction = true } or nil
    local ok, err = uv.fs_symlink(target, path, flags)
    assert(ok, err)
    assert.are.equal("link", uv.fs_lstat(path).type)
  end

  before_each(function()
    require("neo-tree").setup({
      enable_git_status = false,
      enable_diagnostics = false,
      filesystem = { use_libuv_file_watcher = false },
    })
    require("neo-tree").ensure_config()
    root = u.fs.create_temp_dir()
    -- Exercise the fallback without relying on OS-specific permissions or tools.
    utils.execute_command = function()
      return false, { "native deletion unavailable" }
    end
  end)

  after_each(function()
    utils.execute_command = original_execute_command
    uv.fs_unlink = original_unlink
    u.clear_environment()
    u.fs.remove_dir(root, true)
  end)

  it("deletes only the directory link when native deletion is unavailable", function()
    local target = utils.path_join(root, "target")
    local marker = utils.path_join(target, "keep.txt")
    local link = utils.path_join(root, "shortcut")
    u.fs.write_file(marker, { "keep this content" })
    directory_link(target, link)

    local deleted
    fs_actions.delete_node(link, function(path)
      deleted = path
    end, true)

    assert.is_not_nil(uv.fs_stat(marker))
    assert.are.same({ "keep this content" }, vim.fn.readfile(marker))
    assert.is_nil(uv.fs_lstat(link))
    u.wait_for(function()
      return deleted ~= nil
    end)
    assert.are.equal(link, deleted)
  end)

  it("preserves the target when unlinking the directory link fails", function()
    local target = utils.path_join(root, "target")
    local marker = utils.path_join(target, "keep.txt")
    local link = utils.path_join(root, "shortcut")
    u.fs.write_file(marker, { "keep this content" })
    directory_link(target, link)
    uv.fs_unlink = function(path, ...)
      if path == link then
        return nil, "EACCES: permission denied"
      end
      return original_unlink(path, ...)
    end

    local deleted = false
    fs_actions.delete_node(link, function()
      deleted = true
    end, true)
    vim.wait(10)

    assert.is_not_nil(uv.fs_stat(marker))
    assert.are.same({ "keep this content" }, vim.fn.readfile(marker))
    assert.is_not_nil(uv.fs_lstat(link))
    assert.is_false(deleted)
  end)

  it("recursively deletes directories without following links inside them", function()
    local target = utils.path_join(root, "target")
    local marker = utils.path_join(target, "keep.txt")
    local directory = utils.path_join(root, "delete-me")
    u.fs.write_file(marker, { "keep this content" })
    u.fs.write_file(utils.path_join(directory, "nested", "remove.txt"), { "remove me" })
    directory_link(target, utils.path_join(directory, "shortcut"))

    fs_actions.delete_node(directory, nil, true)

    assert.is_nil(uv.fs_lstat(directory))
    assert.is_not_nil(uv.fs_stat(marker))
    assert.are.same({ "keep this content" }, vim.fn.readfile(marker))
  end)
end)

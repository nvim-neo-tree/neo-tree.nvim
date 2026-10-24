local u = require("tests.utils")
local verify = require("tests.utils.verify")
local renderer = require("neo-tree.ui.renderer")
local UniversalBackend = require("neo-tree.clipboard.sync.universal")
local clipboard = require("neo-tree.clipboard")
local uv = vim.uv or vim.loop

describe("Universal clipboard", function()
  local test = u.fs.init_test({
    items = {
      { name = "topfile1.txt", type = "file", id = "topfile1" },
    },
  })

  test.setup()

  local original_new_fs_event = uv.new_fs_event
  local original_update_states = clipboard.update_states
  local event_test_dir

  ---Closes the fs_event handles the backend opens while loading, so that they
  ---do not outlive the test.
  local close_handles = function()
    for filename, handle in pairs(UniversalBackend.handles or {}) do
      if not handle:is_closing() then
        handle:close()
      end
      UniversalBackend.handles[filename] = nil
    end
  end

  after_each(function()
    uv.new_fs_event = original_new_fs_event
    clipboard.update_states = original_update_states
    close_handles()
    if event_test_dir then
      u.fs.remove_dir(event_test_dir, true)
      event_test_dir = nil
    end
    u.clear_environment()
  end)

  it("synchronizes the first external update to a newly created clipboard file", function()
    event_test_dir = u.fs.create_temp_dir()
    local reader = assert(UniversalBackend:new({ dir = event_test_dir }))
    local state = { name = "first_event", clipboard = {} }
    local on_event
    uv.new_fs_event = function()
      local closed = false
      return {
        start = function(_, _, _, callback)
          on_event = callback
          return 0
        end,
        is_active = function()
          return not closed
        end,
        is_closing = function()
          return closed
        end,
        close = function()
          closed = true
        end,
      }
    end
    local updates = 0
    clipboard.update_states = function()
      updates = updates + 1
    end

    local loaded, err = reader:load(state)
    assert.is_nil(err)
    assert.is_nil(loaded)
    assert.is_nil(reader.last_stat_seen)

    local contents = { file = { action = "copy", node = { id = "file", name = "file" } } }
    u.fs.write_file(reader:get_filename(state), {
      vim.json.encode({ state_name = state.name, contents = contents }),
    })
    assert.is_function(on_event)
    on_event(nil)
    assert.are.equal(1, updates)
    u.eq(contents, reader:load(state))

    on_event(nil)
    assert.are.equal(1, updates)
  end)

  it("should save a clipboard that survives a round-trip through json", function()
    require("neo-tree").setup({})

    vim.cmd("Neotree")
    u.wait_for_neo_tree()
    local state = assert(verify.get_state())

    local topfile = assert(test.fs_tree.lookup["topfile1"])
    renderer.focus_node(state, topfile.abspath)
    verify.filesystem_tree_node_is(topfile.abspath)

    local wait = u.changedtick_waiter()
    u.feedkeys("y")
    wait()

    -- Only the fields that paste_from_clipboard and the clipboard component
    -- read are kept, so that the clipboard stays serializable no matter what
    -- nui puts on its nodes.
    local node = assert(state.tree:get_node())
    u.eq(vim.tbl_count(state.clipboard), 1)
    u.eq(state.clipboard[node:get_id()], {
      action = "copy",
      node = {
        id = node:get_id(),
        name = "topfile1.txt",
        path = node:get_id(),
        type = "file",
      },
    })

    local dir = u.fs.create_temp_dir()
    local writer = assert(UniversalBackend:new({ dir = dir }))
    local saved, save_err = writer:save(state)
    assert(saved, save_err)

    -- A separate backend has no cached clipboard, so this reads the file back.
    local reader = assert(UniversalBackend:new({ dir = dir }))
    local loaded, load_err = reader:load(state)
    assert(loaded, load_err)
    u.eq(loaded, state.clipboard)

    close_handles()
    u.fs.remove_dir(dir, true)
  end)

  test.teardown()
end)

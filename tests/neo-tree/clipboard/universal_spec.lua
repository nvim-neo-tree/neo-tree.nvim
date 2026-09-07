local u = require("tests.utils")
local verify = require("tests.utils.verify")
local renderer = require("neo-tree.ui.renderer")
local UniversalBackend = require("neo-tree.clipboard.sync.universal")

describe("Universal clipboard", function()
  local test = u.fs.init_test({
    items = {
      { name = "topfile1.txt", type = "file", id = "topfile1" },
    },
  })

  test.setup()

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
    close_handles()
    u.clear_environment()
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

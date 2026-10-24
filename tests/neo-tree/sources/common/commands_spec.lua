pcall(require, "luacov")

local u = require("tests.utils")
local utils = require("neo-tree.utils")
local renderer = require("neo-tree.ui.renderer")
local commands = require("neo-tree.sources.common.commands")

describe("commands on the top blank line", function()
  local root, state

  before_each(function()
    root = utils.normalize_path(assert((vim.uv or vim.loop).fs_realpath(u.fs.create_temp_dir())))
    u.fs.write_file(utils.path_join(root, "file.txt"), { "test" })
    u.fs.write_file(utils.path_join(root, "folder", "child.txt"), { "child" })
    require("neo-tree").setup({
      add_blank_line_at_top = true,
      enable_git_status = false,
      enable_diagnostics = false,
      enable_modified_markers = false,
      enable_opened_markers = false,
      filesystem = { use_libuv_file_watcher = false },
    })
    require("neo-tree.command").execute({ source = "filesystem", dir = root })
    u.wait_for(function()
      state = require("neo-tree.sources.manager").get_state("filesystem")
      return state and state._ready and state.tree and state.tree:get_node(root)
    end)
    vim.api.nvim_set_current_win(state.winid)
    vim.api.nvim_win_set_cursor(state.winid, { 1, 0 })
    assert.are.same({ "" }, vim.api.nvim_buf_get_lines(state.bufnr, 0, 1, false))
    assert.is_nil(state.tree:get_node())
    local file = utils.path_join(root, "file.txt")
    state.clipboard[file] = {
      action = "copy",
      node = { id = file, path = file, name = "file.txt", type = "file" },
    }
  end)

  after_each(function()
    require("neo-tree.sources.common.preview").hide()
    u.clear_environment()
    u.fs.remove_dir(root, true)
  end)

  local function snapshot()
    return {
      lines = u.buflines(state.bufnr),
      expanded = renderer.get_expanded_nodes(state.tree),
      selected = vim.deepcopy(state.selected),
      clipboard = vim.deepcopy(state.clipboard),
      undo_count = #state.undostack,
      winid = vim.api.nvim_get_current_win(),
      windows = vim.api.nvim_list_wins(),
      buffers = vim.api.nvim_list_bufs(),
      cursor = vim.api.nvim_win_get_cursor(state.winid),
    }
  end

  for _, name in ipairs({
    "add",
    "add_directory",
    "expand_all_subnodes",
    "close_node",
    "close_all_subnodes",
    "copy_to_clipboard",
    "cut_to_clipboard",
    "paste_from_clipboard",
    "git_add_file",
    "git_unstage_file",
    "git_toggle_file_stage",
    "git_revert_file",
    "show_file_details",
    "select",
    "copy",
    "move",
    "delete",
    "trash",
    "restore_from_trash",
    "preview",
    "toggle_preview",
    "toggle_node",
    "toggle_directory",
    "open",
    "open_split",
    "open_vsplit",
    "open_tabnew",
    "rename",
    "rename_basename",
  }) do
    it("ignores " .. name .. " without changing state", function()
      local before = snapshot()
      commands[name](state)
      assert.are.same(before, snapshot())
    end)
  end

  for _, name in ipairs({ "next_git_modified", "prev_git_modified" }) do
    it("ignores filesystem " .. name, function()
      local before = snapshot()
      require("neo-tree.sources.filesystem.commands")[name](state)
      assert.are.same(before, snapshot())
    end)
  end

  for _, name in ipairs({ "open", "jump_to_symbol", "show_symbol", "rename" }) do
    it("ignores document_symbols " .. name, function()
      local before = snapshot()
      require("neo-tree.sources.document_symbols.commands")[name](state)
      assert.are.same(before, snapshot())
    end)
  end

  it("ignores node mappings on the blank line", function()
    local before = snapshot()
    for _, key in ipairs({ "<cr>", "<space>", "<Tab>", "y", "x", "p", "c", "m", "r", "d", "a", "P" }) do
      state.resolved_mappings[key].handler()
      assert.are.same(before, snapshot(), key)
    end
  end)

  it("still applies clipboard mappings to tagged nodes", function()
    local file = utils.path_join(root, "file.txt")
    state.clipboard = {}
    state.selected[file] = true
    state.resolved_mappings["y"].handler()
    assert.are.equal("copy", state.clipboard[file].action)
    assert.are.equal(file, state.clipboard[file].node.path)
    assert.are.same({ 1, 0 }, vim.api.nvim_win_get_cursor(state.winid))
  end)

  it("still closes the window from the blank line", function()
    local winid = state.winid
    state.resolved_mappings["q"].handler()
    assert.is_false(vim.api.nvim_win_is_valid(winid))
  end)

  it("still refreshes from the blank line", function()
    local added = utils.path_join(root, "added.txt")
    u.fs.write_file(added, { "new" })
    state.resolved_mappings["R"].handler()
    u.wait_for(function()
      return state.tree:get_node(added) ~= nil
    end)
  end)

  it("still toggles and selects normal nodes", function()
    local folder = utils.path_join(root, "folder")
    assert.is_true(renderer.focus_node(state, folder))
    assert.is_false(state.tree:get_node(folder):is_expanded())
    state.resolved_mappings["<space>"].handler()
    u.wait_for(function()
      return state.tree:get_node(folder):is_expanded()
    end)
    state.resolved_mappings["<Tab>"].handler()
    assert.is_true(state.selected[folder])
    state.resolved_mappings["<space>"].handler()
    assert.is_false(state.tree:get_node(folder):is_expanded())
  end)

  it("still toggles an explicit node while the cursor is on the blank line", function()
    local folder = state.tree:get_node(utils.path_join(root, "folder"))
    local toggled
    commands.toggle_node(state, function(node)
      toggled = node
    end, folder)
    assert.are.equal(folder, toggled)
    assert.are.same({ 1, 0 }, vim.api.nvim_win_get_cursor(state.winid))
  end)

  it("still opens a normal file", function()
    local file = utils.path_join(root, "file.txt")
    assert.is_true(renderer.focus_node(state, file))
    state.resolved_mappings["<cr>"].handler()
    assert.are.equal(file, utils.normalize_path(vim.api.nvim_buf_get_name(0)))
  end)
end)

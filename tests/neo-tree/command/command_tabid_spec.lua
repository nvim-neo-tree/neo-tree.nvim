pcall(require, "luacov")

local u = require("tests.utils")

local command = require("neo-tree.command")
local manager = require("neo-tree.sources.manager")

local function tab_has_neo_tree(tabid)
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(tabid)) do
    local bufnr = vim.api.nvim_win_get_buf(winid)
    if vim.bo[bufnr].filetype == "neo-tree" then
      return true
    end
  end

  return false
end

local function setup_2_tabs()
  local tab1 = vim.api.nvim_get_current_tabpage()
  local win1 = vim.api.nvim_get_current_win()

  vim.cmd.tabnew()

  local tab2 = vim.api.nvim_get_current_tabpage()
  local win2 = vim.api.nvim_get_current_win()

  u.neq(tab1, tab2)
  u.neq(win1, win2)

  vim.api.nvim_set_current_tabpage(tab1)

  return {
    tab1 = tab1,
    tab2 = tab2,
    win1 = win1,
    win2 = win2,
  }
end

local function tab_state_is_ready(tabid)
  local state = manager.get_state("filesystem", tabid)
  return state.winid ~= nil and state.tree ~= nil and state._ready == true
end

describe("Command tab targeting", function()
  local test = u.fs.init_test({
    items = {
      {
        name = "foo",
        type = "dir",
        items = {
          { name = "foofile1.txt", type = "file" },
        },
      },
      { name = "topfile1.txt", type = "file", id = "topfile1" },
    },
  })

  test.setup()

  local fs_tree = test.fs_tree

  before_each(function()
    u.eq(1, #vim.api.nvim_list_wins())
    u.eq(1, #vim.api.nvim_list_tabpages())
    vim.cmd.lcd(fs_tree.abspath)
    vim.cmd.tcd(fs_tree.abspath)
    vim.cmd.cd(fs_tree.abspath)
  end)

  after_each(function()
    u.clear_environment()
  end)

  it("can show and close neo-tree in another tab without changing the current context", function()
    local ctx = setup_2_tabs()
    local original_tab = vim.api.nvim_get_current_tabpage()
    local original_win = vim.api.nvim_get_current_win()
    local original_buf = vim.api.nvim_get_current_buf()

    command.execute({
      action = "show",
      source = "filesystem",
      position = "left",
      tabid = ctx.tab2,
    })

    u.wait_for(function()
      return tab_has_neo_tree(ctx.tab2)
    end, { timeout = 2000, timeout_message = "Neo-tree did not open in the target tab" })
    u.wait_for(function()
      return tab_state_is_ready(ctx.tab2)
    end, { timeout = 2000, timeout_message = "Neo-tree state did not become ready in the target tab" })

    u.eq(original_tab, vim.api.nvim_get_current_tabpage())
    u.eq(original_win, vim.api.nvim_get_current_win())
    u.eq(original_buf, vim.api.nvim_get_current_buf())
    u.eq(false, tab_has_neo_tree(ctx.tab1))

    command.execute({
      action = "close",
      source = "filesystem",
      position = "left",
      tabid = ctx.tab2,
    })

    u.wait_for(function()
      return not tab_has_neo_tree(ctx.tab2)
    end, { timeout = 2000, timeout_message = "Neo-tree did not close in the target tab" })

    u.eq(original_tab, vim.api.nvim_get_current_tabpage())
    u.eq(original_win, vim.api.nvim_get_current_win())
    u.eq(original_buf, vim.api.nvim_get_current_buf())
  end)
end)

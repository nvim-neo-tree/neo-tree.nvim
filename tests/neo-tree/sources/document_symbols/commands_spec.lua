pcall(require, "luacov")

local u = require("tests.utils")
local treesitter_utils = require("tests.utils.treesitter")
local lsp_utils = require("tests.utils.lsp")
local verify = require("tests.utils.verify")

if vim.fn.has("nvim-0.11") == 0 then
  -- Skip on versions below 0.11 due to requiring treesitter parsers
  return
end
describe("document_symbols commands", function()
  treesitter_utils.ensure_parser("lua")
  lsp_utils.enable_lua_ls()
  before_each(function()
    u.clear_environment()
  end)

  after_each(function()
    u.clear_environment()
  end)

  describe("show_symbol", function()
    it("should scroll to symbol without changing window focus", function()
      -- Create a test file with a function
      local test_file = vim.fn.tempname() .. ".lua"
      local lines = {
        "-- Test file",
        "",
        "function test_function()",
        "  return 42",
        "end",
        "",
        "local function another_function()",
        "  return 'hello'",
        "end",
      }
      vim.fn.writefile(lines, test_file)

      -- Open the file in the main window
      vim.cmd("edit " .. test_file)
      local main_win = vim.api.nvim_get_current_win()
      local main_buf = vim.api.nvim_get_current_buf()
      u.wait_for(function()
        return #vim.lsp.get_clients({ bufnr = main_buf }) > 0
      end)

      -- Open neo-tree with document_symbols
      require("neo-tree").setup({
        sources = { "document_symbols" },
      })
      vim.cmd("Neotree document_symbols right")
      u.wait_for_neo_tree()

      -- Get the neo-tree window
      local neo_tree_win = vim.api.nvim_get_current_win()
      assert.are_not.equal(main_win, neo_tree_win, "Focus should be in neo-tree window")

      -- Wait for document symbols to be populated
      u.wait_for(function()
        local state = require("neo-tree.sources.manager").get_state("document_symbols")
        return state and state.tree and state.tree:get_node() ~= nil
      end)

      -- Get the current state
      local manager = require("neo-tree.sources.manager")
      local state = manager.get_state("document_symbols")

      -- Move to the first child node (should be a function)
      vim.cmd("normal! j")
      u.wait_for(function()
        local node = state.tree:get_node()
        return node and node:get_depth() > 1
      end)

      -- Get neo-tree window before preview
      local neo_win_before = vim.api.nvim_get_current_win()

      -- Get current cursor position in target window before preview
      local cursor_before = vim.api.nvim_win_get_cursor(main_win)

      -- Call show_symbol
      local commands = require("neo-tree.sources.document_symbols.commands")
      commands.show_symbol(state)

      -- Wait for the preview to complete
      vim.wait(100)

      -- Verify: focus should still be in neo-tree window
      local current_win = vim.api.nvim_get_current_win()
      assert.are.equal(neo_win_before, current_win, "Focus should remain in neo-tree after preview")

      -- Verify: target window cursor should have moved
      local cursor_after = vim.api.nvim_win_get_cursor(main_win)
      assert.are_not.equal(
        cursor_before[1],
        cursor_after[1],
        "Target window cursor should have moved"
      )

      -- Cleanup
      vim.fn.delete(test_file)
    end)
  end)

  describe("follow_tree_cursor", function()
    it("should auto-show when cursor moves in tree", function()
      -- Create a test file with multiple functions
      local test_file = vim.fn.tempname() .. ".lua"
      local lines = {
        "-- Test file",
        "",
        "function first_function()",
        "  return 1",
        "end",
        "",
        "function second_function()",
        "  return 2",
        "end",
        "",
        "function third_function()",
        "  return 3",
        "end",
      }
      vim.fn.writefile(lines, test_file)

      -- Open the file
      vim.cmd("edit " .. test_file)
      local main_win = vim.api.nvim_get_current_win()
      local main_buf = vim.api.nvim_get_current_buf()
      u.wait_for(function()
        return #vim.lsp.get_clients({ bufnr = main_buf }) > 0
      end)

      -- Setup neo-tree with follow_tree_cursor enabled
      require("neo-tree").setup({
        sources = { "document_symbols" },
        document_symbols = {
          follow_tree_cursor = true,
        },
      })

      -- Open neo-tree with document_symbols
      vim.cmd("Neotree document_symbols right")
      u.wait_for_neo_tree()

      -- Get neo-tree window
      local neo_tree_win = vim.api.nvim_get_current_win()

      -- Wait for symbols to load
      local state
      u.wait_for(function()
        state = require("neo-tree.sources.manager").get_state("document_symbols")
        return state and state.tree and state.tree:get_node() ~= nil
      end)
      -- Headless workaround, bufenter doesn't fire initally
      vim.api.nvim_exec_autocmds("BufEnter", { buffer = state.bufnr })

      -- Record initial cursor position in target window
      local initial_cursor = vim.api.nvim_win_get_cursor(main_win)

      -- Move to first function symbol
      vim.cmd("normal! j")
      u.wait_for(function()
        local node = state.tree:get_node()
        return node and node:get_depth() > 1
      end)
      vim.api.nvim_exec_autocmds("CursorMoved", {})

      -- Wait for auto-show
      vim.wait(150)

      -- Verify focus is still in neo-tree
      assert.are.equal(
        neo_tree_win,
        vim.api.nvim_get_current_win(),
        "Focus should remain in neo-tree"
      )

      -- Verify target window has moved from initial position
      local current_cursor = vim.api.nvim_win_get_cursor(main_win)
      assert.are_not.equal(
        initial_cursor[1],
        current_cursor[1],
        "Target window should have scrolled"
      )

      -- Move to another function
      vim.cmd("normal! j")
      vim.api.nvim_exec_autocmds("CursorMoved", {})
      vim.wait(150)

      -- Verify focus is still in neo-tree
      assert.are.equal(
        neo_tree_win,
        vim.api.nvim_get_current_win(),
        "Focus should remain in neo-tree after second move"
      )

      -- Verify target window has moved again
      local second_cursor = vim.api.nvim_win_get_cursor(main_win)
      assert.are_not.equal(
        current_cursor[1],
        second_cursor[1],
        "Target window should have scrolled again"
      )

      -- Cleanup
      vim.fn.delete(test_file)
    end)

    it("should not auto-show when follow_tree_cursor is disabled", function()
      -- Create a test file
      local test_file = vim.fn.tempname() .. ".lua"
      local lines = {
        "-- Test file",
        "function test_function()",
        "  return 42",
        "end",
      }
      vim.fn.writefile(lines, test_file)

      -- Open the file
      vim.cmd("edit " .. test_file)
      local main_win = vim.api.nvim_get_current_win()

      -- Setup neo-tree with follow_tree_cursor disabled (default)
      require("neo-tree").setup({
        sources = { "document_symbols" },
        document_symbols = {
          follow_tree_cursor = false,
        },
      })

      -- Open neo-tree
      vim.cmd("Neotree document_symbols right")
      u.wait_for_neo_tree()

      -- Wait for symbols to load
      u.wait_for(function()
        local state = require("neo-tree.sources.manager").get_state("document_symbols")
        return state and state.tree and state.tree:get_node() ~= nil
      end)

      -- Record cursor position
      local initial_cursor = vim.api.nvim_win_get_cursor(main_win)

      -- Move in tree
      vim.cmd("normal! j")
      vim.wait(150)

      -- Verify target window cursor has NOT moved
      local current_cursor = vim.api.nvim_win_get_cursor(main_win)
      assert.are.equal(
        initial_cursor[1],
        current_cursor[1],
        "Target window should NOT have scrolled when follow_tree_cursor is disabled"
      )

      -- Cleanup
      vim.fn.delete(test_file)
    end)

    it("should not trigger errors when switching between sources", function()
      -- Create test files
      local test_file = vim.fn.tempname() .. ".lua"
      local lines = {
        "-- Test file",
        "function test_function()",
        "  return 42",
        "end",
      }
      vim.fn.writefile(lines, test_file)

      -- Setup neo-tree with follow_tree_cursor enabled
      require("neo-tree").setup({
        sources = { "filesystem", "document_symbols" },
        document_symbols = {
          follow_tree_cursor = true,
        },
      })

      -- Open file
      vim.cmd("edit " .. test_file)

      -- Open filesystem source
      vim.cmd("Neotree filesystem right")
      u.wait_for_neo_tree()

      -- Verify filesystem is open
      local fs_state = require("neo-tree.sources.manager").get_state("filesystem")
      assert.is_not_nil(fs_state, "Filesystem should be open")

      -- Switch to document_symbols
      vim.cmd("Neotree document_symbols")
      u.wait_for_neo_tree()

      -- Wait for symbols to load
      u.wait_for(function()
        local state = require("neo-tree.sources.manager").get_state("document_symbols")
        return state and state.tree and state.tree:get_node() ~= nil
      end)

      -- Switch back to filesystem - this should NOT trigger document_symbols errors
      vim.cmd("Neotree filesystem")
      u.wait_for_neo_tree()

      -- Move cursor in filesystem tree (using j/k)
      -- This previously caused errors because CursorMoved autocmd was not properly isolated
      vim.cmd("normal! j")
      vim.wait(50)
      vim.cmd("normal! k")
      vim.wait(50)

      -- If we get here without errors, the test passes
      -- The bug was that document_symbols CursorMoved autocmd was firing for filesystem buffer

      -- Cleanup
      vim.fn.delete(test_file)
    end)
  end)
end)

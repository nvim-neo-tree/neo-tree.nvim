---A generalization of the filter functionality to directly filter the
---source tree instead of relying on pre-filtered data, which is specific
---to the filesystem source.
local Input = require("nui.input")
local event = require("nui.utils.autocmd").event
local popups = require("neo-tree.ui.popups")
local renderer = require("neo-tree.ui.renderer")
local utils = require("neo-tree.utils")
local compat = require("neo-tree.utils._compat")
local log = require("neo-tree.log")
local manager = require("neo-tree.sources.manager")
local fzy = require("neo-tree.sources.common.filters.filter_fzy")

local M = {}

---Reset the current filter to the empty string.
---@param state neotree.State
---@param refresh boolean? whether to refresh the source tree
---@param open_current_node boolean? whether to open the current node
local reset_filter = function(state, refresh, open_current_node)
  log.trace("reset_search")
  if refresh == nil then
    refresh = true
  end

  -- Cancel any pending search
  require("neo-tree.sources.filesystem.lib.filter_external").cancel()

  -- reset search state
  if state.open_folders_before_search then
    state.force_open_folders = vim.deepcopy(state.open_folders_before_search, compat.noref())
  else
    state.force_open_folders = nil
  end
  state.open_folders_before_search = nil
  state.search_pattern = nil

  if open_current_node then
    local success, node = pcall(state.tree.get_node, state.tree)
    if success and node then
      local id = node:get_id()
      renderer.position.set(state, id)
      id = utils.remove_trailing_slash(id)
      manager.navigate(state, nil, id, utils.wrap(pcall, renderer.focus_node, state, id, false))
    end
  elseif refresh then
    manager.navigate(state)
  else
    state.tree = vim.deepcopy(state.orig_tree)
  end
  state.orig_tree = nil
end

---Show the filtered tree
---@param state any
---@param do_not_focus_window boolean? whether to focus the window
local show_filtered_tree = function(state, do_not_focus_window)
  state.tree = vim.deepcopy(state.orig_tree)
  state.tree:get_nodes()[1].search_pattern = state.search_pattern
  local max_score, max_id = fzy.get_score_min(), nil
  local function filter_tree(node_id)
    local node = state.tree:get_node(node_id)
    local path = node.extra.search_path or node.path

    local should_keep = fzy.has_match(state.search_pattern, path)
    if should_keep then
      local score = fzy.score(state.search_pattern, path)
      node.extra.fzy_score = score
      if score > max_score then
        max_score = score
        max_id = node_id
      end
    end

    if node:has_children() then
      for _, child_id in ipairs(node:get_child_ids()) do
        should_keep = filter_tree(child_id) or should_keep
      end
    end
    if not should_keep then
      state.tree:remove_node(node_id) -- TODO: this might not be efficient
    end
    return should_keep
  end
  if #state.search_pattern > 0 then
    for _, root in ipairs(state.tree:get_nodes()) do
      filter_tree(root:get_id())
    end
  end
  manager.redraw(state.name)
  if max_id then
    renderer.focus_node(state, max_id, do_not_focus_window)
  end
end

---Main entry point for the filter functionality.
---This will display a filter input popup and filter the source tree on change and on submit
---@param state neotree.State the source state
---@param search_as_you_type boolean? whether to filter as you type or only on submit
---@param keep_filter_on_submit boolean? whether to keep the filter on <CR> or reset it
M.show_filter = function(state, search_as_you_type, keep_filter_on_submit)
  local winid = vim.api.nvim_get_current_win()
  local height = vim.api.nvim_win_get_height(winid)
  local scroll_padding = 3

  -- setup the input popup options
  local popup_msg = "Search:"
  if search_as_you_type then
    popup_msg = "Filter:"
  end
  if state.config.title then
    popup_msg = state.config.title
  end

  local width = vim.fn.winwidth(0) - 2
  local row = height - 3
  if state.current_position == "float" then
    scroll_padding = 0
    width = vim.fn.winwidth(winid)
    row = height - 2
    vim.api.nvim_win_set_height(winid, row)
  end

  state.orig_tree = vim.deepcopy(state.tree)

  local popup_options = popups.popup_options(popup_msg, width, {
    relative = "win",
    winid = winid,
    position = {
      row = row,
      col = 0,
    },
    size = width,
  })

  local has_pre_search_folders = utils.truthy(state.open_folders_before_search)
  if not has_pre_search_folders then
    log.trace("No search or pre-search folders, recording pre-search folders now")
    state.open_folders_before_search = renderer.get_expanded_nodes(state.tree)
  end

  local waiting_for_default_value = utils.truthy(state.search_pattern)
  local input = Input(popup_options, {
    prompt = " ",
    default_value = state.search_pattern,
    on_submit = function(value)
      if value == "" then
        reset_filter(state)
        return
      end
      if search_as_you_type and not keep_filter_on_submit then
        reset_filter(state, true, true)
        return
      end
      -- do the search
      state.search_pattern = value
      show_filtered_tree(state, false)
    end,
    --this can be bad in a deep folder structure
    on_change = function(value)
      if not search_as_you_type then
        return
      end
      -- apparently when a default value is set, on_change fires for every character
      if waiting_for_default_value then
        if #value < #state.search_pattern then
          return
        end
        waiting_for_default_value = false
      end
      if value == state.search_pattern or value == nil then
        return
      end

      -- finally do the search
      log.trace("Setting search in on_change to:", value)
      state.search_pattern = value
      local len_to_delay = { [0] = 500, 500, 400, 200 }
      local delay = len_to_delay[#value] or 100

      utils.debounce(state.name .. "_filter", function()
        show_filtered_tree(state, true)
      end, delay, utils.debounce_strategy.CALL_LAST_ONLY)
    end,
  })

  input:mount()

  local restore_height = vim.schedule_wrap(function()
    if vim.api.nvim_win_is_valid(winid) then
      vim.api.nvim_win_set_height(winid, height)
    end
  end)

  ---@alias neotree.FuzzyFinder.BuiltinCommandNames
  ---|"move_cursor_down"
  ---|"move_cursor_up"
  ---|"close"
  ---|"close_clear_filter"
  ---|"close_keep_filter"
  ---|neotree.FuzzyFinder.FalsyMappingNames

  ---@alias neotree.FuzzyFinder.CommandFunction fun(state: neotree.State, scroll_padding: integer):string?

  ---@class neotree.FuzzyFinder.BuiltinCommands
  ---@field [string] neotree.FuzzyFinder.CommandFunction?
  local cmds
  cmds = {
    move_cursor_down = function(state_, scroll_padding_)
      renderer.focus_node(state_, nil, true, 1, scroll_padding_)
    end,

    move_cursor_up = function(state_, scroll_padding_)
      renderer.focus_node(state_, nil, true, -1, scroll_padding_)
      vim.cmd("redraw!")
    end,

    close = function(_state)
      vim.cmd("stopinsert")
      input:unmount()
      if utils.truthy(_state.search_pattern) then
        reset_filter(_state, true)
      end
      restore_height()
    end,

    close_keep_filter = function(_state, _scroll_padding)
      log.info("Persisting the search filter")
      keep_filter_on_submit = true
      cmds.close(_state, _scroll_padding)
    end,
    close_clear_filter = function(_state, _scroll_padding)
      log.info("Clearing the search filter")
      keep_filter_on_submit = false
      cmds.close(_state, _scroll_padding)
    end,
  }

  M.setup_hooks(input, cmds, state, scroll_padding)
  M.setup_mappings(input, cmds, state, scroll_padding)
end

---@param input NuiInput
---@param cmds neotree.FuzzyFinder.BuiltinCommands
---@param state neotree.State
---@param scroll_padding integer
function M.setup_hooks(input, cmds, state, scroll_padding)
  input:on(
    { event.BufLeave, event.BufDelete },
    utils.wrap(cmds.close, state, scroll_padding),
    { once = true }
  )

  -- hacky bugfix for quitting from the filter window
  input:on("QuitPre", function()
    if vim.api.nvim_get_current_win() ~= input.winid then
      return
    end
    ---'confirm' can cause blocking user input on exit, so this hack disables it.
    local old_confirm = vim.o.confirm
    vim.o.confirm = false
    vim.schedule(function()
      vim.o.confirm = old_confirm
    end)
  end)
end

---@enum neotree.FuzzyFinder.FalsyMappingNames
M._falsy_mapping_names = { "noop", "none" }

---@alias neotree.FuzzyFinder.CommandOrName neotree.FuzzyFinder.CommandFunction|neotree.FuzzyFinder.BuiltinCommandNames

---@class neotree.FuzzyFinder.VerboseCommand
---@field [1] neotree.FuzzyFinder.Command
---@field [2] vim.keymap.set.Opts?
---@field raw boolean?

---@alias neotree.FuzzyFinder.Command neotree.FuzzyFinder.CommandOrName|neotree.FuzzyFinder.VerboseCommand|string

---@class neotree.FuzzyFinder.SimpleMappings : neotree.SimpleMappings
---@field [string] neotree.FuzzyFinder.Command?

---@class neotree.Config.FuzzyFinder.Mappings : neotree.FuzzyFinder.SimpleMappings, neotree.Mappings
---@field [integer] table<string, neotree.FuzzyFinder.SimpleMappings>

---@param input NuiInput
---@param cmds neotree.FuzzyFinder.BuiltinCommands
---@param state neotree.State
---@param scroll_padding integer
---@param mappings neotree.FuzzyFinder.SimpleMappings
---@param mode string
local function apply_simple_mappings(input, cmds, state, scroll_padding, mode, mappings)
  ---@param command neotree.FuzzyFinder.CommandFunction
  ---@return function
  local function setup_command(command)
    return utils.wrap(command, state, scroll_padding)
  end
  for lhs, rhs in pairs(mappings) do
    if type(lhs) == "string" then
      ---@cast rhs neotree.FuzzyFinder.Command
      local cmd, raw, opts
      if type(rhs) == "table" then
        ---type doesn't narrow properly
        ---@cast rhs -neotree.FuzzyFinder.FalsyMappingNames
        raw = rhs.raw
        opts = vim.deepcopy(rhs)
        opts[1] = nil
        opts.raw = nil
        cmd = rhs[1]
      else
        ---type also doesn't narrow properly
        ---@cast rhs -neotree.FuzzyFinder.VerboseCommand
        cmd = rhs
      end

      local cmdtype = type(cmd)
      if cmdtype == "string" then
        if raw then
          input:map(mode, lhs, cmd, opts)
        else
          local command = cmds[cmd]
          if command then
            input:map(mode, lhs, setup_command(command), opts)
          elseif not vim.tbl_contains(M._falsy_mapping_names, cmd) then
            log.at.warn.format("Invalid command in fuzzy_finder_mappings: ['%s'] = '%s'", lhs, cmd)
          end
        end
      elseif cmdtype == "function" then
        ---@cast cmd -neotree.FuzzyFinder.VerboseCommand
        input:map(mode, lhs, setup_command(cmd), opts)
      end
    end
  end
end

---@param input NuiInput
---@param cmds neotree.FuzzyFinder.BuiltinCommands
---@param state neotree.State
---@param scroll_padding integer
function M.setup_mappings(input, cmds, state, scroll_padding)
  local config = require("neo-tree").config

  local ff_mappings = config.filesystem.window.fuzzy_finder_mappings or {}
  apply_simple_mappings(input, cmds, state, scroll_padding, "i", ff_mappings)

  for _, mappings_by_mode in ipairs(ff_mappings) do
    for mode, mappings in pairs(mappings_by_mode) do
      apply_simple_mappings(input, cmds, state, scroll_padding, mode, mappings)
    end
  end
end

return M

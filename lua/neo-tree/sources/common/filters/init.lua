---A generalization of the filter functionality to directly filter the
---source tree instead of relying on pre-filtered data, which is specific
---to the filesystem source.
local vim = vim
local Input = require("nui.input")
local event = require("nui.utils.autocmd").event
local popups = require("neo-tree.ui.popups")
local renderer = require("neo-tree.ui.renderer")
local utils = require("neo-tree.utils")
local log = require("neo-tree.log")
local manager = require("neo-tree.sources.manager")
local fzy = require("neo-tree.sources.common.filters.filter_fzy")

local M = {}

local cmds = {
  move_cursor_down = function(state, scroll_padding)
    renderer.focus_node(state, nil, true, 1, scroll_padding)
  end,

  move_cursor_up = function(state, scroll_padding)
    renderer.focus_node(state, nil, true, -1, scroll_padding)
    vim.cmd("redraw!")
  end,
}

local sort_by_score = function(state, a, b)
  -- `state.fzy_sort_result_scores` should be defined in
  -- `sources.filesystem.lib.filter_external.fzy_sort_files`
  local result_scores = state.fzy_sort_result_scores or { foo = 0, baz = 0 }
  local a_score = result_scores[a.path]
  local b_score = result_scores[b.path]
  if a_score == nil or b_score == nil then
    log.debug(
      string.format([[Fzy: failed to compare %s: %s, %s: %s]], a.path, a_score, b.path, b_score)
    )
    local config = require("neo-tree").config
    if config.sort_function ~= nil then
      return config.sort_function(a, b)
    end
    return nil
  end
  return a_score > b_score
end

---Reset the current filter to the empty string.
---@param state any
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
  state.fuzzy_finder_mode = nil
  state.fzy_sort_file_list_cache = nil
  state.fzy_sort_result_scores = nil
  state.open_folders_before_search = nil
  state.search_pattern = nil
  state.sort_function_override = nil
  state.use_fzy = nil
  state.force_open_folders = state.open_folders_before_search
      and vim.deepcopy(state.open_folders_before_search, { noref = 1 })
    or nil

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
local show_filtered_tree = function(state, do_not_focus_window)
  state.tree = vim.deepcopy(state.orig_tree)
  local max_score, max_id = fzy.get_score_min(), nil
  local function filter_tree(node_id)
    local node = state.tree:get_node(node_id)
    local path = node.extra.search_path or node.path

    local should_keep = fzy.has_match(state.search_pattern, path)
    if should_keep then
      local score = fzy.score(state.search_pattern, path)
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

M.show_filter = function(state, search_as_you_type, fuzzy_finder_mode)
  local winid = vim.api.nvim_get_current_win()
  local height = vim.api.nvim_win_get_height(winid)
  local scroll_padding = 3

  -- setup the input popup options
  local popup_msg = "Search:"
  if search_as_you_type then
    popup_msg = "Filter:"
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
      if search_as_you_type and fuzzy_finder_mode then
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
      log.trace("Setting search in on_change to: " .. value)
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

  -- create mappings and autocmd
  input:map("i", "<C-w>", "<C-S-w>", { noremap = true })
  input:map("i", "<esc>", function(bufnr)
    vim.cmd("stopinsert")
    input:unmount()
    if fuzzy_finder_mode and utils.truthy(state.search_pattern) then
      reset_filter(state, true)
    end
    restore_height()
  end, { noremap = true })

  input:on({ event.BufLeave, event.BufDelete }, function()
    vim.cmd("stopinsert")
    input:unmount()
    -- If this was closed due to submit, that function will handle the reset_search
    vim.defer_fn(function()
      if fuzzy_finder_mode and utils.truthy(state.search_pattern) then
        reset_filter(state, true)
      end
    end, 100)
    restore_height()
  end, { once = true })

  if fuzzy_finder_mode then
    local config = require("neo-tree").config
    for lhs, cmd_name in pairs(config.filesystem.window.fuzzy_finder_mappings) do
      local cmd = cmds[cmd_name]
      if cmd then
        input:map("i", lhs, utils.wrap(cmd, state, scroll_padding), { noremap = true })
      else
        log.warn(string.format("Invalid command in fuzzy_finder_mappings: %s = %s", lhs, cmd_name))
      end
    end
  end
end

return M

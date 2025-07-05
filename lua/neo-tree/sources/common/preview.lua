local utils = require("neo-tree.utils")
local highlights = require("neo-tree.ui.highlights")
local events = require("neo-tree.events")
local manager = require("neo-tree.sources.manager")
local log = require("neo-tree.log")
local renderer = require("neo-tree.ui.renderer")
local NuiPopup = require("nui.popup")

---@class neotree.Preview.Config
---@field use_float boolean?
---@field use_image_nvim boolean?
---@field use_snacks_image boolean?

---@class neotree.Preview.Event
---@field source string?
---@field event neotree.event.Handler

---@class neotree.Preview
---@field config neotree.Preview.Config?
---@field active boolean Whether the preview is active.
---@field winid integer The id of the window being used to preview.
---@field is_neo_tree_window boolean Whether the preview window belongs to neo-tree.
---@field bufnr number The buffer that is currently in the preview window.
---@field start_pos integer[]? An array-like table specifying the (0-indexed) starting position of the previewed text.
---@field end_pos integer[]? An array-like table specifying the (0-indexed) ending position of the preview text.
---@field truth table A table containing information to be restored when the preview ends.
---@field events neotree.Preview.Event[] A list of events the preview is subscribed to.
local Preview = {}

---@type neotree.Preview?
local instance = nil

local neo_tree_preview_namespace = vim.api.nvim_create_namespace("neo_tree_preview")

---@param state neotree.State
local function create_floating_preview_window(state)
  local default_position = utils.resolve_config_option(state, "window.position", "left")
  state.current_position = state.current_position or default_position

  local title = state.config.title or "Neo-tree Preview"
  local winwidth = vim.api.nvim_win_get_width(state.winid)
  local winheight = vim.api.nvim_win_get_height(state.winid)
  local height = vim.o.lines - 4
  local width = 120
  local row, col = 0, 0

  if state.current_position == "left" then
    col = winwidth + 1
    width = math.min(vim.o.columns - col, 120)
  elseif state.current_position == "top" or state.current_position == "bottom" then
    height = height - winheight
    width = winwidth - 2
    if state.current_position == "top" then
      row = vim.api.nvim_win_get_height(state.winid) + 1
    end
  elseif state.current_position == "right" then
    width = math.min(vim.o.columns - winwidth - 4, 120)
    col = vim.o.columns - winwidth - width - 3
  elseif state.current_position == "float" then
    local pos = vim.api.nvim_win_get_position(state.winid)
    -- preview will be same height and top as tree
    row = pos[1]
    height = winheight

    -- tree and preview window will be side by side and centered in the editor
    width = math.min(vim.o.columns - winwidth - 4, 120)
    local total_width = winwidth + width + 4
    local margin = math.floor((vim.o.columns - total_width) / 2)
    col = margin + winwidth + 2

    -- move the tree window to make the combined layout centered
    local popup = renderer.get_nui_popup(state.winid)
    popup:update_layout({
      relative = "editor",
      position = {
        row = row,
        col = margin,
      },
    })
  else
    local cur_pos = state.current_position or "unknown"
    log.error('Preview cannot be used when position = "' .. cur_pos .. '"')
    return
  end

  if height < 5 or width < 5 then
    log.error(
      "Preview cannot be used without any space, please resize the neo-tree split to allow for at least 5 cells of free space."
    )
    return
  end
  local popups = require("neo-tree.ui.popups")
  local options = popups.popup_options(title, width, {
    ns_id = highlights.ns_id,
    size = { height = height, width = width },
    relative = "editor",
    position = {
      row = row,
      col = col,
    },
    win_options = {
      number = true,
      winhighlight = "Normal:"
        .. highlights.FLOAT_NORMAL
        .. ",FloatBorder:"
        .. highlights.FLOAT_BORDER,
    },
  })
  options.zindex = 40
  options.buf_options.filetype = "neo-tree-preview"

  local win = NuiPopup(options)
  win:mount()
  return win
end

---Creates a new preview.
---@param state neotree.State The state of the source.
---@return neotree.Preview preview A new preview. A preview is a table consisting of the following keys:
--These keys should not be altered directly. Note that the keys `start_pos`, `end_pos` and `truth`
--may be inaccurate if `active` is false.
function Preview:new(state)
  local preview = {}
  preview.active = false
  preview.config = vim.deepcopy(state.config)
  setmetatable(preview, { __index = self })
  preview:findWindow(state)
  return preview
end

---Preview a buffer in the preview window and optionally reveal and highlight the previewed text.
---@param bufnr integer? The number of the buffer to be previewed.
---@param start_pos integer[]? The (0-indexed) starting position of the previewed text. May be absent.
---@param end_pos integer[]? The (0-indexed) ending position of the previewed text. May be absent
function Preview:preview(bufnr, start_pos, end_pos)
  if self.is_neo_tree_window then
    log.warn("Could not find appropriate window for preview")
    return
  end

  bufnr = bufnr or self.bufnr
  if not self.active then
    self:activate()
  end

  if not self.active then
    return
  end

  self:setBuffer(bufnr)

  self.start_pos = start_pos
  self.end_pos = end_pos

  self:reveal()
  self:highlight_preview_range()
end

---Reverts the preview and inactivates it, restoring the preview window to its previous state.
function Preview:revert()
  self.active = false
  self:unsubscribe()

  if not renderer.is_window_valid(self.winid) then
    self.winid = nil
    return
  end

  if self.config.use_float then
    vim.api.nvim_win_close(self.winid, true)
    self.winid = nil
    return
  else
    local foldenable = utils.get_value(self.truth, "options.foldenable", nil, false)
    if foldenable ~= nil then
      vim.wo[self.winid].foldenable = self.truth.options.foldenable
    end
    vim.api.nvim_win_set_var(self.winid, "neo_tree_preview", 0)
  end

  local bufnr = self.truth.bufnr
  if type(bufnr) ~= "number" then
    return
  end
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  self:setBuffer(bufnr)
  if vim.api.nvim_win_is_valid(self.winid) then
    vim.api.nvim_win_call(self.winid, function()
      vim.fn.winrestview(self.truth.view)
    end)
  end
  vim.bo[self.bufnr].bufhidden = self.truth.options.bufhidden
end

---Subscribe to event and add it to the preview event list.
---@param source string? Name of the source to add the event to. Will use `events.subscribe` if nil.
---@param event neotree.event.Handler Event to subscribe to.
function Preview:subscribe(source, event)
  if source == nil then
    events.subscribe(event)
  else
    manager.subscribe(source, event)
  end
  self.events = self.events or {}
  table.insert(self.events, { source = source, event = event })
end

---Unsubscribe to all events in the preview event list.
function Preview:unsubscribe()
  if self.events == nil then
    return
  end
  for _, event in ipairs(self.events) do
    if event.source == nil then
      events.unsubscribe(event.event)
    else
      manager.unsubscribe(event.source, event.event)
    end
  end
  self.events = {}
end

---Finds the appropriate window and updates the preview accordingly.
---@param state neotree.State The state of the source.
function Preview:findWindow(state)
  local winid, is_neo_tree_window
  if self.config.use_float then
    if
      type(self.winid) == "number"
      and vim.api.nvim_win_is_valid(self.winid)
      and utils.is_floating(self.winid)
    then
      return
    end
    local win = create_floating_preview_window(state)
    if not win then
      self.active = false
      return
    end
    winid = win.winid
    is_neo_tree_window = false
  else
    winid, is_neo_tree_window = utils.get_appropriate_window(state)
    self.bufnr = vim.api.nvim_win_get_buf(winid)
  end

  if winid == self.winid then
    return
  end
  self.winid, self.is_neo_tree_window = winid, is_neo_tree_window

  if self.active then
    self:revert()
    self:preview()
  end
end

---Activates the preview, but does not populate the preview window,
function Preview:activate()
  if self.active then
    return
  end
  if not renderer.is_window_valid(self.winid) then
    return
  end
  if self.config.use_float then
    self.bufnr = vim.api.nvim_create_buf(false, true)
    self.truth = {}
  else
    self.truth = {
      bufnr = self.bufnr,
      view = vim.api.nvim_win_call(self.winid, vim.fn.winsaveview),
      options = {
        bufhidden = vim.bo[self.bufnr].bufhidden,
        foldenable = vim.wo[self.winid].foldenable,
      },
    }
    vim.bo[self.bufnr].bufhidden = "hide"
    vim.wo[self.winid].foldenable = false
  end
  self.active = true
  vim.api.nvim_win_set_var(self.winid, "neo_tree_preview", 1)
end

---@param winid number
---@param bufnr number
---@return boolean hijacked Whether the buffer was successfully hijacked.
local function try_load_image_nvim_buf(winid, bufnr)
  -- notify only image.nvim to let it try and hijack
  local image_augroup = vim.api.nvim_create_augroup("image.nvim", { clear = false })
  if #vim.api.nvim_get_autocmds({ group = image_augroup }) == 0 then
    local image_available, image = pcall(require, "image")
    if not image_available then
      local image_nvim_url = "https://github.com/3rd/image.nvim"
      log.debug(
        "use_image_nvim was set but image.nvim was not found. Install from: " .. image_nvim_url
      )
      return false
    end
    log.warn("image.nvim was not setup. Calling require('image').setup().")
    image.setup()
  end

  vim.opt.eventignore:remove("BufWinEnter")
  local ok = pcall(vim.api.nvim_win_call, winid, function()
    vim.api.nvim_exec_autocmds("BufWinEnter", { group = image_augroup, buffer = bufnr })
  end)
  vim.opt.eventignore:append("BufWinEnter")
  if not ok then
    log.debug("image.nvim doesn't have any file patterns to hijack.")
    return false
  end
  if vim.bo[bufnr].filetype ~= "image_nvim" then
    return false
  end
  return true
end

---@param bufnr number The buffer number of the buffer to set.
---@return number bytecount The number of bytes in the buffer
local get_bufsize = function(bufnr)
  return vim.api.nvim_buf_call(bufnr, function()
    return vim.fn.line2byte(vim.fn.line("$") + 1)
  end)
end

events.subscribe({
  event = events.NEO_TREE_PREVIEW_BEFORE_RENDER,
  ---@param args neotree.event.args.PREVIEW_BEFORE_RENDER
  handler = function(args)
    local preview = args.preview
    local bufnr = args.bufnr

    if not preview.config.use_snacks_image then
      return
    end
    -- check if snacks.image is available
    local snacks_image_ok, image = pcall(require, "snacks.image")
    if not snacks_image_ok then
      local snacks_nvim_url = "https://github.com/folke/snacks.nvim"
      log.debug(
        "use_snacks_image was set but snacks.nvim was not found. Install from: " .. snacks_nvim_url
      )
      return
    end
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    -- try attaching it
    if image.supports(bufname) then
      image.placement.new(preview.bufnr, bufname)
      vim.bo[preview.bufnr].modifiable = true
      return { handled = true } -- let snacks.image handle the rest
    end
  end,
})
events.subscribe({
  event = events.NEO_TREE_PREVIEW_BEFORE_RENDER,
  ---@param args neotree.event.args.PREVIEW_BEFORE_RENDER
  handler = function(args)
    local preview = args.preview
    local bufnr = args.bufnr

    if preview.config.use_image_nvim and try_load_image_nvim_buf(preview.winid, bufnr) then
      -- calling the try method twice should be okay here, image.nvim should cache the image and displaying the image takes
      -- really long anyways
      vim.api.nvim_win_set_buf(preview.winid, bufnr)
      return { handled = try_load_image_nvim_buf(preview.winid, bufnr) }
    end
  end,
})

---Set the buffer in the preview window without executing BufEnter or BufWinEnter autocommands.
---@param bufnr number The buffer number of the buffer to set.
function Preview:setBuffer(bufnr)
  self:clearHighlight()
  if bufnr == self.bufnr then
    return
  end
  local eventignore = vim.opt.eventignore
  vim.opt.eventignore:append("BufEnter,BufWinEnter")

  repeat
    ---@class neotree.event.args.PREVIEW_BEFORE_RENDER
    local args = {
      preview = self,
      bufnr = bufnr,
    }
    events.fire_event(events.NEO_TREE_PREVIEW_BEFORE_RENDER, args)

    if self.config.use_float then
      -- Workaround until https://github.com/neovim/neovim/issues/24973 is resolved or maybe 'previewpopup' comes in?
      vim.fn.bufload(bufnr)
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, lines)
      vim.api.nvim_win_set_buf(self.winid, self.bufnr)
      -- I'm not sure why float windows won't show numbers without this
      vim.wo[self.winid].number = true

      -- code below is from mini.pick
      -- only starts treesitter parser if the filetype is matching
      local ft = vim.bo[bufnr].filetype
      local bufsize = get_bufsize(bufnr)
      if bufsize > 1024 * 1024 or bufsize > 1000 * #lines then
        break -- goto end
      end
      local has_lang, lang = pcall(vim.treesitter.language.get_lang, ft)
      lang = has_lang and lang or ft
      local has_parser, parser =
        pcall(vim.treesitter.get_parser, self.bufnr, lang, { error = false })
      has_parser = has_parser and parser ~= nil
      if has_parser then
        has_parser = pcall(vim.treesitter.start, self.bufnr, lang)
      end
      if not has_parser then
        vim.bo[self.bufnr].syntax = ft
      end
    else
      vim.api.nvim_win_set_buf(self.winid, bufnr)
      self.bufnr = bufnr
    end

  until true
  vim.opt.eventignore = eventignore
end

---Move the cursor to the previewed position and center the screen.
function Preview:reveal()
  local pos = self.start_pos or self.end_pos
  if not self.active or not self.winid or not pos then
    return
  end
  vim.api.nvim_win_set_cursor(self.winid, { (pos[1] or 0) + 1, pos[2] or 0 })
  vim.api.nvim_win_call(self.winid, function()
    vim.cmd("normal! zz")
  end)
end

---Highlight the previewed range
function Preview:highlight_preview_range()
  if not self.active or not self.bufnr then
    return
  end
  local start_pos, end_pos = self.start_pos, self.end_pos
  if not start_pos and not end_pos then
    return
  end

  if not start_pos then
    ---@cast end_pos table
    start_pos = end_pos
  elseif not end_pos then
    ---@cast start_pos table
    end_pos = start_pos
  end

  local start_line, end_line = start_pos[1], end_pos[1]
  local start_col, end_col = start_pos[2], end_pos[2]
  vim.api.nvim_buf_set_extmark(self.bufnr, neo_tree_preview_namespace, start_line, start_col, {
    hl_group = highlights.PREVIEW,
    end_row = end_line,
    end_col = end_col,
    -- priority = priority,
    strict = false,
  })
end

---Clear the preview highlight in the buffer currently in the preview window.
function Preview:clearHighlight()
  if type(self.bufnr) == "number" and vim.api.nvim_buf_is_valid(self.bufnr) then
    vim.api.nvim_buf_clear_namespace(self.bufnr, neo_tree_preview_namespace, 0, -1)
  end
end

local toggle_state = false

Preview.hide = function()
  toggle_state = false
  if instance then
    instance:revert()
  end
  instance = nil
end

Preview.is_active = function()
  return instance and instance.active
end

---@param state neotree.State
Preview.show = function(state)
  local node = assert(state.tree:get_node())

  if instance then
    instance:findWindow(state)
  else
    instance = Preview:new(state)
  end

  local extra = node.extra or {}
  local position = extra.position
  local end_position = extra.end_position
  local path = node.path or node:get_id()
  local bufnr = extra.bufnr or vim.fn.bufadd(path)

  if bufnr and bufnr > 0 and instance then
    instance:preview(bufnr, position, end_position)
  end
end

---@param state neotree.State
Preview.toggle = function(state)
  if toggle_state then
    Preview.hide()
  else
    Preview.show(state)
    if instance and instance.active then
      toggle_state = true
    else
      Preview.hide()
      return
    end
    local winid = state.winid
    local source_name = state.name
    local preview_event = {
      event = events.VIM_CURSOR_MOVED,
      handler = function()
        local did_enter_preview = vim.api.nvim_get_current_win() == instance.winid
        if not toggle_state or (did_enter_preview and instance.config.use_float) then
          return
        end
        if vim.api.nvim_get_current_win() == winid then
          log.debug("Cursor moved in tree window, updating preview")
          Preview.show(state)
        else
          log.debug("Neo-tree window lost focus, disposing preview")
          Preview.hide()
        end
      end,
      id = "preview-event",
    }
    instance:subscribe(source_name, preview_event)
  end
end

Preview.focus = function()
  if Preview.is_active() then
    ---@cast instance table
    vim.fn.win_gotoid(instance.winid)
  end
end

local CTRL_E = utils.keycode("<c-e>")
local CTRL_Y = utils.keycode("<c-y>")
---@param state neotree.State
Preview.scroll = function(state)
  local direction = state.config.direction
  local input = direction < 0 and CTRL_E or CTRL_Y
  local count = math.abs(direction)

  if Preview:is_active() then
    ---@cast instance table
    vim.api.nvim_win_call(instance.winid, function()
      vim.cmd(("normal! %s%s"):format(count, input))
    end)
  else
    vim.api.nvim_win_call(state.winid, function()
      vim.api.nvim_feedkeys(state.fallback, "n", false)
    end)
  end
end

return Preview

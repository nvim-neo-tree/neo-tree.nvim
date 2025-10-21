---@class neotree.clipboard.Backend
local Backend = {}

---A backend saves and loads clipboards to and from states.
---Returns nil if the backend couldn't be created properly.
---@return neotree.clipboard.Backend?
function Backend:new()
  local backend = {}
  setmetatable(backend, self)
  self.__index = self
  -- if not do_setup() then
  --   return nil -- will default to no sync/backend
  -- end
  return backend
end

-- local function applicable(state)
--   return state.name ~= "document_symbols"
-- end

---Saves a state's clipboard to the backend.
---Automatically called whenever a user changes a state's clipboard.
---Returns nil when the save is not applicable.
---@param state neotree.State
---@return boolean? success_or_noop
function Backend:save(state)
  -- if not applicable(state) then
  --   return nil -- nothing happens
  -- end

  -- local saved, err = save_clipboard_to_somewhere(state)
  -- if not saved then
  --   return false, err -- will error
  -- end

  -- on true, neo-tree will try Backend:load with all other states
  -- return true
end

---Given a state, determines what clipboard (if any), should be loaded.
---Automatically called when other states' clipboards saved successfully.
---Returns nil if the clipboard should not be changed.
---@param state neotree.State
---@return neotree.clipboard.Contents? clipboard
---@return string? err
function Backend:load(state)
  -- if not applicable(state) then
  --   return nil -- nothing happens
  -- end

  -- local clipboard, err = load_clipboard_from_somewhere(state)
  -- if err then
  --   -- don't modify the clipboard and log an error
  --   return nil, err
  -- end

  -- change the clipboard to the saved clipboard
  -- return clipboard
end

return Backend

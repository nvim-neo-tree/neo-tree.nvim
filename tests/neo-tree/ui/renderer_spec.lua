pcall(require, "luacov")

local renderer = require("neo-tree.ui.renderer")
local events = require("neo-tree.events")

describe("renderer show_nodes", function()
  it("skips rendering when the state belongs to another tab", function()
    -- A second tab to serve as the state's owner.
    vim.cmd("tabnew")
    local other_tab = vim.api.nvim_get_current_tabpage()
    vim.cmd("tabprevious")

    -- Any field access beyond `tabid` means the guard failed and the renderer
    -- walked into a stale-tab render.
    local state = setmetatable({ tabid = other_tab }, {
      __index = function()
        error("show_nodes touched state fields for a stale tab")
      end,
    })

    -- The guard must return before the BEFORE_RENDER event fires.
    local fired = false
    local orig_fire = events.fire_event
    events.fire_event = function()
      fired = true
    end

    assert.has_no.errors(function()
      renderer.show_nodes({}, state)
    end)
    events.fire_event = orig_fire

    assert.is_false(fired)
  end)

  it("does not block rendering for the current tab", function()
    -- The guard must not trip for the current tab: the render proceeds at
    -- least as far as the BEFORE_RENDER event. The rest of the render chain
    -- needs full plugin state, so it may error here — that is expected and
    -- irrelevant to the guard.
    local fired = false
    local orig_fire = events.fire_event
    events.fire_event = function()
      fired = true
    end

    local current_tab = vim.api.nvim_get_current_tabpage()
    local state = setmetatable({ tabid = current_tab }, {
      __index = function()
        error("render proceeded past the tab guard")
      end,
    })

    pcall(renderer.show_nodes, {}, state)
    events.fire_event = orig_fire

    assert.is_true(fired)
  end)
end)

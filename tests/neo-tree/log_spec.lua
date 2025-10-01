local log = require("neo-tree.log")
local debug_locals = function(lvl)
  local i = 1
  local results = {}
  while true do
    local name, value = debug.getlocal(lvl, i)
    if not name then
      return results
    end
    results[#results + 1] = { name = name, value = value }
    i = i + 1
  end
end
describe("File logging", function()
  it("should get correct debug info", function()
    require("neo-tree").setup({
      log_to_file = true,
      log_level = {
        console = vim.log.levels.OFF,
        file = vim.log.levels.INFO,
      },
    })
    local expected = debug.getinfo(1, "Sln")
    local check_getinfo_at_format = false
    local debug_getinfo_hook = function(...)
      local running_func = debug.getinfo(2, "Sln")

      if running_func.name == "getinfo" then
        check_getinfo_at_format = true
      elseif check_getinfo_at_format and running_func.name == "format" then
        for _, localinfo in ipairs(debug_locals(4)) do
          local actual = localinfo.value
          if type(actual) == "table" then
            if actual.lastlinedefined then
              ---@cast actual debuginfo
              assert(
                actual.lastlinedefined == expected.lastlinedefined
                  and actual.source == expected.source
              )
            end
          end
        end
        debug.sethook()
      end
    end
    debug.sethook(debug_getinfo_hook, "cl")
    log.info("")
  end)
end)

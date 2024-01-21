pcall(require, "luacov")

local uv = vim.loop

---Return all sources inside "lua/neo-tree/sources"
---@return string[] # name of sources found
local function find_all_sources()
  local base_dir = "lua/neo-tree/sources"
  local result = {}
  local fd = uv.fs_scandir(base_dir)
  while fd do
    local name, typ = uv.fs_scandir_next(fd)
    if not name then
      break
    end
    if typ == "directory" then
      local ok, mod = pcall(require, "neo-tree.sources." .. name)
      if ok and mod.name then
        result[#result + 1] = name
      end
    end
  end
  return result
end

describe("sources.navigate(...: #<nparams>)", function()
  it("neo-tree.sources.filesystem.navigate exists", function()
    local ok, mod = pcall(require, "neo-tree.sources.filesystem")
    assert.is_true(ok)
    assert.is_not_nil(mod.navigate)
  end)
  local filesystem_navigate_nparams =
    debug.getinfo(require("neo-tree.sources.filesystem").navigate).nparams
  it("neo-tree.sources.filesystem.navigate is a func and has args", function()
    assert.is_not_nil(filesystem_navigate_nparams)
    assert.is_true(filesystem_navigate_nparams > 0)
  end)
  for _, source in ipairs(find_all_sources()) do
    describe(string.format("Test: %s.navigate", source), function()
      it(source .. ".navigate is able to require and exists", function()
        local ok, mod = pcall(require, "neo-tree.sources." .. source)
        assert.is_true(ok)
        assert.is_not_nil(mod.navigate)
      end)
      it(source .. ".navigate has same num of args as filesystem", function()
        local nparams = debug.getinfo(require("neo-tree.sources." .. source).navigate).nparams
        assert.are.equal(filesystem_navigate_nparams, nparams)
      end)
    end)
  end
end)

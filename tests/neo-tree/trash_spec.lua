local u = require("tests.utils")
describe("config.trash.command", function()
  after_each(function()
    u.clear_environment()
  end)

  it("works with functions that return functions", function()
    local paths_from_command
    require("neo-tree").setup({
      trash = {
        command = function(paths)
          return function()
            paths_from_command = paths
            return true
          end
        end,
      },
    })

    local paths = { "/example" }
    require("neo-tree.trash").trash(paths)
    assert.are.equal(paths, paths_from_command, "Internal function should have received paths")
  end)

  it("Should error if no paths are passed in", function()
    local ok = pcall(require("neo-tree.trash").trash, {})
    assert.are.equal(ok, false, "Expected trash to error")
  end)
end)

pcall(require, "luacov")
local utils = require("neo-tree.utils")

describe("is_subpath", function()
  local common_tests = function()
    -- Relative paths
    assert.are.same(true, utils.is_subpath("a", "a/subpath"))
    assert.are.same(false, utils.is_subpath("a", "b/c"))
    assert.are.same(false, utils.is_subpath("a", "b"))
  end
  it("should work with unix paths", function()
    local old = utils.is_windows
    utils.is_windows = false
    common_tests()
    assert.are.same(true, utils.is_subpath("/a", "/a/subpath"))
    assert.are.same(false, utils.is_subpath("/a", "/b/c"))

    -- Edge cases
    assert.are.same(false, utils.is_subpath("", ""))
    assert.are.same(true, utils.is_subpath("/", "/"))

    -- Paths with trailing slashes
    assert.are.same(true, utils.is_subpath("/a/", "/a/subpath"))
    assert.are.same(true, utils.is_subpath("/a/", "/a/subpath/"))
    assert.are.same(true, utils.is_subpath("/a", "/a/subpath"))
    assert.are.same(true, utils.is_subpath("/a", "/a/subpath/"))

    -- Paths with different casing
    assert.are.same(true, utils.is_subpath("/TeSt", "/TeSt/subpath"))
    assert.are.same(false, utils.is_subpath("/A", "/a/subpath"))
    assert.are.same(false, utils.is_subpath("/A", "/a/subpath"))
    utils.is_windows = old
  end)
  it("should work on windows paths", function()
    local old = utils.is_windows
    utils.is_windows = true
    common_tests()
    assert.are.same(true, utils.is_subpath("C:", "C:"))
    assert.are.same(false, utils.is_subpath("C:", "D:"))
    assert.are.same(true, utils.is_subpath("C:/A", [[C:\A]]))

    -- Test Windows paths with backslashes
    assert.are.same(true, utils.is_subpath([[C:\Users\user]], [[C:\Users\user\Documents]]))
    assert.are.same(false, utils.is_subpath([[C:\Users\user]], [[D:\Users\user]]))
    assert.are.same(false, utils.is_subpath([[C:\Users\user]], [[C:\Users\usera]]))

    -- Test Windows paths with forward slashes
    assert.are.same(true, utils.is_subpath("C:/Users/user", "C:/Users/user/Documents"))
    assert.are.same(false, utils.is_subpath("C:/Users/user", "D:/Users/user"))
    assert.are.same(false, utils.is_subpath("C:/Users/user", "C:/Users/usera"))

    -- Test Windows paths with drive letters
    assert.are.same(true, utils.is_subpath("C:", "C:/Users/user"))
    assert.are.same(false, utils.is_subpath("C:", "D:/Users/user"))

    -- Test Windows paths with UNC paths
    assert.are.same(true, utils.is_subpath([[\\server\share]], [[\\server\share\folder]]))
    assert.are.same(false, utils.is_subpath([[\\server\share]], [[\\server2\share]]))

    -- Test Windows paths with trailing backslashes
    assert.are.same(true, utils.is_subpath([[C:\Users\user\]], [[C:\Users\user\Documents]]))
    assert.are.same(true, utils.is_subpath("C:/Users/user/", "C:/Users/user/Documents"))

    utils.is_windows = old
  end)
end)

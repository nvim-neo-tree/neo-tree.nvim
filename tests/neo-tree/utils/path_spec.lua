pcall(require, "luacov")
local utils = require("neo-tree.utils")

describe("utils path functions", function()
  describe("is_subpath", function()
    local common_tests = function()
      -- Relative paths
      assert.are.same(true, utils.is_subpath("a", "a/subpath"))
      assert.are.same(false, utils.is_subpath("a", "b/c"))
      assert.are.same(false, utils.is_subpath("a", "b"))
    end
    it("should work with unix paths", function()
      local old = {
        is_windows = utils.is_windows,
        path_separator = utils.path_separator,
      }
      utils.is_windows = false
      utils.path_separator = "/"
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
      utils.is_windows = old.is_windows
      utils.path_separator = old.path_separator
    end)
    it("should work on windows paths", function()
      local old = {
        is_windows = utils.is_windows,
        path_separator = utils.path_separator,
      }
      utils.is_windows = true
      utils.path_separator = "\\"
      common_tests()
      assert.are.same(true, utils.is_subpath("C:", "C:"))
      assert.are.same(false, utils.is_subpath("C:", "D:"))
      assert.are.same(true, utils.is_subpath("C:/A", [[c:\A]]))

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

      utils.is_windows = old.is_windows
      utils.path_separator = old.path_separator
    end)
  end)

  describe("split_path", function()
    local common_tests = function(sep)
      -- Relative paths
      assert.are.same({ "a", "b" }, { utils.split_path("a" .. sep .. "b") })
      assert.are.same({ "a", "b" }, { utils.split_path("a" .. sep .. "b" .. sep) })

      -- Single component path
      assert.are.same({ nil, "a" }, { utils.split_path("a") })

      -- Empty path
      assert.are.same({ nil, "" }, { utils.split_path("") })

      -- Paths with dots
      assert.are.same({ ".a", ".b" }, { utils.split_path(".a" .. sep .. ".b") })
      assert.are.same({ "a", ".b" }, { utils.split_path("a" .. sep .. ".b") })
    end

    it("should work with unix paths", function()
      local old = {
        is_windows = utils.is_windows,
        path_separator = utils.path_separator,
      }
      utils.is_windows = false
      utils.path_separator = "/"
      common_tests("/")

      -- Absolute paths
      assert.are.same({ "/a", "b" }, { utils.split_path("/a/b") })
      assert.are.same({ "/a/b/c/d", "e" }, { utils.split_path("/a/b/c/d/e") })
      assert.are.same({ "/", "a" }, { utils.split_path("/a") })

      -- Edge cases
      assert.are.same({ nil, "/" }, { utils.split_path("/") })
      assert.are.same({ "/a", "b" }, { utils.split_path("/a/b/") })
      assert.are.same({ "a", "b" }, { utils.split_path("a/b/") })
      assert.are.same({ "//a", "b" }, { utils.split_path("//a/b") })

      utils.is_windows = old.is_windows
      utils.path_separator = old.path_separator
    end)

    it("should work on windows paths", function()
      local old = {
        is_windows = utils.is_windows,
        path_separator = utils.path_separator,
      }
      utils.is_windows = true
      utils.path_separator = "\\"
      common_tests("\\")

      -- Paths with drive letters
      assert.are.same({ [[C:\Users]], "user" }, { utils.split_path([[C:\Users\user]]) })
      assert.are.same({ [[C:\Users]], "user" }, { utils.split_path([[C:\Users\user\]]) })
      assert.are.same({ nil, "C:" }, { utils.split_path([[C:]]) })
      assert.are.same({ nil, "C:\\" }, { utils.split_path([[C:\]]) })
      assert.are.same({ [[C:\]], "_" }, { utils.split_path([[C:\_]]) })

      -- UNC paths
      assert.are.same(
        { [[\\server\share]], "folder" },
        { utils.split_path([[\\server\share\folder]]) }
      )
      assert.are.same({ [[\\server]], "share" }, { utils.split_path([[\\server\share]]) })
      assert.are.same(
        { [[\\server\share\folder]], "file" },
        { utils.split_path([[\\server\share\folder\file]]) }
      )

      utils.is_windows = old.is_windows
      utils.path_separator = old.path_separator
    end)
  end)
end)

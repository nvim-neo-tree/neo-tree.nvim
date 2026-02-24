pcall(require, "luacov")
local utils = require("neo-tree.utils")
local test_utils = require("tests.utils")
local uv = vim.uv or vim.loop

describe("utils path functions", function()
  describe("is_subpath", function()
    local common_tests = function()
      -- Relative paths
      assert.are.same(true, utils.is_subpath("a", "a/subpath"))
      assert.are.same(false, utils.is_subpath("a", "b/c"))
      assert.are.same(false, utils.is_subpath("a", "b"))
    end
    it("should work with unix paths", function()
      local restore = test_utils.os_to_windows(false)
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

      -- Root path edge case
      assert.are.same(true, utils.is_subpath("/", "/b/c"))
      assert.are.same(true, utils.is_subpath("/", "/b"))
      restore()
    end)
    it("should work on windows paths", function()
      local restore = test_utils.os_to_windows(true)
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
      assert.are.same(true, utils.is_subpath("C:\\", [[c:\A]]))
      assert.are.same(false, utils.is_subpath("C:", "D:/Users/user"))

      -- Test Windows paths with UNC paths
      assert.are.same(true, utils.is_subpath([[\\server\share]], [[\\server\share\folder]]))
      assert.are.same(false, utils.is_subpath([[\\server\share]], [[\\server2\share]]))

      -- Test Windows paths with trailing backslashes
      assert.are.same(true, utils.is_subpath([[C:\Users\user\]], [[C:\Users\user\Documents]]))
      assert.are.same(true, utils.is_subpath("C:/Users/user/", "C:/Users/user/Documents"))

      -- Test root paths
      assert.are.same(false, utils.is_subpath([[\]], [[\\]]))

      restore()
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
      local restore = test_utils.os_to_windows(false)
      common_tests(utils.path_separator)

      -- Absolute paths
      assert.are.same({ "/a", "b" }, { utils.split_path("/a/b") })
      assert.are.same({ "/a/b/c/d", "e" }, { utils.split_path("/a/b/c/d/e") })
      assert.are.same({ "/", "a" }, { utils.split_path("/a") })

      -- Edge cases
      assert.are.same({ nil, "/" }, { utils.split_path("/") })
      assert.are.same({ "/a", "b" }, { utils.split_path("/a/b/") })
      assert.are.same({ "a", "b" }, { utils.split_path("a/b/") })
      assert.are.same({ "//a", "b" }, { utils.split_path("//a/b") })
      restore()
    end)

    it("should work on windows paths", function()
      local restore = test_utils.os_to_windows(true)
      common_tests(utils.path_separator)

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

      restore()
    end)
  end)

  -- Helper function to collect iterator results into a table
  local function collect_parents(path)
    local parents = {}
    for parent in utils.path_parents(path) do
      parents[#parents + 1] = parent
    end
    return parents
  end

  describe("utils.path_parents", function()
    -- Test Case 1: Standard Unix path (from example)
    describe("on Unix-like paths ('/')", function()
      -- Temporarily set OS path behavior to Unix/non-Windows
      local restore = test_utils.os_to_windows(false)

      it(
        "should return the correct parents for a deep path (longest-to-shortest, including root)",
        function()
          local path = "/some/path/here/file.txt"
          -- Expected: /some/path/here, /some/path, /some, /
          local expected_parents = { "/some/path/here", "/some/path", "/some", "/" }
          assert.are.same(expected_parents, collect_parents(path))
        end
      )

      it(
        "should return correct parents for a relative path (longest-to-shortest, no root)",
        function()
          local path = "a/b/c/d.lua"
          -- Expected: a/b/c, a/b, a
          local expected_parents = { "a/b/c", "a/b", "a" }
          assert.are.same(expected_parents, collect_parents(path))
        end
      )

      it("should handle a path that is only one level deep (excluding root)", function()
        local path = "/file.txt"
        -- Expected: /
        local expected_parents = { "/" }
        assert.are.same(expected_parents, collect_parents(path))
      end)

      it("should return an empty list for the root path", function()
        local path = "/"
        local expected_parents = {}
        assert.are.same(expected_parents, collect_parents(path))
      end)

      restore()
    end)
    describe("on Windows-like paths ('\\')", function()
      -- Temporarily set OS path behavior to Windows
      local restore = test_utils.os_to_windows(true)

      it(
        "should return the correct parents for a drive-rooted path (longest-to-shortest, including root)",
        function()
          local path = "C:\\projects\\app\\src\\main.lua"
          -- Expected: C:\projects\app\src, C:\projects\app, C:\projects, C:\
          local expected_parents =
            { "C:\\projects\\app\\src", "C:\\projects\\app", "C:\\projects", "C:\\" }
          assert.are.same(expected_parents, collect_parents(path))
        end
      )

      it("should return an empty list for a drive root", function()
        local path = "E:\\"
        local expected_parents = {}
        assert.are.same(expected_parents, collect_parents(path))
      end)

      restore()
    end)
  end)
  describe("utils.path_splitroot", function()
    it("handles POSIX absolute and relative paths", function()
      local restore = test_utils.os_to_windows(false)
      assert.are.same({ "", "/", "etc/hosts" }, { utils.path_splitroot("/etc/hosts") })
      assert.are.same({ "", "", "src/main.lua" }, { utils.path_splitroot("src/main.lua") })
      assert.are.same({ "", "/", "" }, { utils.path_splitroot("/") })
      restore()
    end)

    it("handles Windows paths", function()
      local restore = test_utils.os_to_windows(true)
      assert.are.same(
        { "C:", "\\", "Windows\\System" },
        { utils.path_splitroot("C:\\Windows\\System") }
      )
      assert.are.same({ "D:", "", "docs/notes.txt" }, { utils.path_splitroot("D:docs/notes.txt") })
      assert.are.same({ "Z:", "", "" }, { utils.path_splitroot("Z:") })
      assert.are.same(
        { "\\\\server\\share", "\\", "folder\\file" },
        { utils.path_splitroot("\\\\server\\share\\folder\\file") }
      )
      restore()
    end)

    it("handles empty or edge case inputs", function()
      assert.are.same({ "", "", "" }, { utils.path_splitroot("") })
      assert.are.same({ "", "", "." }, { utils.path_splitroot(".") })
    end)
  end)
end)

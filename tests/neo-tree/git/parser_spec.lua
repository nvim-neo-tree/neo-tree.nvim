local git_parser = require("neo-tree.git.parser")
local utils = require("neo-tree.utils")
local test_utils = require("tests.utils")
describe("git parser", function()
  describe("parses v2 output", function()
    local porcelain_v2_status = {
      "1 MM N... 100644 100644 100644 109d711d57a4f9683fde9128389928002162a490 42c6fcc404e517043706028825185095d0c47421 dir1/dir2/dir3/mixed_modify.txt",
      "1 D. N... 100644 000000 000000 37ce9c00e8b504beab1de2eafc826384fc370d56 0000000000000000000000000000000000000000 dir1/dir2/staged_delete.txt",
      "1 .T N... 100644 100644 120000 0325a864d684a90d6c2ae8ea87cc03f018453413 0325a864d684a90d6c2ae8ea87cc03f018453413 dir1/dir2/type_change.txt",
      "1 .M N... 100644 100644 100644 01a6f1c971e9294a240b3115bac66cbfce11f7d8 01a6f1c971e9294a240b3115bac66cbfce11f7d8 dir1/dir2/unstaged_modify.txt",
      "2 R. N... 100644 100644 100644 2448337202c660fbfa4656098d0f26e57c28d796 2448337202c660fbfa4656098d0f26e57c28d796 R100 dir1/rename_new.txt",
      "dir1/rename_old.txt",
      "1 A. N... 000000 100644 100644 0000000000000000000000000000000000000000 7500412f150f61942cf346e35ce17ffa88d07cf3 dir1/staged_add.txt",
      "1 M. N... 100644 100644 100644 846c1fabd482d05b6e1039e970bcb6b73d640dc2 0058a29e63ae9dbfc1d3c64a20c56282c2219b33 dir1/staged_modify.txt",
      "1 .D N... 100644 100644 000000 3d86a78393c13896aaa5e167a6175042d9bf4dd2 3d86a78393c13896aaa5e167a6175042d9bf4dd2 dir1/unstaged_delete.txt",
      "? .gitignore",
      "? dir1/dir2/dir3/untracked.txt",
    }

    local test = function()
      local iter = coroutine.wrap(function()
        for i, s in ipairs(porcelain_v2_status) do
          coroutine.yield(s)
        end
      end)
      local worktree_root = utils.is_windows and "C:\\" or "/asdf"
      local status = git_parser.parse_status_porcelain(2, worktree_root, iter)
      ---@param path string
      local from_git_root = function(path)
        return utils.path_join(worktree_root, path)
      end
      assert.are.same({
        [from_git_root(".gitignore")] = "?",
        [from_git_root("dir1/unstaged_delete.txt")] = ".D",
        [from_git_root("dir1/rename_new.txt")] = "R.",
        [from_git_root("dir1/staged_add.txt")] = "A.",
        [from_git_root("dir1/staged_modify.txt")] = "M.",
        [from_git_root("dir1/dir2/staged_delete.txt")] = "D.",
        [from_git_root("dir1/dir2/unstaged_modify.txt")] = ".M",
        [from_git_root("dir1/dir2/type_change.txt")] = ".T",
        [from_git_root("dir1/dir2/dir3/mixed_modify.txt")] = "MM",
        [from_git_root("dir1/dir2/dir3/untracked.txt")] = "?",

        ---parent bubbling
        [from_git_root("dir1")] = { "?" },
        [from_git_root("dir1/dir2")] = { "?" },
        [from_git_root("dir1/dir2/dir3")] = { "?" },
      }, status)
    end

    local restore = test_utils.os_to_windows(false)
    it("on unix", test)
    test_utils.os_to_windows(true)
    it("on windows", test)
    restore()
  end)

  describe("parses v1 output", function()
    local porcelain_v1_status = {
      "MM dir1/dir2/dir3/mixed_modify.txt",
      "D  dir1/dir2/staged_delete.txt",
      " T dir1/dir2/type_change.txt",
      " M dir1/dir2/unstaged_modify.txt",
      "R  dir1/rename_new.txt",
      "dir1/rename_old.txt",
      "A  dir1/staged_add.txt",
      "M  dir1/staged_modify.txt",
      " D dir1/unstaged_delete.txt",
      "?? .gitignore",
      "?? dir1/dir2/dir3/untracked.txt",
    }
    local test = function()
      local iter = coroutine.wrap(function()
        for i, s in ipairs(porcelain_v1_status) do
          coroutine.yield(s)
        end
      end)
      local git_root = utils.is_windows and "C:\\" or "/asdf"
      local status = git_parser.parse_status_porcelain(1, git_root, iter)
      local from_git_root = function(path)
        return utils.path_join(git_root, path)
      end
      assert.are.same({
        [from_git_root(".gitignore")] = "?",
        [from_git_root("dir1/unstaged_delete.txt")] = ".D",
        [from_git_root("dir1/rename_new.txt")] = "R.",
        [from_git_root("dir1/staged_add.txt")] = "A.",
        [from_git_root("dir1/staged_modify.txt")] = "M.",
        [from_git_root("dir1/dir2/staged_delete.txt")] = "D.",
        [from_git_root("dir1/dir2/unstaged_modify.txt")] = ".M",
        [from_git_root("dir1/dir2/type_change.txt")] = ".T",
        [from_git_root("dir1/dir2/dir3/mixed_modify.txt")] = "MM",
        [from_git_root("dir1/dir2/dir3/untracked.txt")] = "?",

        ---parent bubbling
        [from_git_root("dir1")] = { "?" },
        [from_git_root("dir1/dir2")] = { "?" },
        [from_git_root("dir1/dir2/dir3")] = { "?" },
      }, status)
    end
    local restore = test_utils.os_to_windows(false)
    it("on unix", test)
    test_utils.os_to_windows(true)
    it("on windows", test)
    restore()
  end)

  describe("parses git diff --name-status", function()
    local diff_name_status_output = {
      "M",
      "lua/neo-tree/git/init.lua",
      "M",
      "lua/neo-tree/git/ls-files.lua",
      "M",
      "lua/neo-tree/git/parser.lua",
      "M",
      "lua/neo-tree/git/utils.lua",
      "M",
      "tests/neo-tree/git/parser_spec.lua",
    }
    local test = function()
      local iter = coroutine.wrap(function()
        for i, s in ipairs(diff_name_status_output) do
          coroutine.yield(s)
        end
      end)
      local worktree_root = utils.is_windows and "C:\\" or "/asdf"
      local status = git_parser.parse_diff_name_status_output(worktree_root, false, iter)
      local from_git_root = function(path)
        return utils.path_join(worktree_root, path)
      end
      assert.are.same({
        [from_git_root("lua/neo-tree/git/init.lua")] = "M.",
        [from_git_root("lua/neo-tree/git/ls-files.lua")] = "M.",
        [from_git_root("lua/neo-tree/git/parser.lua")] = "M.",
        [from_git_root("lua/neo-tree/git/utils.lua")] = "M.",
        [from_git_root("tests/neo-tree/git/parser_spec.lua")] = "M.",

        --parent bubbling
        [from_git_root("lua/neo-tree/git")] = { "M" },
        [from_git_root("lua/neo-tree")] = { "M" },
        [from_git_root("lua")] = { "M" },

        [from_git_root("tests/neo-tree/git")] = { "M" },
        [from_git_root("tests/neo-tree")] = { "M" },
        [from_git_root("tests")] = { "M" },
      }, status)
    end
    local restore = test_utils.os_to_windows(false)
    it("on unix", test)
    test_utils.os_to_windows(true)
    it("on windows", test)
    restore()
  end)
end)

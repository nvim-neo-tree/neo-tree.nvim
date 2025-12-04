local git = require("neo-tree.git")
local utils = require("neo-tree.utils")
local test_utils = require("tests.utils")
local gsplit_plain = vim.fn.has("nvim-0.9") == 1 and { plain = true } or true
local uv = vim.uv or vim.loop
describe("git parser", function()
  describe("parses v2 output", function()
    local porcelain_v2_status = {
      "1 D. N... 100644 000000 000000 ade2881afa1dcb156a3aa576024aa0fecf789191 0000000000000000000000000000000000000000 deleted_staged.txt",
      "1 .D N... 100644 100644 000000 9c13483e67ceff219800303ec7af39c4f0301a5b 9c13483e67ceff219800303ec7af39c4f0301a5b deleted_unstaged.txt",
      "1 MM N... 100644 100644 100644 4417f3aca512ffdf247662e2c611ee03ff9255cc 29c0e9846cd6410a44c4ca3fdaf5623818bd2838 modified_mixed.txt",
      "1 M. N... 100644 100644 100644 f784736eecdd43cd8eb665615163cfc6506fca5f 8d6fad5bd11ac45c7c9e62d4db1c427889ed515b modified_staged.txt",
      "1 .M N... 100644 100644 100644 c9e1e027aa9430cb4ffccccf45844286d10285c1 c9e1e027aa9430cb4ffccccf45844286d10285c1 modified_unstaged.txt",
      "1 A. N... 000000 100644 100644 0000000000000000000000000000000000000000 89cae60d74c222609086441e29985f959b6ec546 new_staged_file.txt",
      "2 R. N... 100644 100644 100644 3454a7dc6b93d1098e3c3f3ec369589412abdf99 3454a7dc6b93d1098e3c3f3ec369589412abdf99 R100 renamed_staged_new.txt",
      "renamed_staged_old.txt",
      "1 .T N... 100644 100644 120000 192f10ed8c11efb70155e8eb4cae6ec677347623 192f10ed8c11efb70155e8eb4cae6ec677347623 type_change.txt",
      "? .gitignore",
      "? untracked.txt",
    }

    local test = function()
      local old = utils.is_windows
      local iter = coroutine.wrap(function()
        for i, s in ipairs(porcelain_v2_status) do
          coroutine.yield(s)
        end
      end)
      local git_root = utils.is_windows and "C:\\" or "/asdf"
      local status = git._parse_porcelain(2, git_root, iter, {})
      assert.are.same({
        [utils.path_join(git_root, ".gitignore")] = "?",
        [utils.path_join(git_root, "deleted_staged.txt")] = "D.",
        [utils.path_join(git_root, "deleted_unstaged.txt")] = ".D",
        [utils.path_join(git_root, "modified_mixed.txt")] = "MM",
        [utils.path_join(git_root, "modified_staged.txt")] = "M.",
        [utils.path_join(git_root, "modified_unstaged.txt")] = ".M",
        [utils.path_join(git_root, "new_staged_file.txt")] = "A.",
        [utils.path_join(git_root, "renamed_staged_new.txt")] = "R.",
        [utils.path_join(git_root, "type_change.txt")] = ".T",
        [utils.path_join(git_root, "untracked.txt")] = "?",
      }, status)
    end

    local old = utils.on_windows
    utils.on_windows = false
    it("on unix", test)
    utils.on_windows = true
    it("on windows", test)
    utils.on_windows = old
  end)

  describe("parses v1 output", function()
    local porcelain_v1_status = {
      "1 D. N... 100644 000000 000000 ade2881afa1dcb156a3aa576024aa0fecf789191 0000000000000000000000000000000000000000 deleted_staged.txt",
      "1 .D N... 100644 100644 000000 9c13483e67ceff219800303ec7af39c4f0301a5b 9c13483e67ceff219800303ec7af39c4f0301a5b deleted_unstaged.txt",
      "1 MM N... 100644 100644 100644 4417f3aca512ffdf247662e2c611ee03ff9255cc 29c0e9846cd6410a44c4ca3fdaf5623818bd2838 modified_mixed.txt",
      "1 M. N... 100644 100644 100644 f784736eecdd43cd8eb665615163cfc6506fca5f 8d6fad5bd11ac45c7c9e62d4db1c427889ed515b modified_staged.txt",
      "1 .M N... 100644 100644 100644 c9e1e027aa9430cb4ffccccf45844286d10285c1 c9e1e027aa9430cb4ffccccf45844286d10285c1 modified_unstaged.txt",
      "1 A. N... 000000 100644 100644 0000000000000000000000000000000000000000 89cae60d74c222609086441e29985f959b6ec546 new_staged_file.txt",
      "2 R. N... 100644 100644 100644 3454a7dc6b93d1098e3c3f3ec369589412abdf99 3454a7dc6b93d1098e3c3f3ec369589412abdf99 R100 renamed_staged_new.txt",
      "renamed_staged_old.txt",
      "1 .T N... 100644 100644 120000 192f10ed8c11efb70155e8eb4cae6ec677347623 192f10ed8c11efb70155e8eb4cae6ec677347623 type_change.txt",
      "? .gitignore",
      "? untracked.txt",
    }
    local test = function()
      local iter = coroutine.wrap(function()
        for i, s in ipairs(porcelain_v1_status) do
          coroutine.yield(s)
        end
      end)
      local git_root = utils.is_windows and "C:\\" or "/asdf"
      local status = git._parse_porcelain(2, git_root, iter, {})
      assert.are.same({
        [utils.path_join(git_root, ".gitignore")] = "?",
        [utils.path_join(git_root, "deleted_staged.txt")] = "D.",
        [utils.path_join(git_root, "deleted_unstaged.txt")] = ".D",
        [utils.path_join(git_root, "modified_mixed.txt")] = "MM",
        [utils.path_join(git_root, "modified_staged.txt")] = "M.",
        [utils.path_join(git_root, "modified_unstaged.txt")] = ".M",
        [utils.path_join(git_root, "new_staged_file.txt")] = "A.",
        [utils.path_join(git_root, "renamed_staged_new.txt")] = "R.",
        [utils.path_join(git_root, "type_change.txt")] = ".T",
        [utils.path_join(git_root, "untracked.txt")] = "?",
      }, status)
    end
    local restore = test_utils.os_to_windows(false)
    it("on unix", test)
    test_utils.os_to_windows(true)
    it("on windows", test)
    restore()
  end)
end)

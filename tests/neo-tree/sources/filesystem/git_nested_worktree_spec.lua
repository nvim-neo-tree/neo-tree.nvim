pcall(require, "luacov")

local u = require("tests.utils")
local verify = require("tests.utils.verify")
local git = require("neo-tree.git")
local utils = require("neo-tree.utils")

-- Registration spawns `git rev-parse` and `git status`, which is slow on CI runners.
local TIMEOUT = 5000

---@param cwd string
---@param ... string
local function git_cmd(cwd, ...)
  vim.fn.system(vim.list_extend({ "git", "-C", cwd }, { ... }))
  assert(vim.v.shell_error == 0, "git " .. table.concat({ ... }, " ") .. " failed in " .. cwd)
end

---An outer repository with an independent repository checked out inside of it, which
---the outer .gitignore excludes. Nothing is committed on purpose: staging is enough
---for `git status` to report the file, and it keeps the setup free of the user's
---global commit hooks and signing config.
---@return string outer, string inner, string inner_file
local function create_nested_repos()
  local outer = u.fs.create_temp_dir()
  git_cmd(outer, "init", "--quiet")
  u.fs.write_file(utils.path_join(outer, ".gitignore"), { "/inner/" })
  git_cmd(outer, "add", ".gitignore")

  local inner = utils.path_join(outer, "inner")
  u.fs.create_dir(inner)
  git_cmd(inner, "init", "--quiet")
  local inner_file = utils.path_join(inner, "tracked.txt")
  u.fs.write_file(inner_file, { "hello" })
  git_cmd(inner, "add", "tracked.txt")

  return outer, inner, utils.normalize_path(inner_file)
end

describe("Filesystem git status for nested repositories", function()
  -- The temporary repositories are deliberately left on disk. Removing them while an
  -- async `git status` is still in flight makes it fail against a missing directory,
  -- and Neovim drops its own temp directory on exit anyway.
  after_each(function()
    u.clear_environment()
  end)

  for _, use_libuv_file_watcher in ipairs({ false, true }) do
    local suffix = " (use_libuv_file_watcher=" .. tostring(use_libuv_file_watcher) .. ")"

    ---@return string inner, string inner_file
    local function open_tree_revealing_the_nested_repo()
      local outer, inner, inner_file = create_nested_repos()
      require("neo-tree").setup({
        enable_git_status = true,
        filesystem = {
          use_libuv_file_watcher = use_libuv_file_watcher,
          filtered_items = { hide_gitignored = false },
        },
      })
      require("neo-tree.command").execute({
        action = "show",
        source = "filesystem",
        dir = outer,
        reveal_file = inner_file,
      })
      return inner, inner_file
    end

    it("resolves the nested repository to its own worktree" .. suffix, function()
      local inner, inner_file = open_tree_revealing_the_nested_repo()
      local inner_root = git.find_worktree_info(inner)

      verify.eventually(function()
        return git.find_existing_worktree(inner_file) == inner_root
      end, "the nested file should resolve to the nested worktree, not the outer one", TIMEOUT)
    end)

    it("does not report files of the nested repository as ignored" .. suffix, function()
      local _, inner_file = open_tree_revealing_the_nested_repo()

      -- Waiting for a status code that is neither missing nor "!" covers both halves:
      -- the outer .gitignore marks the nested file as ignored until the nested
      -- repository is registered, and the nested repository reports it as staged.
      verify.eventually(function()
        local status = git.find_existing_status_code(inner_file, {})
        return status ~= nil and status ~= "!"
      end, "the nested file kept the outer repository's ignored status", TIMEOUT)
    end)
  end
end)

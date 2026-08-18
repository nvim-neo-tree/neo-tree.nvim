pcall(require, "luacov")

local u = require("tests.utils")
local uv = vim.uv or vim.loop
local verify = require("tests.utils.verify")
local git = require("neo-tree.git")
local utils = require("neo-tree.utils")

-- Registration spawns `git rev-parse` and `git status`, which is slow on CI runners.
-- Timeout determined by seeing how long successful runs take (usually 20 seconds or less)
local TIMEOUT = 30 * 1000

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

  -- we must resolve all of these paths to realpaths because: (gemini-generated output below)
  -- On Windows hosted virtual machines in GitHub Actions, "RUNNER~1" is the 8.3 short-form MS-DOS path representation
  -- for the user profile directory C:\Users\RUNNER 1 (often belonging to the default user runneradmin). This path
  -- frequently appears in environment variables, temporary folders, or test assertions on GitHub-hosted Windows
  -- runners.  Node.js methods like os.tmpdir() can intermittently return either the short-form (RUNNER~1) or long-form
  -- path, which sometimes breaks path-matching unit tests in CI pipelines.
  local outputs = { outer, inner, inner_file }
  for i, path in ipairs(outputs) do
    outputs[i] = utils.normalize_path(assert(uv.fs_realpath(path)))
  end

  outer, inner, inner_file = unpack(outputs)
  return outer, inner, inner_file
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
      verify.filesystem_tree_node_is(inner_file)
      return inner, inner_file
    end

    it("resolves the nested repository to its own worktree" .. suffix, function()
      local inner, inner_file = open_tree_revealing_the_nested_repo()

      verify.eventually(function()
        local actual_worktree_root = git.find_existing_worktree(inner_file)
        return actual_worktree_root and actual_worktree_root == inner
      end, "worktree root never resolved to " .. inner, TIMEOUT)
    end)

    it("does not report files of the nested repository as ignored" .. suffix, function()
      local _, inner_file = open_tree_revealing_the_nested_repo()

      -- Waiting for a status code that is neither missing nor "!" covers both halves:
      -- the outer .gitignore marks the nested file as ignored until the nested
      -- repository is registered, and the nested repository reports it as staged.
      verify.eventually(function()
        local status = git.find_existing_status_code(inner_file, {})
        return status ~= nil and status ~= "!"
      end, "status code did not resolve properly for " .. inner_file, TIMEOUT)
    end)
  end
end)

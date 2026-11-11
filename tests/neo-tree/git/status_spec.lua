local git = require("neo-tree.git")
local utils = require("neo-tree.utils")
local u = require("tests.utils")
local uv = vim.uv or vim.loop

local function git_cmd(repo, ...)
  local output = vim.fn.system(vim.list_extend({ "git", "-C", repo }, { ... }))
  assert(vim.v.shell_error == 0, output)
  return vim.trim(output)
end

local function commit(repo)
  git_cmd(repo, "add", "--all")
  -- Keep the fixture independent of the user's identity, signing and commit hooks.
  git_cmd(
    repo,
    "-c",
    "user.name=Neo-tree tests",
    "-c",
    "user.email=neo-tree@example.com",
    "-c",
    "commit.gpgsign=false",
    "-c",
    "core.hooksPath=" .. utils.path_join(repo, ".git", "disabled-hooks"),
    "commit",
    "--quiet",
    "-m",
    "test commit"
  )
end

describe("git status with a baseline", function()
  local repo, tracked_file, base

  before_each(function()
    require("neo-tree").setup({ filesystem = { use_libuv_file_watcher = false } })
    require("neo-tree").ensure_config()

    repo = utils.normalize_path(assert(uv.fs_realpath(u.fs.create_temp_dir())))
    git_cmd(repo, "init", "--quiet")
    tracked_file = utils.path_join(repo, "tracked.txt")
    u.fs.write_file(tracked_file, { "before" })
    commit(repo)
    base = git_cmd(repo, "rev-parse", "HEAD")
    u.fs.write_file(tracked_file, { "after" })
    commit(repo)
  end)

  after_each(function()
    u.clear_environment()
  end)

  it("returns committed changes on repeated requests with unchanged git status", function()
    local bases = { [repo] = base }
    local expected_diff = { [tracked_file] = "M." }
    local status, _, diff = git.status(repo, bases)
    assert.are.same({}, status)
    assert.are.same(expected_diff, diff)

    status, _, diff = git.status(repo, bases)
    assert.are.same({}, status)
    assert.are.same(expected_diff, diff)
    assert.are.equal("M.", git.find_existing_status_code(tracked_file, bases))
  end)

  it("compares against a new baseline even when git status is unchanged", function()
    git.status(repo, { [repo] = base })

    local bases = { [repo] = "HEAD" }
    local status, _, diff = git.status(repo, bases)
    assert.are.same({}, status)
    assert.are.same({}, diff)
    assert.is_nil(git.find_existing_status_code(tracked_file, bases))
  end)

  it("updates the diff after a commit leaves the working tree clean", function()
    local bases = { [repo] = base }
    git.status(repo, bases)

    local added_file = utils.path_join(repo, "added.txt")
    u.fs.write_file(added_file, { "new file" })
    commit(repo)

    local status, _, diff = git.status(repo, bases)
    assert.are.same({}, status)
    assert.are.same({ [tracked_file] = "M.", [added_file] = "A." }, diff)
    assert.are.equal("A.", git.find_existing_status_code(added_file, bases))
  end)
end)

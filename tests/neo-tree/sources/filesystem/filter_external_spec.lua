local u = require("tests.utils")
local utils = require("neo-tree.utils")
local filter = require("neo-tree.sources.filesystem.lib.filter_external")

describe("Filesystem search", function()
  local root
  local fd = vim.fn.executable("fd") == 1 and "fd" or vim.fn.executable("fdfind") == 1 and "fdfind"

  before_each(function()
    assert(fd, "fd or fdfind is required; run mise bootstrap")
    root = u.fs.create_temp_dir()
  end)

  after_each(function()
    filter.cancel()
    u.fs.remove_dir(root, true)
  end)

  local function search(term, names, find_args, full_path_words)
    for _, name in ipairs(names) do
      u.fs.write_file(utils.path_join(root, name))
    end
    local results, errors = {}, {}
    local completed, exit_code = false, nil
    filter.find_files({
      path = root,
      term = term,
      find_command = fd,
      find_args = find_args,
      find_by_full_path_words = full_path_words,
      fuzzy_finder_mode = true,
      filtered_items = { visible = true },
      on_insert = function(err, path)
        if err then
          errors[#errors + 1] = err
        elseif path then
          results[#results + 1] = vim.fn.fnamemodify(path, ":t")
        end
      end,
      on_exit = function(code)
        exit_code = code
        completed = true
      end,
    })
    assert.is_true(vim.wait(5000, function()
      return completed
    end))
    assert.are.equal(0, exit_code)
    assert.are.same({}, errors)
    table.sort(results)
    return results
  end

  it("matches Cyrillic case variants with a lowercase search", function()
    local names = { "1_тест.txt", "2_Тест.txt", "3_ТЕСТ.txt", "4_ТеСт.txt" }
    assert.are.same(names, search("тест", names))
  end)

  it("keeps ASCII substring matching case insensitive", function()
    local names = { "1_test.txt", "2_Test.txt", "3_TEST.txt", "4_TeSt.txt" }
    assert.are.same(names, search("test", names))
  end)

  it("treats regular expression characters as literal filename text", function()
    local name = "1_тест.(a+b)^$.txt"
    assert.are.same({ name }, search("тест.(a+b)^$", { name, "2_тестXaaab.txt" }))
  end)

  it("preserves explicit glob queries", function()
    local names = { "1_test.lua", "2_test.txt", "3_test.md" }
    assert.are.same({ names[1], names[2] }, search("test.{lua,txt}", names))
    assert.are.same({ names[1], names[2] }, search("test.[lt]??", names))
    assert.are.same(names, search("test.*", names))
  end)

  it("preserves full-path word searches", function()
    assert.are.same({ "file.lua" }, search("folder file", { "folder/file.lua" }, nil, true))
  end)

  it("preserves fd smart case for uppercase queries", function()
    local names = { "1_тест.txt", "2_Тест.txt", "3_ТЕСТ.txt" }
    assert.are.same({ names[2] }, search("Тест", names))
  end)

  it("honors an explicit ignore-case option", function()
    local names = { "1_тест.txt", "2_Тест.txt", "3_ТЕСТ.txt" }
    assert.are.same(names, search("Тест", names, { "--ignore-case" }))
  end)

  it("honors an explicit case-sensitive option", function()
    local names = { "1_тест.txt", "2_Тест.txt", "3_ТЕСТ.txt" }
    assert.are.same({ names[1] }, search("тест", names, { "--case-sensitive" }))
  end)
end)

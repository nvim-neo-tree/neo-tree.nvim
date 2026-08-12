--- generated largely by gemini 3.6 flash
local utils = require("neo-tree.utils")
local chunk_to_lines = utils._testing.chunk_to_lines

describe("chunk handling (for utils.job)", function()
  local function push_chunks(co, chunks, final_err)
    for _, chunk in ipairs(chunks) do
      coroutine.resume(co, nil, chunk)
    end
    -- Send final non-string or error signal to complete stream
    coroutine.resume(co, final_err, nil)
  end

  -- Test 1: Simple single chunk with newline separators
  it("works with a simple chunk", function()
    local lines = {}
    local on_line = function(err, line)
      table.insert(lines, line)
    end

    local co = chunk_to_lines(on_line, "\n")
    push_chunks(co, { "hello\nworld\nfoo" })

    assert.are.same({ "hello", "world", "foo" }, lines)
  end)

  -- Test 2: Chunk split across boundaries (incomplete line completed in next chunk)

  it("works with lines split across chunks", function()
    local lines = {}
    local on_line = function(_, line)
      table.insert(lines, line)
    end

    local co = chunk_to_lines(on_line, "\n")
    push_chunks(co, { "hel", "lo\nwor", "ld" })

    assert.are.same({ "hello", "world" }, lines)
  end)

  -- Test 3: Custom separator (e.g. comma)
  it("works with custom separators", function()
    local lines = {}
    local on_line = function(_, line)
      table.insert(lines, line)
    end

    local co = chunk_to_lines(on_line, ",")
    push_chunks(co, { "apple,banana,", "cherry" })

    assert.are.same({ "apple", "banana", "cherry" }, lines)
  end)

  -- Test 4: Error propagation and termination
  it("works with errors", function()
    local lines = {}
    local errs = {}
    local i = 1
    local on_line = function(err, line)
      lines[i] = line
      errs[i] = err
      i = i + 1
    end

    local co = chunk_to_lines(on_line, "\n")
    coroutine.resume(co, nil, "some data\nmore data")
    coroutine.resume(co, "IO_ERROR", nil)

    assert.are.same({ "some data", "more data" }, lines)
    assert.are.same({ nil, "IO_ERROR" }, errs)
  end)

  -- Test 5: Empty chunks and empty string input
  it("works with empty input", function()
    local lines = {}
    local on_line = function(err, line)
      table.insert(lines, line)
    end

    local co = chunk_to_lines(on_line, "\n")
    push_chunks(co, { "" })

    assert.are.same({ "" }, lines)
  end)
end)

pcall(require, "luacov")

local symbols = require("neo-tree.sources.document_symbols.lib.symbols_utils")

local function make_sym(name, kind_name, children)
  children = children or {}
  return {
    id = name,
    name = name,
    type = "symbol",
    path = "/test.lua",
    children = children,
    extra = {
      kind = { name = kind_name, icon = "?", hl = "" },
    },
  }
end

describe("filter_symbols", function()
  it("returns nil when ignore is nil", function()
    local syms = { make_sym("foo", "Function") }
    local got = symbols._filter_symbols(syms, nil)
    assert.are.same(1, #got)
  end)

  it("returns all when ignore is empty", function()
    local syms = { make_sym("foo", "Function") }
    local got = symbols._filter_symbols(syms, {})
    assert.are.same(1, #got)
  end)

  it("removes ignored kinds", function()
    local syms = {
      make_sym("foo", "Function"),
      make_sym("bar", "Variable"),
      make_sym("baz", "Function"),
    }
    local got = symbols._filter_symbols(syms, { variable = true })
    assert.are.same(2, #got)
    assert.are.same("foo", got[1].name)
    assert.are.same("baz", got[2].name)
  end)

  it("removes multiple ignored kinds", function()
    local syms = {
      make_sym("f", "Function"),
      make_sym("v", "Variable"),
      make_sym("c", "Constant"),
      make_sym("k", "Field"),
    }
    local got = symbols._filter_symbols(syms, { variable = true, field = true })
    assert.are.same(2, #got)
    assert.are.same("f", got[1].name)
    assert.are.same("c", got[2].name)
  end)

  it("filters children recursively", function()
    local syms = {
      make_sym("top", "Function", {
        make_sym("inner_var", "Variable"),
        make_sym("inner_func", "Function", {
          make_sym("deep_var", "Variable"),
        }),
      }),
    }
    local got = symbols._filter_symbols(syms, { variable = true })
    assert.are.same(1, #got)
    assert.are.same("top", got[1].name)
    local children = got[1].children
    assert.are.same(1, #children)
    assert.are.same("inner_func", children[1].name)
    local grandchildren = children[1].children
    assert.are.same(0, #grandchildren)
  end)

  it("removes root symbol if its kind matches", function()
    local syms = {
      make_sym("only_var", "Variable"),
    }
    local got = symbols._filter_symbols(syms, { variable = true })
    assert.are.same(0, #got)
  end)

  it("passes through symbols without kind info", function()
    local syms = {
      make_sym("f", "Function"),
      { id = "unknown", name = "unknown", type = "symbol", path = "/test.lua", children = {}, extra = {} },
    }
    local got = symbols._filter_symbols(syms, { variable = true })
    assert.are.same(2, #got)
  end)
end)

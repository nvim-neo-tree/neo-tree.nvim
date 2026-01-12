local proxy = require("neo-tree.utils.proxy")

describe("proxy module", function()
  local root

  before_each(function()
    root = {
      existing = {
        value = 10,
        list = { "a", "b" },
      },
      primitive = 5,
    }
  end)

  describe("new() and basic indexing", function()
    it("should allow deep indexing into non-existent keys without erroring", function()
      local p = proxy.new(root)
      local deep = p.this.doesnt.exist
      assert.is_table(deep)
      assert.is_nil(proxy.get(deep))
    end)

    it("should return the correct string representation of a key path", function()
      local p = proxy.new(root)
      local path = p.users[1].settings.theme
      assert.equal("users.[1].settings.theme", tostring(path))
    end)
  end)

  describe("tracking and primitives", function()
    it("should track accesses and assignments when enabled", function()
      local p, metadata = proxy.new(root, true)
      assert(metadata)

      -- Access
      local _ = p.a.b.c
      -- Assignment
      p.x.y = 20

      --- p.a, p.a.b, p.a.b.c, p.x
      assert.equal(4, #metadata.accesses)
      assert.equal("a.b.c", tostring(metadata.accesses[3]))
      assert.equal(1, #metadata.assignments)
      assert.equal("x.y", tostring(metadata.assignments[1]))
    end)

    it("should return raw primitives if return_primitives is true", function()
      local p = proxy.new(root, false, true)
      -- 'primitive' key is 5 (not a table)
      assert.equal(5, p.primitive)
    end)
  end)

  describe("proxy.set() and proxy.get()", function()
    it("should retrieve the actual value from the root table using get()", function()
      local p = proxy.new(root)
      local val, _, _ = proxy.get(p.existing.value)
      assert.equal(10, val)
    end)

    it("should NOT overwrite existing primitives during assignment by default", function()
      local p = proxy.new(root)
      -- root.existing.value is 10. p.existing.value.sub is a path through a primitive.
      proxy.set(p.existing.value.sub, "broken")
      assert.equal(10, root.existing.value)
    end)

    it("should create new nested tables if they don't exist in root", function()
      local p = proxy.new(root)
      proxy.set(p.new_node.sub_node, "hello")
      assert.equal("hello", root.new_node.sub_node)
    end)

    it("should overwrite primitives if force is true", function()
      local p = proxy.new(root)
      proxy.set(p.primitive.new_key, "forced", true)
      assert.is_table(root.primitive)
      assert.equal("forced", root.primitive.new_key)
    end)
  end)

  describe("Edge cases", function()
    it("should handle numeric indices in paths correctly", function()
      local p = proxy.new(root)
      proxy.set(p.existing.list[3], "c")
      assert.equal("c", root.existing.list[3])
    end)

    it("should provide the metatable and root in the get() callback", function()
      local p = proxy.new(root)
      local captured_root
      proxy.get(p.existing, function(val, _, mt)
        captured_root = mt.root
      end)
      assert.equal(root, captured_root)
    end)
  end)
end)

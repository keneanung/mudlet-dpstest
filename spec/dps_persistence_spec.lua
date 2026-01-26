require("spec/spec_helper")

describe("DPS persistence", function()
  before_each(function()
    set_time(0)
  end)

  it("saves strategies and label to file", function()
    -- Capture writes
    local writes = {}
    local real_io_open = io.open
    io.open = function(path, mode)
      assert.is_truthy(path:match("dps_data%.json$"))
      if mode == "w" then
        local buf = ""
        return {
          write = function(_, s) buf = buf .. tostring(s) end,
          close = function()
            table.insert(writes, buf)
          end,
        }
      else
        return real_io_open(path, mode)
      end
    end

    -- Make yajl produce some string so save writes something
    local old_to_string = yajl.to_string
    yajl.to_string = function(tbl)
      assert.is_truthy(tbl.strategies)
      assert.is_truthy(tbl.strategyLabel)
      return "{mock-json}"
    end

    -- Load module with real save allowed
    reload_dps({ noSaveStub = true })
    DPS.start("S1")
    DPS.addDamage(100)
    advance_time(5)
    DPS.stop()
    DPS.setLabel("LabelA")

    -- Restore stubs
    io.open = real_io_open
    yajl.to_string = old_to_string

    assert.is_true(#writes >= 1)
    assert.is_truthy(writes[#writes]:match("{mock%-json}"))
  end)

  it("loads strategies and label from file", function()
    -- Prepare a fake file read with canned content
    local real_io_open = io.open
    io.open = function(path, mode)
      assert.is_truthy(path:match("dps_data%.json$"))
      if mode == "r" then
        return {
          read = function(_, _)
            return "{mock-json-read}"
          end,
          close = function() end,
        }
      end
      return real_io_open(path, mode)
    end

    -- Make yajl decode return a specific table regardless of input
    local old_to_value = yajl.to_value
    yajl.to_value = function(_)
      return {
        strategies = { S2 = { totalDamage = 300, totalRawDamage = 300, totalTime = 10, sessions = {}, critHits = 0, critTypes = {} } },
        strategyLabel = "Restored",
      }
    end

    -- Reload module (init() calls load())
    reload_dps({ noSaveStub = true })

    -- Restore stubs
    io.open = real_io_open
    yajl.to_value = old_to_value

    assert.is_truthy(DPS.strategies.S2)
    assert.are.equal(300, DPS.strategies.S2.totalDamage)
    assert.are.equal("Restored", DPS.strategyLabel)
  end)
end)

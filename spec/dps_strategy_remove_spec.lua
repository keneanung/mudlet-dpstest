require("spec/spec_helper")

describe("DPS remove strategy", function()
  before_each(function()
    set_time(0)
    reload_dps()
  end)

  it("deletes a strategy and persists state", function()
    DPS.start("ToDelete")
    DPS.addDamage(10)
    DPS.stop()
    assert.is_truthy(DPS.strategies["ToDelete"]) -- sanity
    DPS.removeStrategy("ToDelete")
    assert.is_nil(DPS.strategies["ToDelete"]) -- removed
  end)

  it("refuses to delete the active strategy", function()
    DPS.start("Active")
    DPS.removeStrategy("Active")
    -- still active and still present
    assert.is_truthy(DPS.current)
    -- strategy table entry is only created on stop, so remains nil here
    assert.is_nil(DPS.strategies["Active"]) 
  end)
end)

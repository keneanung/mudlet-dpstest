require("spec/spec_helper")

describe("DPS basic flow", function()
  before_each(function()
    set_time(0)
    reload_dps()
  end)

  it("aggregates damage and raw damage with crits", function()
    DPS.start("StrategyA")
    -- first non-crit hit: 100
    DPS.addDamage(100)
    -- flag a CRITICAL (2x) and hit for 100 (raw should add 50)
    DPS.flagCrit("CRITICAL")
    DPS.addDamage(100)
    -- advance 10 seconds and stop
    advance_time(10)
    DPS.stop()

    local s = DPS.strategies["StrategyA"]
    assert.is_truthy(s)
    assert.are.equal(200, s.totalDamage)
    assert.are.equal(150, s.totalRawDamage)
    assert.are.equal(10, s.totalTime)
    assert.are.equal(1, s.critHits)
    assert.is_truthy(s.critTypes["CRITICAL"]) -- counted once
  end)
end)

require("spec/spec_helper")

describe("DPS crit multipliers", function()
  before_each(function()
    set_time(0)
    reload_dps()
  end)

  it("backs out raw damage correctly for all tiers", function()
    DPS.start("Crits")
    for crit, mult in pairs(DPS.critMultipliers) do
      DPS.flagCrit(crit)
      DPS.addDamage(100 * mult)
    end
    advance_time(1)
    DPS.stop()

    local s = DPS.strategies["Crits"]
    assert.is_truthy(s)
    -- Each tier contributes raw 100
    local tiers = 0
    for _ in pairs(DPS.critMultipliers) do tiers = tiers + 1 end
    assert.are.equal(100 * tiers, s.totalRawDamage)
  end)
end)

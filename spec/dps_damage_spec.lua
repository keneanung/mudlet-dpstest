require("spec/spec_helper")

describe("Damage accounting and pauses", function()
  before_each(function()
    set_time(0)
    reload_dps({ noSaveStub = true })
  end)

  it("accounts rawDamage for crits via multiplier", function()
    DPS.start("StratCrit")
    DPS.current.enemyName = "Dummy"
    DPS.flagCrit("CRITICAL")
    advance_time(1)
    DPS.addDamage(200)
    advance_time(1)
    DPS.stop()
    local e = DPS.enemies["Dummy"].strategies["StratCrit"].recent[1]
    -- CRITICAL multiplier is 2, so rawDamage should be 100
    assert.are.equal(100, e.rawDamage)
  end)

  it("pauses active time on regain when not attacking", function()
    keneanung = { bashing = { attacking = 0 } }
    DPS.start("StratPause")
    advance_time(5)
    DPS.onRegain("balance")
    assert.is_nil(DPS.current.activeStart)
    assert.are.equal(5, DPS.current.activeTime)
  end)
end)

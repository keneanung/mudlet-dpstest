require("spec/spec_helper")

describe("Per-enemy local controls", function()
  before_each(function()
    set_time(0)
    reload_dps({ noSaveStub = true })
  end)

  it("resets local data for an enemy and strategy", function()
    DPS.start("StratA")
    DPS.current.enemyName = "Orc"
    advance_time(5)
    DPS.addDamage(100)
    DPS.stop()

    -- ensure data exists
    assert.is_truthy(DPS.enemies["Orc"]) 
    assert.is_truthy(DPS.enemies["Orc"].strategies["StratA"]) 

    -- reset for enemy+strategy
    DPS.resetLocal("Orc", "StratA")
    assert.is_falsy(DPS.enemies["Orc"].strategies["StratA"]) 

    -- add again and reset whole enemy
    DPS.start("StratA")
    DPS.current.enemyName = "Orc"
    advance_time(2)
    DPS.addDamage(50)
    DPS.stop()
    DPS.resetLocal("Orc")
    assert.is_falsy(DPS.enemies["Orc"]) 
  end)

  it("updates last-N buffer size via setLastN", function()
    assert.are.equal(10, DPS.lastNSessions)
    DPS.setLastN(3)
    assert.are.equal(3, DPS.lastNSessions)
  end)
end)

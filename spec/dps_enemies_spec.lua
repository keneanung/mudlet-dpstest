require("spec/spec_helper")

describe("Listing recorded enemies", function()
  before_each(function()
    set_time(0)
    reload_dps({ noSaveStub = true })
  end)

  it("returns a sorted list of enemy names with strategy counts", function()
    -- seed encounters for two enemies
    DPS.start("StratA")
    DPS.current.enemyName = "Goblin"
    advance_time(1)
    DPS.addDamage(10)
    DPS.stop()

    DPS.start("StratB")
    DPS.current.enemyName = "Orc"
    advance_time(1)
    DPS.addDamage(10)
    DPS.stop()

    DPS.start("StratA")
    DPS.current.enemyName = "Orc"
    advance_time(1)
    DPS.addDamage(10)
    DPS.stop()

    local list = DPS.listEnemies()
    assert.are.equal(2, #list)
    assert.are.equal("Goblin", list[1].name)
    assert.are.equal("Orc", list[2].name)
    assert.are.equal(1, list[1].strategies)
    assert.are.equal(2, list[2].strategies)
  end)
end)

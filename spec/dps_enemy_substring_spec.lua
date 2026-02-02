require("spec/spec_helper")

describe("Enemy substring resolution", function()
  before_each(function()
    set_time(0)
    reload_dps({ noSaveStub = true })
  end)

  it("resolves a unique case-insensitive substring to the enemy", function()
    -- seed encounters
    DPS.start("StratA")
    DPS.current.enemyName = "Orc"
    advance_time(5)
    DPS.addDamage(50)
    DPS.stop()

    DPS.start("StratB")
    DPS.current.enemyName = "Goblin"
    advance_time(3)
    DPS.addDamage(30)
    DPS.stop()

    local list = DPS.localReport("or") -- substring should match 'Orc' uniquely
    assert.is_truthy(list)
    assert.is_true(#list >= 1)
  end)

  it("returns empty report when substring is ambiguous", function()
    -- seed two enemies that both match 'gob'
    DPS.start("StratA")
    DPS.current.enemyName = "Goblin"
    advance_time(2)
    DPS.addDamage(20)
    DPS.stop()

    DPS.start("StratA")
    DPS.current.enemyName = "Goblin King"
    advance_time(2)
    DPS.addDamage(20)
    DPS.stop()

    local list = DPS.localReport("gob")
    assert.is_truthy(list)
    assert.are.equal(0, #list)
  end)

  it("returns empty report when substring has no matches", function()
    -- no enemies seeded
    local list = DPS.localReport("Drake")
    assert.is_truthy(list)
    assert.are.equal(0, #list)
  end)
end)

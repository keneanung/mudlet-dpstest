require("spec/spec_helper")

describe("Renaming and merging enemies", function()
  before_each(function()
    set_time(0)
    reload_dps({ noSaveStub = true })
    DPS.lastNSessions = 2
  end)

  it("renames an enemy to a new name", function()
    DPS.start("StratA"); DPS.current.enemyName = "Goblin"; advance_time(5); DPS.addDamage(50); DPS.stop()

    assert.is_truthy(DPS.enemies["Goblin"]) -- precondition
    assert.is_falsy(DPS.enemies["Gob"])     -- precondition

    local ok = DPS.renameEnemy("Goblin", "Gob")
    assert.is_true(ok)
    assert.is_falsy(DPS.enemies["Goblin"]) -- old removed
    assert.is_truthy(DPS.enemies["Gob"])   -- new present

    local st = DPS._enemyStrategyStats("Gob", "StratA")
    assert.are.equal(1, st.recentCount)
    assert.are.equal(50, st.recentDamage)
    assert.are.equal(5, st.recentTime)
  end)

  it("merges source into existing target and removes source", function()
    -- seed source "corpse of Orc" and target "Orc" under same strategy
    DPS.start("StratA"); DPS.current.enemyName = "corpse of Orc"; advance_time(10); DPS.addDamage(100); DPS.stop()
    DPS.start("StratA"); DPS.current.enemyName = "Orc";           advance_time(5);  DPS.addDamage(50);  DPS.stop()

    local ok = DPS.renameEnemy("corpse of Orc", "Orc") -- should merge
    assert.is_true(ok)
    assert.is_falsy(DPS.enemies["corpse of Orc"]) -- removed
    assert.is_truthy(DPS.enemies["Orc"])          -- kept

    local st = DPS._enemyStrategyStats("Orc", "StratA")
    assert.are.equal(2, st.recentCount)
    assert.are.equal(150, st.recentDamage)
    assert.are.equal(15, st.recentTime)
    assert.are.equal(0, st.totalsDamage) -- no rolling needed with N=2
  end)

  it("merges strategies correctly when both enemies have different strategies", function()
    DPS.start("StratA"); DPS.current.enemyName = "Troll"; advance_time(4); DPS.addDamage(40); DPS.stop()
    DPS.start("StratB"); DPS.current.enemyName = "Orc";   advance_time(6); DPS.addDamage(60); DPS.stop()

    local ok = DPS.mergeEnemies("Troll", "Orc")
    assert.is_true(ok)

    -- StratA now exists on Orc from Troll
    local sa = DPS._enemyStrategyStats("Orc", "StratA")
    assert.are.equal(1, sa.recentCount)
    assert.are.equal(40, sa.recentDamage)
    assert.are.equal(4, sa.recentTime)

    -- StratB remains as-is
    local sb = DPS._enemyStrategyStats("Orc", "StratB")
    assert.are.equal(1, sb.recentCount)
    assert.are.equal(60, sb.recentDamage)
    assert.are.equal(6, sb.recentTime)
  end)

  it("does not proceed on ambiguous source name", function()
    -- create two that match 'gob'
    DPS.start("StratA"); DPS.current.enemyName = "Goblin";      advance_time(1); DPS.addDamage(10); DPS.stop()
    DPS.start("StratA"); DPS.current.enemyName = "Goblin King"; advance_time(1); DPS.addDamage(10); DPS.stop()

    local before = DPS.listEnemies()
    local ok = DPS.renameEnemy("gob", "Whatever")
    assert.is_false(ok)
    local after = DPS.listEnemies()
    assert.are.equal(#before, #after)
  end)
end)

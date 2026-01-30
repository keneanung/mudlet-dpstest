require("spec/spec_helper")

describe("Local per-enemy encounter recording", function()
  before_each(function()
    set_time(0)
    reload_dps({ noSaveStub = true })
  end)

  it("records encounters into recent buffer and rolls into totals beyond N", function()
    DPS.lastNSessions = 2
    DPS.start("StratA")
    -- set enemy snapshot manually
    DPS.current.enemyName = "Goblin"
    advance_time(5)
    DPS.addDamage(100)
    advance_time(5)
    DPS.stop()

    DPS.start("StratA")
    DPS.current.enemyName = "Goblin"
    advance_time(10)
    DPS.addDamage(200)
    DPS.stop()

    DPS.start("StratA")
    DPS.current.enemyName = "Goblin"
    advance_time(10)
    DPS.addDamage(300)
    DPS.stop()

    local stats = DPS._enemyStrategyStats("Goblin", "StratA")
    -- last 2 sessions: (200/10)=20 dps and (300/10)=30 dps -> mean 25 dps
    assert.are.equal(2, stats.recentCount)
    assert.are.equal(25, stats.recentDps)
    -- totals should have first session folded: 100 dmg over 10s -> 10 dps
    assert.are.equal(10, stats.totalsDps)
  end)

  it("resolves target name via recent cleared buffer", function()
    -- simulate recent-cleared target snapshot before the killing hit
    DPS.recentClearedTarget = { id = "42", name = "Elf", expires = getEpoch() + 2 }
    DPS.start("StratB")
    DPS.addDamage(50)
    DPS.stop()
    local e = DPS.enemies["Elf"]
    assert.is_truthy(e)
  end)
end)

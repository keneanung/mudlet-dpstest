require("spec/spec_helper")

describe("Cross-enemy comparison overview", function()
  before_each(function()
    set_time(0)
    reload_dps({ noSaveStub = true })
  end)

  it("returns enemies sorted ascending by recent DPS for a strategy", function()
    -- Seed multiple enemies under same strategy
    local function run(enemy, dmg, dur)
      DPS.start("StratX")
      DPS.current.enemyName = enemy
      advance_time(dur)
      DPS.addDamage(dmg)
      DPS.stop()
    end
    run("Goblin", 100, 10) -- 10 dps
    run("Orc", 150, 10)    -- 15 dps
    run("Troll", 50, 10)   -- 5 dps

    local list = DPS.overview("StratX")
    assert.are.equal(3, #list)
    assert.are.equal("Troll", list[1].enemy)
    assert.are.equal("Goblin", list[2].enemy)
    assert.are.equal("Orc", list[3].enemy)
    -- recentDps now reflects raw dps
    assert.are.equal(5, list[1].recentDps)
    assert.are.equal(10, list[2].recentDps)
    assert.are.equal(15, list[3].recentDps)
  end)

  it("uses current strategy label when none provided", function()
    DPS.strategyLabel = "AutoY"
    DPS.start("AutoY")
    DPS.current.enemyName = "Elf"
    advance_time(10)
    DPS.addDamage(100)
    DPS.stop()
    local list = DPS.overview()
    assert.are.equal(1, #list)
    assert.are.equal("Elf", list[1].enemy)
  end)

  it("uses raw dps values when crit multiplier applies", function()
    local function runCrit(enemy, dmg, dur)
      DPS.start("StratR")
      DPS.current.enemyName = enemy
      DPS.flagCrit("CRITICAL") -- multiplier 2
      advance_time(dur)
      DPS.addDamage(dmg)
      DPS.stop()
    end
    runCrit("Ghoul", 200, 10) -- rawDamage should be 100 -> 10 raw dps
    local list = DPS.overview("StratR")
    assert.are.equal(1, #list)
    assert.are.equal("Ghoul", list[1].enemy)
    assert.are.equal(10, list[1].recentDps)
  end)
end)

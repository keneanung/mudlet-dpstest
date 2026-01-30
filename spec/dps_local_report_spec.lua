require("spec/spec_helper")

describe("Local report with type breakdowns", function()
  before_each(function()
    set_time(0)
    reload_dps({ noSaveStub = true })
  end)

  it("returns detailed per-strategy report including recent and totals typeDamage", function()
    DPS.lastNSessions = 1 -- roll older sessions into totals

    -- First session: goes into totals after second session
    DPS.start("StratA")
    DPS.current.enemyName = "Orc"
    advance_time(5)
    DPS.addDamage(60, "fire")  -- 60 fire over 5s
    DPS.addDamage(40, "cold")  -- 100 total
    DPS.stop()

    -- Second session: stays in recent
    DPS.start("StratA")
    DPS.current.enemyName = "Orc"
    advance_time(10)
    DPS.addDamage(30, "fire")  -- 30 fire
    DPS.addDamage(70, "acid")  -- 100 total
    DPS.stop()

    local list = DPS.localReport("Orc")
    assert.is_truthy(list)
    assert.is_true(#list >= 1)
    local strat
    for _, it in ipairs(list) do if it.name == "StratA" then strat = it break end end
    assert.is_truthy(strat)

    -- recent reflects second session only
    assert.are.equal(10, strat.recentTime)
    assert.are.equal(100, strat.recentDamage)
    assert.are.equal(100/10, strat.recentDps)
    -- per-type raw dps
    assert.are.equal(3, strat.recentTypeRawDamage.fire and (strat.recentTypeRawDamage.fire / strat.recentTime) or 0)
    assert.are.equal(7, strat.recentTypeRawDamage.acid and (strat.recentTypeRawDamage.acid / strat.recentTime) or 0)
    assert.is_falsy(strat.recentTypeRawDamage.cold)

    -- totals reflect first session (rolled)
    assert.are.equal(100, strat.totalsDamage)
    -- per-type raw dps
    assert.are.equal(12, strat.totalsTypeRawDamage.fire and (strat.totalsTypeRawDamage.fire / strat.totalsTime) or 0)
    assert.are.equal(8, strat.totalsTypeRawDamage.cold and (strat.totalsTypeRawDamage.cold / strat.totalsTime) or 0)
    assert.is_falsy(strat.totalsTypeRawDamage.acid)
  end)
end)

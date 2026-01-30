require("spec/spec_helper")

describe("Per-target segmentation", function()
  before_each(function()
    set_time(0)
    reload_dps({ noSaveStub = true })
  end)

  it("records separate enemies when target changes mid-session", function()
    -- seed entity name mapping via Char.Items.List
    _G.gmcp = { Char = { Items = { List = { items = { { id = 1, name = "Spectre" }, { id = 2, name = "Millipede" } } } } } }
    DPS.onGMCPCharItemsList()

    DPS.start("StratZ")
    -- first segment target: Spectre
    gmcp.IRE = { Target = { Info = { id = 1 } } }
    DPS.onGMCPTarget()
    advance_time(5)
    DPS.addDamage(100)

    -- switch target: Millipede
    gmcp.IRE.Target.Info = { id = 2 }
    DPS.onGMCPTarget()
    -- trigger segment switch immediately at now=5
    DPS.addDamage(1)
    advance_time(5)
    DPS.addDamage(49)
    DPS.stop()

    local s = DPS._enemyStrategyStats("Spectre", "StratZ")
    local m = DPS._enemyStrategyStats("Millipede", "StratZ")
    assert.is_truthy(s)
    assert.is_truthy(m)
    assert.are.equal(1, s.recentCount)
    assert.are.equal(1, m.recentCount)
    assert.are.equal(20, s.recentDps)   -- 100 / 5
    assert.are.equal(10, m.recentDps)   -- 50 / 5
  end)
end)

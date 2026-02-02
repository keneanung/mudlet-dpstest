require("spec/spec_helper")

describe("GMCP handlers and helpers", function()
  before_each(function()
    set_time(0)
    reload_dps({ noSaveStub = true })
  end)

  it("updates entities mapping from Char.Items.* events (room only)", function()
    _G.gmcp = { Char = { Items = { List = { location = "room", items = { { id = 1, name = "Goblin" }, { id = 2, name = "Orc" } } }, Add = { location = "room", item = { id = 3, name = "Elf" } }, Update = { location = "room", item = { id = 2, name = "Orc2" } }, Remove = { location = "room", item = { id = 1 } } } } }
    DPS.onGMCPCharItemsList()
    assert.are.equal("Goblin", DPS.entitiesById["1"]) 
    assert.are.equal("Orc", DPS.entitiesById["2"]) 
    DPS.onGMCPCharItemsAdd()
    assert.are.equal("Elf", DPS.entitiesById["3"]) 
    DPS.onGMCPCharItemsUpdate()
    assert.are.equal("Orc2", DPS.entitiesById["2"]) 
    DPS.onGMCPCharItemsRemove()
    assert.is_nil(DPS.entitiesById["1"]) 
  end)

  it("resolves target via IRE.Target and recent-cleared buffer", function()
    _G.gmcp = { IRE = { Target = { Info = { id = 2 }, Set = nil } } }
    DPS.onGMCPTarget()
    assert.are.equal("2", DPS.currentTarget.id)
    -- ensure name lookup works using entitiesById
    DPS.entitiesById["2"] = "Orc2"
    DPS.onGMCPTarget()
    assert.are.equal("Orc2", DPS.currentTarget.name)
    -- clear target and ensure recent-cleared is set
    gmcp.IRE.Target.Info = ""
    DPS.onGMCPTarget()
    assert.are.equal("2", DPS.recentClearedTarget.id)
    -- ensure snapshot resolves from recent-cleared
    assert.are.equal("Orc2", DPS.resolveTargetNameSnapshot())
  end)

  it("covers localReport and auto helpers", function()
    -- seed some data
    DPS._recordEncounter({ name = "Strat", enemyName = "Orc2", damage = 100, rawDamage = 100, hits = 10, critHits = 0, typeDamage = {} }, 10)
    DPS.localReport("Orc2")
    -- auto start/stop
    DPS.current = nil
    DPS.autoMaybeStart()
    assert.is_truthy(DPS.current)
    DPS.autoStop("gmcp")
    assert.is_falsy(DPS.current)
    -- set label
    DPS.setLabel("newlabel")
    assert.are.equal("newlabel", DPS.strategyLabel)
    -- isAttacking paths
    _G.keneanung = { bashing = { attacking = 0 } }
    assert.is_false(DPS.isAttacking())
    keneanung.bashing.attacking = 2
    assert.is_true(DPS.isAttacking())
  end)
end)

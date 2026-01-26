require("spec/spec_helper")

describe("DPS damage types", function()
  before_each(function()
    set_time(0)
    reload_dps()
  end)

  it("tallies hits and damage per type", function()
    DPS.start("Types")
    DPS.addDamage(100, "psychic")
    DPS.addDamage(50, "fire")
    DPS.addDamage(75, "psychic")
    advance_time(5)
    DPS.stop()

    local s = DPS.strategies["Types"]
    assert.is_truthy(s)
    assert.are.equal(2, s.typeHits.psychic)
    assert.are.equal(175, s.typeDamage.psychic)
    assert.are.equal(1, s.typeHits.fire)
    assert.are.equal(50, s.typeDamage.fire)
  end)
end)

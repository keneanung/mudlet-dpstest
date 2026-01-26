require("spec/spec_helper")

describe("DPS pause/resume on regain when not attacking", function()
  before_each(function()
    set_time(0)
    reload_dps()
  end)

  it("excludes paused time from active duration", function()
    DPS.start("Pausable")
    -- 2s of active time
    advance_time(2)
    -- regain while not attacking -> pause
    _G.keneanung = { bashing = { attacking = 0 } }
    DPS.onRegain("balance")
    -- 5s pass while paused
    advance_time(5)
    -- resume on next damage and add 50
    DPS.addDamage(50)
    -- 3s more active
    advance_time(3)
    DPS.stop()

    local s = DPS.strategies["Pausable"]
    assert.are.equal(5, s.totalTime) -- 2s before pause + 3s after resume
    assert.are.equal(50, s.totalDamage)
  end)
end)

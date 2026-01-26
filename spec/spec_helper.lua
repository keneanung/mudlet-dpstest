-- Minimal Mudlet environment mocks for testing

-- controllable clock
local _now = 0
function set_time(t)
  _now = assert(tonumber(t))
end
function advance_time(dt)
  _now = _now + assert(tonumber(dt))
end
function getEpoch()
  return _now
end

-- mudlet functions used by the module
function cecho(_)
  -- no-op in tests
end

function getMudletHomeDir()
  return "."
end

-- provide a minimal yajl stub if needed
yajl = yajl or {
  to_string = function(_)
    return "{}"
  end,
  to_value = function(_)
    return {}
  end,
}

function reload_dps(opts)
  DPS = nil
  -- load the module file which auto-initializes
  dofile("src/scripts/DPS/dps.lua")
  -- avoid filesystem writes during tests
  if not (opts and opts.noSaveStub) then
    DPS.save = function() end
  end
end

DPS = DPS or {}

local function now()
  local ok, t = pcall(function() return getEpoch() end)
  if ok and type(t) == "number" then return t end
  return os.time()
end

local function ensureDir(path)
  local ok, lfsOrErr = pcall(function() return lfs end)
  local l = ok and lfsOrErr or (pcall(require, "lfs") and lfs or nil)
  if not l then return end
  if l.attributes(path, "mode") ~= "directory" then
    pcall(l.mkdir, path)
  end
end

local function dataFile()
  local base
  local ok, dir = pcall(function() return getMudletHomeDir() end)
  if ok and dir then
    base = dir .. "/@PKGNAME@"
  else
    base = "."
  end
  return base .. "/dps_data.json", base
end

local function json_encode(tbl)
  local ok, res = pcall(function() return yajl.to_string(tbl) end)
  if ok then return res end
  return nil
end

local function json_decode(str)
  local ok, res = pcall(function() return yajl.to_value(str) end)
  if ok then return res end
  return nil
end

function DPS.init()
  DPS.strategies = DPS.strategies or {}
  DPS.current = nil
  DPS.nextCritType = nil
  DPS.strategyLabel = DPS.strategyLabel or "auto"
  DPS._handlers = DPS._handlers or {}
  DPS.critMultipliers = {
    ["CRITICAL"] = 2,
    ["CRUSHING"] = 4,
    ["OBLITERATING"] = 8,
    ["ANNIHILATINGLY POWERFUL"] = 16,
    ["WORLD-SHATTERING"] = 32,
    ["PLANE-RAZING"] = 64,
  }
  -- load persisted data if available
  DPS.load()
  cecho("<green>DPS tracker ready. Use 'dps start <name>' and 'dps stop'.\n")
end

function DPS.start(name)
  if not name or name == "" then
    cecho("<yellow>DPS: Provide a strategy name: dps start <name>\n")
    return
  end
  if DPS.current then
    cecho(string.format("<yellow>DPS: Stopping previous '%s' first.\n", DPS.current.name))
    DPS.stop()
  end
  DPS.current = {
    name = name,
    start = now(),
    damage = 0,
    rawDamage = 0,
    hits = 0,
    critHits = 0,
    critTypes = {},
    typeHits = {},
    typeDamage = {},
    activeStart = now(),
    activeTime = 0
  }
  cecho(string.format("<cyan>DPS: Started '%s'.\n", name))
end

function DPS.stop()
  local cur = DPS.current
  if not cur then
    cecho("<yellow>DPS: No active strategy to stop.\n")
    return
  end
  cur.stop = now()
  -- accumulate any active segment
  local duration = cur.activeTime + (cur.activeStart and (now() - cur.activeStart) or 0)
  duration = math.max(0, math.floor(duration))
  local strat = DPS.strategies[cur.name] or { totalDamage = 0, totalRawDamage = 0, totalTime = 0, critHits = 0, critTypes = {}, typeHits = {}, typeDamage = {} }
  strat.totalDamage = strat.totalDamage + (cur.damage or 0)
  strat.totalRawDamage = strat.totalRawDamage + (cur.rawDamage or cur.damage or 0)
  strat.totalTime = strat.totalTime + duration
  strat.critHits = strat.critHits + (cur.critHits or 0)
  for k,v in pairs(cur.critTypes or {}) do
    strat.critTypes[k] = (strat.critTypes[k] or 0) + v
  end
  for k,v in pairs(cur.typeHits or {}) do
    strat.typeHits[k] = (strat.typeHits[k] or 0) + v
  end
  for k,v in pairs(cur.typeDamage or {}) do
    strat.typeDamage[k] = (strat.typeDamage[k] or 0) + v
  end
  DPS.strategies[cur.name] = strat
  local dps = duration > 0 and ((cur.damage or 0) / duration) or 0
  local rawdps = duration > 0 and ((cur.rawDamage or 0) / duration) or 0
  cecho(string.format("<green>DPS: '%s' session %ds, %d dmg (%d raw), %d hits (%d crits), %.1f dps / %.1f raw dps.\n", cur.name, duration, cur.damage or 0, cur.rawDamage or 0, cur.hits or 0, cur.critHits or 0, dps, rawdps))
  DPS.current = nil
  DPS.save()
end

function DPS.addDamage(amount, dtype)
  if not DPS.current then return end
  local a = tonumber(amount) or 0
  DPS.current.damage = (DPS.current.damage or 0) + a
  DPS.current.hits = (DPS.current.hits or 0) + 1
  if not DPS.current.activeStart then
    DPS.current.activeStart = now()
  end
  if dtype and dtype ~= "" then
    local key = string.lower(tostring(dtype))
    DPS.current.typeHits[key] = (DPS.current.typeHits[key] or 0) + 1
    DPS.current.typeDamage[key] = (DPS.current.typeDamage[key] or 0) + a
  end
  if DPS.nextCritType then
    DPS.current.critHits = (DPS.current.critHits or 0) + 1
    DPS.current.critTypes[DPS.nextCritType] = (DPS.current.critTypes[DPS.nextCritType] or 0) + 1
    local key = string.upper(DPS.nextCritType)
    local mult = DPS.critMultipliers[key] or 1
    local base = mult > 0 and (a / mult) or a
    DPS.current.rawDamage = (DPS.current.rawDamage or 0) + base
    DPS.nextCritType = nil
  else
    DPS.current.rawDamage = (DPS.current.rawDamage or 0) + a
  end
end

function DPS.report(name)
  if name and name ~= "" then
    local strat = DPS.strategies[name]
    if not strat then
      cecho(string.format("<yellow>DPS: No data for '%s'.\n", name))
      return
    end
    local dps = strat.totalTime > 0 and (strat.totalDamage / strat.totalTime) or 0
    local rawdps = strat.totalTime > 0 and (strat.totalRawDamage / strat.totalTime) or 0
    cecho(string.format("<cyan>DPS Report: '%s'\n", name))
    cecho(string.format("<white>- Totals: %d dmg (%d raw) over %ds\n", strat.totalDamage, strat.totalRawDamage, strat.totalTime))
    cecho(string.format("<white>- Rates: %.1f dps / %.1f raw dps\n", dps, rawdps))
    if (strat.critHits or 0) > 0 then
      local critParts = {}
      for k,v in pairs(strat.critTypes or {}) do
        table.insert(critParts, string.format("%s:%d", k, v))
      end
      table.sort(critParts)
      cecho(string.format("<white>- Crits: %d (%s)\n", strat.critHits or 0, table.concat(critParts, ", ")))
    else
      cecho("<white>- Crits: 0\n")
    end
    local hadTypes = false
    local tlist = {}
    for k,h in pairs(strat.typeHits or {}) do
      hadTypes = true
      local dmg = (strat.typeDamage and strat.typeDamage[k]) or 0
      table.insert(tlist, { k = k, hits = h, dmg = dmg })
    end
    if hadTypes then
      table.sort(tlist, function(a,b) return a.dmg > b.dmg end)
      cecho("<white>- Types:\n")
      for _, it in ipairs(tlist) do
        cecho(string.format("<white>  %s: %d hits (%d dmg)\n", it.k, it.hits, it.dmg))
      end
    end
  else
    DPS.compare()
  end
end

function DPS.compare()
  local list = {}
  for k, v in pairs(DPS.strategies) do
    local dps = v.totalTime > 0 and (v.totalDamage / v.totalTime) or 0
    local rawdps = v.totalTime > 0 and (v.totalRawDamage / v.totalTime) or 0
    table.insert(list, { name = k, dps = dps, rawdps = rawdps, damage = v.totalDamage, rawDamage = v.totalRawDamage, time = v.totalTime })
  end
  table.sort(list, function(a, b) return a.rawdps > b.rawdps end)
  cecho("<cyan>DPS: Comparison:\n")
  for i, it in ipairs(list) do
    cecho(string.format("<white>%2d. %-16s %.1f raw dps / %.1f dps (%d raw / %d dmg / %ds)\n", i, it.name, it.rawdps, it.dps, it.rawDamage or 0, it.damage, it.time))
  end
end

function DPS.flagCrit(t)
  DPS.nextCritType = t
end


function DPS.renameStrategy(oldName, newName)
  if not oldName or not newName or oldName == "" or newName == "" then
    cecho("<yellow>DPS: Usage: dps rename <old> <new>\n")
    return
  end
  if not DPS.strategies[oldName] then
    cecho(string.format("<yellow>DPS: No data for '%s'.\n", tostring(oldName)))
    return
  end
  if DPS.strategies[newName] then
    cecho(string.format("<yellow>DPS: '%s' already exists.\n", tostring(newName)))
    return
  end
  DPS.strategies[newName] = DPS.strategies[oldName]
  DPS.strategies[oldName] = nil
  if DPS.current and DPS.current.name == oldName then
    DPS.current.name = newName
  end
  cecho(string.format("<green>DPS: Renamed '%s' -> '%s'.\n", oldName, newName))
  DPS.save()
end

function DPS.removeStrategy(name)
  if not name or name == "" then
    cecho("<yellow>DPS: Usage: dps delete <name>\n")
    return
  end
  if not DPS.strategies[name] then
    cecho(string.format("<yellow>DPS: No data for '%s'.\n", tostring(name)))
    return
  end
  if DPS.current and DPS.current.name == name then
    cecho("<yellow>DPS: Stop the active session before deleting this strategy.\n")
    return
  end
  DPS.strategies[name] = nil
  cecho(string.format("<green>DPS: Deleted strategy '%s'.\n", name))
  DPS.save()
end

-- Auto start/stop helpers
function DPS.autoStop(reason)
  if DPS.current then
    cecho(string.format("<yellow>DPS: Auto-stopping (%s).\n", reason or ""))
    DPS.stop()
  end
end

function DPS.autoMaybeStart()
  if not DPS.current then
    local label = DPS.strategyLabel or "auto"
    DPS.start(label)
  end
end

-- External setters
function DPS.setLabel(name)
  if name and name ~= "" then
    DPS.strategyLabel = name
    cecho(string.format("<cyan>DPS: Strategy label set to '%s'.\n", name))
    DPS.save()
  end
end

function DPS.isAttacking()
  local ok, val = pcall(function()
    return keneanung and keneanung.bashing and keneanung.bashing.attacking
  end)
  if not ok then return false end
  local n = tonumber(val) or 0
  return n > 1
end

function DPS.onRegain(kind)
  if DPS.current and not DPS.isAttacking() then
    -- pause active time on regain if we are not attacking
    if DPS.current.activeStart then
      DPS.current.activeTime = (DPS.current.activeTime or 0) + (now() - DPS.current.activeStart)
      DPS.current.activeStart = nil
    end
  end
end

-- Persistence
function DPS.save()
  local file, dir = dataFile()
  ensureDir(dir)
  local payload = {
    version = 1,
    strategies = DPS.strategies or {},
    strategyLabel = DPS.strategyLabel or "auto",
  }
  local body = json_encode(payload)
  if not body then return end
  local fh = io.open(file, "w")
  if fh then
    fh:write(body)
    fh:close()
  end
end

function DPS.load()
  local file = dataFile()
  if type(file) == "table" then file = file[1] end
  local fh = io.open(file, "r")
  if not fh then return end
  local content = fh:read("*a")
  fh:close()
  local data = content and json_decode(content) or nil
  if type(data) == "table" then
    if type(data.strategies) == "table" then 
      DPS.strategies = data.strategies 
      -- clean up legacy sessions arrays if present
      for _, strat in pairs(DPS.strategies) do
        if strat.sessions then strat.sessions = nil end
      end
    end
    if type(data.strategyLabel) == "string" then DPS.strategyLabel = data.strategyLabel end
  end
end

-- Auto-initialize when the script loads
DPS.init()

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
  DPS.enemies = DPS.enemies or {}
  DPS.lastNSessions = DPS.lastNSessions or 10
  DPS.entitiesById = DPS.entitiesById or {}
  DPS.currentTarget = { id = nil, name = nil, cleared = false, ts = nil }
  DPS.recentClearedTarget = { id = nil, name = nil, expires = 0 }
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

  -- Register GMCP handlers using named registration only
  local regNamed = registerNamedEventHandler
  if type(regNamed) == "function" then
    local user = "DPS"
    local function reg(handlerName, eventName, fn)
      local ok = pcall(regNamed, user, handlerName, eventName, fn)
      if ok then table.insert(DPS._handlers, handlerName) end
    end
    reg("GMCPCharItemsList", "gmcp.Char.Items.List", DPS.onGMCPCharItemsList)
    reg("GMCPCharItemsAdd", "gmcp.Char.Items.Add", DPS.onGMCPCharItemsAdd)
    reg("GMCPCharItemsRemove", "gmcp.Char.Items.Remove", DPS.onGMCPCharItemsRemove)
    reg("GMCPCharItemsUpdate", "gmcp.Char.Items.Update", DPS.onGMCPCharItemsUpdate)
    reg("GMCPTarget", "gmcp.IRE.Target", DPS.onGMCPTarget)
  end
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
    enemyName = nil,
    damage = 0,
    rawDamage = 0,
    hits = 0,
    critHits = 0,
    critTypes = {},
    typeHits = {},
    typeDamage = {},
    typeRawDamage = {},
    activeStart = now(),
    activeTime = 0,
    seg = { enemyName = nil, damage = 0, rawDamage = 0, hits = 0, critHits = 0, critTypes = {}, typeHits = {}, typeDamage = {}, typeRawDamage = {}, activeStart = now(), activeTime = 0 }
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
  local dps = duration > 0 and ((cur.damage or 0) / duration) or 0
  local rawdps = duration > 0 and ((cur.rawDamage or 0) / duration) or 0
  cecho(string.format("<green>DPS: '%s' session %ds, %d dmg (%d raw), %d hits (%d crits), %.1f dps / %.1f raw dps.\n", cur.name, duration, cur.damage or 0, cur.rawDamage or 0, cur.hits or 0, cur.critHits or 0, dps, rawdps))

  -- Attribute encounter to enemyName + strategy (local optimization store)
  if cur.seg then
    local s = cur.seg
    local sdur = s.activeTime + (s.activeStart and (now() - s.activeStart) or 0)
    sdur = math.max(0, math.floor(sdur))
    if (s.hits or 0) > 0 or (s.damage or 0) > 0 then
      s.name = cur.name
      DPS._recordEncounter(s, sdur)
    end
  end

  DPS.current = nil
  DPS.save()
end

-- Show current session DPS without stopping
function DPS.status()
  local cur = DPS.current
  if not cur then
    cecho("<yellow>DPS: No active session.\n")
    return nil
  end
  local duration = cur.activeTime + (cur.activeStart and (now() - cur.activeStart) or 0)
  duration = math.max(0, math.floor(duration))
  local dps = duration > 0 and ((cur.damage or 0) / duration) or 0
  local rawdps = duration > 0 and ((cur.rawDamage or 0) / duration) or 0

  cecho(string.format("<cyan>DPS status: '%s' %ds, %d dmg (%d raw), %d hits (%d crits), %.1f dps / %.1f raw dps%s\n",
    cur.name,
    duration,
    cur.damage or 0,
    cur.rawDamage or 0,
    cur.hits or 0,
    cur.critHits or 0,
    dps,
    rawdps,
    cur.enemyName and (", enemy: " .. tostring(cur.enemyName)) or ""))

  -- also compute current segment if present
  local seg = cur.seg
  local segInfo
  if seg then
    local sdur = seg.activeTime + (seg.activeStart and (now() - seg.activeStart) or 0)
    sdur = math.max(0, math.floor(sdur))
    local sdps = sdur > 0 and ((seg.damage or 0) / sdur) or 0
    local sraw = sdur > 0 and ((seg.rawDamage or 0) / sdur) or 0
    segInfo = {
      enemyName = seg.enemyName,
      duration = sdur,
      damage = seg.damage or 0,
      rawDamage = seg.rawDamage or 0,
      hits = seg.hits or 0,
      critHits = seg.critHits or 0,
      dps = sdps,
      rawDps = sraw,
    }
  end

  return {
    name = cur.name,
    enemyName = cur.enemyName,
    duration = duration,
    damage = cur.damage or 0,
    rawDamage = cur.rawDamage or 0,
    hits = cur.hits or 0,
    critHits = cur.critHits or 0,
    dps = dps,
    rawDps = rawdps,
    segment = segInfo,
  }
end

function DPS.addDamage(amount, dtype)
  if not DPS.current then return end
  local a = tonumber(amount) or 0
  -- Resolve target name snapshot on every hit to segment per enemy
  local snap = DPS.resolveTargetNameSnapshot()
  if not snap and DPS.recentClearedTarget and DPS.recentClearedTarget.id then
    snap = DPS.entitiesById[tostring(DPS.recentClearedTarget.id)]
  end
  local cur = DPS.current
  -- initialize segment enemy name if unknown, prefer explicit current.enemyName if set
  if cur.seg and not cur.seg.enemyName then
    cur.seg.enemyName = snap or cur.enemyName or "unknown"
    cur.enemyName = cur.seg.enemyName
  elseif cur.seg and snap and snap ~= cur.seg.enemyName then
    -- close previous segment and start a new one
    local s = cur.seg
    local sdur = s.activeTime + (s.activeStart and (now() - s.activeStart) or 0)
    sdur = math.max(0, math.floor(sdur))
    if (s.hits or 0) > 0 or (s.damage or 0) > 0 then
      s.name = cur.name
      DPS._recordEncounter(s, sdur)
    end
    -- start new segment for new target
    cur.seg = { enemyName = snap, damage = 0, rawDamage = 0, hits = 0, critHits = 0, critTypes = {}, typeHits = {}, typeDamage = {}, typeRawDamage = {}, activeStart = now(), activeTime = 0 }
    cur.enemyName = cur.seg.enemyName
  end
  DPS.current.damage = (DPS.current.damage or 0) + a
  DPS.current.hits = (DPS.current.hits or 0) + 1
  if not DPS.current.activeStart then
    DPS.current.activeStart = now()
  end
  local baseForRaw = a
  if DPS.nextCritType then
    DPS.current.critHits = (DPS.current.critHits or 0) + 1
    DPS.current.critTypes[DPS.nextCritType] = (DPS.current.critTypes[DPS.nextCritType] or 0) + 1
    local key = string.upper(DPS.nextCritType)
    local mult = DPS.critMultipliers[key] or 1
    local base = mult > 0 and (a / mult) or a
    baseForRaw = base
    DPS.current.rawDamage = (DPS.current.rawDamage or 0) + base
    if cur.seg then
      cur.seg.critHits = (cur.seg.critHits or 0) + 1
      cur.seg.critTypes[DPS.nextCritType] = (cur.seg.critTypes[DPS.nextCritType] or 0) + 1
      cur.seg.rawDamage = (cur.seg.rawDamage or 0) + base
    end
    DPS.nextCritType = nil
  else
    DPS.current.rawDamage = (DPS.current.rawDamage or 0) + a
    if cur.seg then
      cur.seg.rawDamage = (cur.seg.rawDamage or 0) + a
    end
  end
  if dtype and dtype ~= "" then
    local key = string.lower(tostring(dtype))
    DPS.current.typeHits[key] = (DPS.current.typeHits[key] or 0) + 1
    DPS.current.typeDamage[key] = (DPS.current.typeDamage[key] or 0) + a
    DPS.current.typeRawDamage[key] = (DPS.current.typeRawDamage[key] or 0) + baseForRaw
    if cur.seg then
      cur.seg.typeHits[key] = (cur.seg.typeHits[key] or 0) + 1
      cur.seg.typeDamage[key] = (cur.seg.typeDamage[key] or 0) + a
      cur.seg.typeRawDamage[key] = (cur.seg.typeRawDamage[key] or 0) + baseForRaw
    end
  end
  if cur.seg then
    cur.seg.damage = (cur.seg.damage or 0) + a
    cur.seg.hits = (cur.seg.hits or 0) + 1
    if not cur.seg.activeStart then
      cur.seg.activeStart = now()
    end
  end
end

-- Local optimization store: per enemy name + strategy totals and last-N buffer
function DPS._recordEncounter(cur, duration)
  local enemy = cur.enemyName or "unknown"
  local stratName = cur.name
  DPS.enemies[enemy] = DPS.enemies[enemy] or { strategies = {} }
  local E = DPS.enemies[enemy].strategies
  E[stratName] = E[stratName] or { totals = { damage = 0, rawDamage = 0, time = 0, hits = 0, critHits = 0, typeDamage = {} }, recent = {} }
  local entry = {
    damage = cur.damage or 0,
    rawDamage = cur.rawDamage or (cur.damage or 0),
    time = duration or 0,
    hits = cur.hits or 0,
    critHits = cur.critHits or 0,
    typeDamage = cur.typeDamage or {},
    typeRawDamage = cur.typeRawDamage or {},
  }
  -- push to recent buffer
  table.insert(E[stratName].recent, entry)
  -- roll oldest into totals if buffer exceeds N
  local N = DPS.lastNSessions or 10
  while #E[stratName].recent > N do
    local old = table.remove(E[stratName].recent, 1)
    local T = E[stratName].totals
    T.damage = (T.damage or 0) + (old.damage or 0)
    T.rawDamage = (T.rawDamage or 0) + (old.rawDamage or (old.damage or 0))
    T.time = (T.time or 0) + (old.time or 0)
    T.hits = (T.hits or 0) + (old.hits or 0)
    T.critHits = (T.critHits or 0) + (old.critHits or 0)
    for k,v in pairs(old.typeDamage or {}) do
      T.typeDamage[k] = (T.typeDamage[k] or 0) + v
    end
    T.typeRawDamage = T.typeRawDamage or {}
    for k,v in pairs(old.typeRawDamage or {}) do
      T.typeRawDamage[k] = (T.typeRawDamage[k] or 0) + v
    end
  end
end

-- Compute last-N mean DPS and totals DPS for an enemy+strategy
function DPS._enemyStrategyStats(enemy, stratName)
  local e = DPS.enemies[enemy]
  if not e then return nil end
  local s = e.strategies[stratName]
  if not s then return nil end
  local recentDamage, recentRawDamage, recentTime = 0, 0, 0
  local recentHits, recentCritHits = 0, 0
  local recentTypeDamage = {}
  local recentTypeRawDamage = {}
  for _, r in ipairs(s.recent) do
    recentDamage = recentDamage + (r.damage or 0)
    recentRawDamage = recentRawDamage + (r.rawDamage or (r.damage or 0))
    recentTime = recentTime + (r.time or 0)
    recentHits = recentHits + (r.hits or 0)
    recentCritHits = recentCritHits + (r.critHits or 0)
    for k, v in pairs(r.typeDamage or {}) do
      recentTypeDamage[k] = (recentTypeDamage[k] or 0) + v
    end
    for k, v in pairs(r.typeRawDamage or {}) do
      recentTypeRawDamage[k] = (recentTypeRawDamage[k] or 0) + v
    end
  end
  local totals = s.totals
  local lastNdps = recentTime > 0 and (recentDamage / recentTime) or 0
  local lastNrawDps = recentTime > 0 and (recentRawDamage / recentTime) or 0
  local totalsDps = (totals.time or 0) > 0 and ((totals.damage or 0) / (totals.time or 1)) or 0
  local totalsRawDps = (totals.time or 0) > 0 and ((totals.rawDamage or 0) / (totals.time or 1)) or 0
  return {
    recentCount = #s.recent,
    recentDps = lastNdps,
    totalsDps = totalsDps,
    recentRawDps = lastNrawDps,
    totalsRawDps = totalsRawDps,
    recentDamage = recentDamage,
    recentRawDamage = recentRawDamage,
    recentTime = recentTime,
    recentHits = recentHits,
    recentCritHits = recentCritHits,
    recentTypeDamage = recentTypeDamage,
    recentTypeRawDamage = recentTypeRawDamage,
    totalsDamage = totals.damage or 0,
    totalsRawDamage = totals.rawDamage or 0,
    totalsTime = totals.time or 0,
    totalsHits = totals.hits or 0,
    totalsCritHits = totals.critHits or 0,
    totalsTypeDamage = totals.typeDamage or {},
    totalsTypeRawDamage = totals.typeRawDamage or {},
  }
end

function DPS.localReport(enemyName)
  local enemy
  if enemyName and enemyName ~= "" then
    -- resolve exact or substring match
    enemy = DPS.resolveEnemyName and DPS.resolveEnemyName(enemyName) or enemyName
  else
    enemy = (DPS.current and DPS.current.enemyName) or "unknown"
  end
  local e = DPS.enemies[enemy]
  if not e or not e.strategies then
    cecho(string.format("<yellow>DPS: No local data for '%s'.\n", enemyName or enemy))
    return {}
  end
  cecho(string.format("<cyan>DPS Local: '%s'\n", enemy))
  local list = {}
  for stratName, _ in pairs(e.strategies) do
    local st = DPS._enemyStrategyStats(enemy, stratName)
    table.insert(list, {
      name = stratName,
      recentDps = st.recentDps,
      totalsDps = st.totalsDps,
      recentRawDps = st.recentRawDps,
      totalsRawDps = st.totalsRawDps,
      recentTime = st.recentTime,
      recentDamage = st.recentDamage,
      totalsDamage = st.totalsDamage,
      totalsTime = st.totalsTime,
      recentCount = st.recentCount,
      recentHits = st.recentHits,
      recentCritHits = st.recentCritHits,
      totalsHits = st.totalsHits,
      totalsCritHits = st.totalsCritHits,
      recentTypeDamage = st.recentTypeDamage,
      totalsTypeDamage = st.totalsTypeDamage,
      recentTypeRawDamage = st.recentTypeRawDamage,
      totalsTypeRawDamage = st.totalsTypeRawDamage,
    })
  end
  table.sort(list, function(a,b) return a.recentRawDps > b.recentRawDps end)
  for _, it in ipairs(list) do
    cecho(string.format("<white>%-16s last-%d: %.1f dps (%.1f raw) | totals: %.1f dps (%.1f raw)\n", it.name, it.recentCount, it.recentDps, it.recentRawDps, it.totalsDps, it.totalsRawDps))
    cecho(string.format("<white>  recent: hits %d (crit %d) | totals: hits %d (crit %d)\n", it.recentHits or 0, it.recentCritHits or 0, it.totalsHits or 0, it.totalsCritHits or 0))
    local function printTypesRawDps(label, dmgTbl, time)
      local parts = {}
      if (time or 0) > 0 then
        for k, v in pairs(dmgTbl or {}) do table.insert(parts, string.format("%s: %.1f", k, (v or 0) / time)) end
      end
      table.sort(parts)
      if #parts > 0 then
        cecho(string.format("<white>  %s: %s\n", label, table.concat(parts, ", ")))
      end
    end
    printTypesRawDps("recent types (raw dps)", it.recentTypeRawDamage, it.recentTime)
    printTypesRawDps("totals types (raw dps)", it.totalsTypeRawDamage, it.totalsTime)
  end
  return list
end

-- Resolve an enemy name from user input supporting case-insensitive substring search.
-- Returns the exact name if found, the single substring match if unique,
-- or nil and prints an ambiguity/no-match message.
function DPS.resolveEnemyName(input)
  if not input or input == "" then return (DPS.current and DPS.current.enemyName) or "unknown" end
  local enemies = DPS.enemies or {}
  -- exact match first
  if enemies[input] then return input end
  local q = string.lower(tostring(input))
  local matches = {}
  for name, _ in pairs(enemies) do
    if string.find(string.lower(name), q, 1, true) then
      table.insert(matches, name)
    end
  end
  table.sort(matches)
  if #matches == 1 then
    return matches[1]
  elseif #matches > 1 then
    cecho(string.format("<yellow>DPS: Ambiguous enemy '%s'. Matches: %s\n", input, table.concat(matches, ", ")))
    return nil
  else
    cecho(string.format("<yellow>DPS: No enemy matching '%s'.\n", input))
    return nil
  end
end

-- List all enemies with recorded local data
function DPS.listEnemies()
  local result = {}
  local enemies = DPS.enemies or {}
  for name, data in pairs(enemies) do
    local s = data.strategies or {}
    local count = 0
    for _ in pairs(s) do count = count + 1 end
    table.insert(result, { name = name, strategies = count })
  end
  table.sort(result, function(a,b) return a.name < b.name end)
  if #result == 0 then
    cecho("<yellow>DPS: No enemies recorded yet.\n")
    return result
  end
  cecho("<cyan>DPS Enemies:\n")
  for _, it in ipairs(result) do
    cecho(string.format("<white>%-24s strategies: %d\n", it.name, it.strategies))
  end
  return result
end

-- Comparison overview: show recent/total DPS per enemy for a strategy
function DPS.overview(stratName)
  local strat = (stratName and stratName ~= "") and stratName or (DPS.strategyLabel or "auto")
  local enemies = DPS.enemies or {}
  local list = {}
  for enemy, data in pairs(enemies) do
    local s = data.strategies and data.strategies[strat]
    if s then
      local st = DPS._enemyStrategyStats(enemy, strat)
      if st then
        table.insert(list, {
          enemy = enemy,
          recentDps = st.recentRawDps,
          totalsDps = st.totalsRawDps,
          recentCount = st.recentCount,
        })
      end
    end
  end
  table.sort(list, function(a,b)
    if a.recentDps == b.recentDps then return a.enemy < b.enemy end
    return a.recentDps < b.recentDps
  end)
  if #list == 0 then
    cecho(string.format("<yellow>DPS: No overview data for strategy '%s'.\n", strat))
    return list
  end
  cecho(string.format("<cyan>DPS Overview for '%s' (lower = likely resistance; raw dps)\n", strat))
  for _, it in ipairs(list) do
    cecho(string.format("<white>%-24s last-%d: %.1f raw dps | totals: %.1f raw dps\n", it.enemy, it.recentCount, it.recentDps, it.totalsDps))
  end
  return list
end

function DPS.resetLocal(enemyName, stratName)
  local enemy = enemyName or (DPS.current and DPS.current.enemyName)
  if not enemy or not DPS.enemies[enemy] then return end
  if stratName then
    DPS.enemies[enemy].strategies[stratName] = nil
  else
    DPS.enemies[enemy] = nil
  end
  cecho(string.format("<green>DPS: Reset local data for '%s'%s.\n", enemy, stratName and ("/"..stratName) or ""))
  DPS.save()
end

-- Internal helpers for merging data structures
local function _addTypeTable(dst, src)
  if not src then return end
  for k, v in pairs(src) do
    dst[k] = (dst[k] or 0) + (v or 0)
  end
end

local function _rollIntoTotals(totals, entry)
  totals.damage = (totals.damage or 0) + (entry.damage or 0)
  totals.rawDamage = (totals.rawDamage or 0) + (entry.rawDamage or (entry.damage or 0))
  totals.time = (totals.time or 0) + (entry.time or 0)
  totals.hits = (totals.hits or 0) + (entry.hits or 0)
  totals.critHits = (totals.critHits or 0) + (entry.critHits or 0)
  totals.typeDamage = totals.typeDamage or {}
  totals.typeRawDamage = totals.typeRawDamage or {}
  _addTypeTable(totals.typeDamage, entry.typeDamage or {})
  _addTypeTable(totals.typeRawDamage, entry.typeRawDamage or {})
end

local function _normalizeRecentForStrategy(strategyData, N)
  local recent = strategyData.recent or {}
  strategyData.totals = strategyData.totals or { damage = 0, rawDamage = 0, time = 0, hits = 0, critHits = 0, typeDamage = {}, typeRawDamage = {} }
  while #recent > N do
    local old = table.remove(recent, 1)
    _rollIntoTotals(strategyData.totals, old)
  end
end

local function _mergeStrategies(dstS, srcS, N)
  dstS.totals = dstS.totals or { damage = 0, rawDamage = 0, time = 0, hits = 0, critHits = 0, typeDamage = {}, typeRawDamage = {} }
  srcS.totals = srcS.totals or { damage = 0, rawDamage = 0, time = 0, hits = 0, critHits = 0, typeDamage = {}, typeRawDamage = {} }

  -- merge totals
  dstS.totals.damage = (dstS.totals.damage or 0) + (srcS.totals.damage or 0)
  dstS.totals.rawDamage = (dstS.totals.rawDamage or 0) + (srcS.totals.rawDamage or 0)
  dstS.totals.time = (dstS.totals.time or 0) + (srcS.totals.time or 0)
  dstS.totals.hits = (dstS.totals.hits or 0) + (srcS.totals.hits or 0)
  dstS.totals.critHits = (dstS.totals.critHits or 0) + (srcS.totals.critHits or 0)
  dstS.totals.typeDamage = dstS.totals.typeDamage or {}
  dstS.totals.typeRawDamage = dstS.totals.typeRawDamage or {}
  _addTypeTable(dstS.totals.typeDamage, srcS.totals.typeDamage or {})
  _addTypeTable(dstS.totals.typeRawDamage, srcS.totals.typeRawDamage or {})

  -- concat recents
  dstS.recent = dstS.recent or {}
  srcS.recent = srcS.recent or {}
  for _, r in ipairs(srcS.recent) do table.insert(dstS.recent, r) end

  -- normalize to last-N and roll overflow into totals
  _normalizeRecentForStrategy(dstS, N)
end

-- Merge enemy data from 'fromName' into 'toName', keeping 'toName' and removing 'fromName'.
-- Returns true on success.
function DPS.mergeEnemies(fromName, toName)
  if not fromName or not toName or fromName == toName then
    cecho("<yellow>DPS: Provide distinct source and target names.\n")
    return false
  end
  local enemies = DPS.enemies or {}
  local srcKey = DPS.resolveEnemyName and DPS.resolveEnemyName(fromName) or fromName
  if not srcKey or not enemies[srcKey] then
    cecho(string.format("<yellow>DPS: Source enemy '%s' not found.\n", fromName))
    return false
  end
  local dstKey = enemies[toName] and toName or (DPS.resolveEnemyName and DPS.resolveEnemyName(toName) or nil)
  if not dstKey then
    cecho(string.format("<yellow>DPS: Target enemy '%s' not found. Use rename to create a new name.\n", toName))
    return false
  end
  if not enemies[dstKey] then
    cecho(string.format("<yellow>DPS: Target enemy '%s' not found.\n", toName))
    return false
  end
  if srcKey == dstKey then
    cecho("<yellow>DPS: Source and target resolve to the same enemy.\n")
    return false
  end

  local N = DPS.lastNSessions or 10
  local dst = enemies[dstKey]
  local src = enemies[srcKey]
  dst.strategies = dst.strategies or {}
  src.strategies = src.strategies or {}
  for strat, sdata in pairs(src.strategies) do
    if not dst.strategies[strat] then
      -- shallow copy src strategy data
      dst.strategies[strat] = { totals = { damage = 0, rawDamage = 0, time = 0, hits = 0, critHits = 0, typeDamage = {}, typeRawDamage = {} }, recent = {} }
      _mergeStrategies(dst.strategies[strat], sdata, N)
    else
      _mergeStrategies(dst.strategies[strat], sdata, N)
    end
  end
  enemies[srcKey] = nil
  cecho(string.format("<green>DPS: Merged '%s' into '%s'.\n", srcKey, dstKey))
  DPS.save()
  return true
end

-- Rename 'fromName' to 'toName'. If 'toName' exists, merges into it.
function DPS.renameEnemy(fromName, toName)
  if not fromName or not toName or fromName == toName then
    cecho("<yellow>DPS: Provide distinct source and target names.\n")
    return false
  end
  local enemies = DPS.enemies or {}
  local srcKey = DPS.resolveEnemyName and DPS.resolveEnemyName(fromName) or fromName
  if not srcKey or not enemies[srcKey] then
    cecho(string.format("<yellow>DPS: Enemy '%s' not found.\n", fromName))
    return false
  end
  -- If destination exists (exact), merge instead of raw rename. Do not substring-resolve target to allow creating new names like 'Gob'.
  local dstKey = enemies[toName] and toName or nil
  if dstKey then
    return DPS.mergeEnemies(srcKey, dstKey)
  end
  -- Create new entry with the new name
  enemies[toName] = enemies[srcKey]
  enemies[srcKey] = nil
  cecho(string.format("<green>DPS: Renamed '%s' to '%s'.\n", srcKey, toName))
  DPS.save()
  return true
end

function DPS.setLastN(n)
  local v = tonumber(n)
  if v and v > 0 then
    DPS.lastNSessions = v
    cecho(string.format("<cyan>DPS: last-N sessions set to %d.\n", v))
    DPS.save()
  end
end

-- GMCP integration
local function gmcpTable(path)
  local ok, tbl = pcall(function()
    local parts = {}
    for p in string.gmatch(path, "[^.]+") do table.insert(parts, p) end
    local t = gmcp
    for _, k in ipairs(parts) do t = t and t[k] end
    return t
  end)
  if ok then return tbl end
  return nil
end

function DPS.onGMCPCharItemsList()
  local data = gmcpTable("Char.Items.List")
  if type(data) ~= "table" or type(data.items) ~= "table" then return end
  if data.location ~= "room" then return end
  DPS.entitiesById = {}
  for _, item in ipairs(data.items) do
    if item.id and item.name then
      DPS.entitiesById[tostring(item.id)] = item.name
    end
  end
end

function DPS.onGMCPCharItemsAdd()
  local data = gmcpTable("Char.Items.Add")
  if type(data) ~= "table" or data.location ~= "room" then return end
  local item = data.item
  if type(item) == "table" and item.id and item.name then
    DPS.entitiesById[tostring(item.id)] = item.name
  end
end

function DPS.onGMCPCharItemsUpdate()
  local data = gmcpTable("Char.Items.Update")
  if type(data) ~= "table" or data.location ~= "room" then return end
  local item = data.item
  if type(item) == "table" and item.id and item.name then
    DPS.entitiesById[tostring(item.id)] = item.name
  end
end

function DPS.onGMCPCharItemsRemove()
  local data = gmcpTable("Char.Items.Remove")
  if type(data) ~= "table" or data.location ~= "room" then return end
  local item = data.item
  if type(item) == "table" and item.id then
    DPS.entitiesById[tostring(item.id)] = nil
  end
end

function DPS.onGMCPTarget()
  local t = gmcpTable("IRE.Target")
  if type(t) ~= "table" then return end
  local info = t.Info
  local set = t.Set
  if info == "" or not info then
    -- cleared: store recent for kill-hit attribution
    if DPS.currentTarget and DPS.currentTarget.id then
      DPS.recentClearedTarget.id = DPS.currentTarget.id
      DPS.recentClearedTarget.name = DPS.currentTarget.name
      DPS.recentClearedTarget.expires = now() + 2
    end
    DPS.currentTarget = { id = nil, name = nil, cleared = true, ts = now() }
    return
  end
  -- info present: update current target
  local id = (type(info) == "table" and info.id) or set or nil
  id = id and tostring(id) or nil
  local name = id and DPS.entitiesById[id] or nil
  DPS.currentTarget = { id = id, name = name, cleared = false, ts = now() }
end

function DPS.resolveTargetNameSnapshot()
  if DPS.currentTarget and (not DPS.currentTarget.cleared) then
    local name = DPS.currentTarget.name
    if (not name) and DPS.currentTarget.id then
      name = DPS.entitiesById[tostring(DPS.currentTarget.id)]
    end
    if name then return name end
  end
  if DPS.recentClearedTarget and DPS.recentClearedTarget.expires > now() then
    local name = DPS.recentClearedTarget.name
    if (not name) and DPS.recentClearedTarget.id then
      name = DPS.entitiesById[tostring(DPS.recentClearedTarget.id)]
    end
    if name then return name end
  end
  return nil
end

-- legacy report/compare removed: focus on per-enemy local reporting

function DPS.flagCrit(t)
  DPS.nextCritType = t
end


-- legacy rename/remove removed

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
    if DPS.current.seg and DPS.current.seg.activeStart then
      DPS.current.seg.activeTime = (DPS.current.seg.activeTime or 0) + (now() - DPS.current.seg.activeStart)
      DPS.current.seg.activeStart = nil
    end
  end
end

-- Persistence
function DPS.save()
  local file, dir = dataFile()
  ensureDir(dir)
  local payload = {
    version = 3,
    strategyLabel = DPS.strategyLabel or "auto",
    enemies = DPS.enemies or {},
    lastNSessions = DPS.lastNSessions or 10,
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
    if type(data.strategyLabel) == "string" then DPS.strategyLabel = data.strategyLabel end
    if type(data.enemies) == "table" then DPS.enemies = data.enemies end
    if type(data.lastNSessions) == "number" then DPS.lastNSessions = data.lastNSessions end
  end
end

-- Auto-initialize when the script loads
DPS.init()

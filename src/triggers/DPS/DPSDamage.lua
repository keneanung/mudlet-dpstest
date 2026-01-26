local amount = tonumber(matches[2]) or 0
local dtype = matches[3]
if not DPS.current then DPS.autoMaybeStart() end
DPS.addDamage(amount, dtype)

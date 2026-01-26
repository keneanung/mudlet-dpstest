local desc = matches[2] or ""
if desc == "" or desc:match("^CRITICAL$") then
  DPS.flagCrit("CRITICAL")
else
  DPS.flagCrit(desc)
end

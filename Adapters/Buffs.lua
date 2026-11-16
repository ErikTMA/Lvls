-- The leveling buffs on you and the cooldowns of their items (Engine/Buffs.lua), from
-- the forever client (Gethe/wow-ui-source branch `forever`, 1.60.1):
-- C_UnitAuras.GetPlayerAuraBySpellID (AuraData applications / expirationTime),
-- C_Container.GetItemCooldown (startTime, duration), GetTime. A change to one of
-- these buffs (UNIT_AURA on the player) or an item's cooldown running out asks for a
-- refresh (LVLS_STATE), so the step's buff line and the item bar follow.
local _, ns = ...
local BA = ns:NewModule("BuffData")
local G = ns.Game
local plain = ns.Util.plain

-- { [aura] = { stacks, left } }, { [item] = seconds left }
function BA.State()
  local buffs, cds = {}, {}
  local now = GetTime and GetTime() or 0
  for _, b in ipairs(ns.Buffs.List()) do
    if G.has(C_UnitAuras, "GetPlayerAuraBySpellID") then
      local ok, a = pcall(C_UnitAuras.GetPlayerAuraBySpellID, b.aura)
      if ok and type(a) == "table" then
        local exp = plain(a.expirationTime)
        buffs[b.aura] = { stacks = plain(a.applications) or 1,
          left = (exp and exp > 0) and math.max(0, exp - now) or nil }
      end
    end
    if G.has(C_Container, "GetItemCooldown") then
      local ok, start, dur = pcall(C_Container.GetItemCooldown, b.item)
      start, dur = ok and plain(start), ok and plain(dur)
      if start and dur and start > 0 and dur > 1.5 then -- (the global cooldown is no wait)
        cds[b.item] = math.max(0, start + dur - now)
      end
    end
  end
  return buffs, cds
end

-- A key of what Engine/Buffs looks at: each buff's stacks, whether it runs low, and
-- whether its item is ready.
local function key()
  local buffs, cds = BA.State()
  local parts = {}
  for _, b in ipairs(ns.Buffs.List()) do
    local a = buffs[b.aura]
    local low = a and a.left and a.left <= ns.Buffs.RENEW and 1 or 0
    parts[#parts + 1] = (a and a.stacks or 0) .. ":" .. low .. ":" .. ((cds[b.item] or 0) > 0 and 1 or 0)
  end
  return table.concat(parts, ","), cds
end

if CreateFrame then
  local f = CreateFrame("Frame")
  local last
  local function check()
    local k, cds = key()
    if k == last then return end
    last = k
    ns.Events.Fire("LVLS_STATE", "BUFFS")
    -- when a cooldown ends nothing fires: look again then (once per change)
    local soon
    for _, s in pairs(cds) do soon = math.min(soon or s, s) end
    if C_Timer and C_Timer.After and soon then C_Timer.After(soon + 1, check) end
  end
  BA.Check = check
  f:RegisterEvent("PLAYER_ENTERING_WORLD")
  f:RegisterEvent("BAG_UPDATE_COOLDOWN")
  if f.RegisterUnitEvent then f:RegisterUnitEvent("UNIT_AURA", "player") else f:RegisterEvent("UNIT_AURA") end
  f:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_AURA" and unit ~= "player" then return end
    check()
  end)
  -- a buff running low (Engine/Buffs.RENEW) changes no event either
  if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(60, check) end
end

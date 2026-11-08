-- Dungeon facts from the client and what Lvls! learns while playing.
--   name: C_Map.GetAreaInfo(areaID) (the client's own, localized), else the shipped
--         name (Data/forever/Dungeons.lua), else "Dungeon <id>"
--   entrance: the shipped one (where a ghost revives, from the client's Map table),
--         else the spot you last stood outside before entering it (learned)
--   inside: GetInstanceInfo() -> name, instanceType, ..., instanceID (8th)
local _, ns = ...
local DI = ns:NewModule("DungeonInfo")

local function has(t, k) return type(t) == "table" and type(t[k]) == "function" end

function DI.Data(area) return ns.DungeonData and ns.DungeonData[area] end

function DI.Name(area)
  if has(C_Map, "GetAreaInfo") then
    local n = C_Map.GetAreaInfo(area)
    if type(n) == "string" and n ~= "" then return n end
  end
  local d = DI.Data(area)
  return d and d.n or ("Dungeon " .. tostring(area))
end

function DI.Entrance(area)
  local d = DI.Data(area)
  if d and d.e then return { map = d.e[1], x = d.e[2], y = d.e[3] } end
  local learned = ns.db and ns.db.dungeonEntrances
  local e = d and d.inst and learned and learned[d.inst]
  if e then return { map = e.map, x = e.x, y = e.y } end
  return nil
end

function DI.Instance()
  if type(GetInstanceInfo) ~= "function" then return nil end
  local _, kind, _, _, _, _, _, id = GetInstanceInfo()
  if kind == "party" or kind == "raid" then return id end
  return nil
end

function DI.Inside(area)
  local d = DI.Data(area)
  local id = DI.Instance()
  return id ~= nil and d ~= nil and d.inst == id
end

-- Called with the character's position on every refresh: outside, remember it;
-- just inside an instance without a known entrance, the last outside spot is it.
function DI.Track(pos)
  local id = DI.Instance()
  if not id then
    if pos then DI.outside = pos end
    return
  end
  if not DI.outside or not ns.db then return end
  ns.db.dungeonEntrances = ns.db.dungeonEntrances or {}
  local known = false
  for _, d in pairs(ns.DungeonData or {}) do
    if d.inst == id and d.e then known = true end
  end
  if not known and not ns.db.dungeonEntrances[id] then
    local p = DI.outside
    ns.db.dungeonEntrances[id] = { map = p.map, x = p.x, y = p.y }
  end
  DI.outside = nil
end

-- the env Engine/Dungeons wants
DI.env = { name = function(area) return DI.Name(area) end }

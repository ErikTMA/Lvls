-- WoW client adapter. Every call is feature-detected. Verified against Blizzard's UI
-- source for the forever client (Gethe/wow-ui-source branch `forever`, 1.60.1):
--   C_QuestLog.GetAllCompletedQuestIDs / GetNumQuestLogEntries / GetInfo /
--   IsComplete / ReadyForTurnIn / GetQuestObjectives, C_Map.GetBestMapForUnit /
--   GetPlayerMapPosition / GetWorldPosFromMapPos / GetMapWorldSize / GetMapInfo,
--   C_Map.SetUserWaypoint + C_SuperTrack.SetSuperTrackedUserWaypoint,
--   C_Minimap.GetViewRadius, UnitPosition-free (map positions only).
local _, ns = ...
local G = ns:NewModule("Game")

local function has(t, k) return type(t) == "table" and type(t[k]) == "function" end
G.has = has

function G.Flavor()
  if not GetBuildInfo then return "forever" end
  local ver = GetBuildInfo()
  local major, minor = tostring(ver or ""):match("^(%d+)%.(%d+)")
  if tonumber(major) == 1 and tonumber(minor) and tonumber(minor) >= 60 then return "forever" end
  return "unsupported"
end

function G.Completed()
  local out = {}
  if has(C_QuestLog, "GetAllCompletedQuestIDs") then
    for _, id in ipairs(C_QuestLog.GetAllCompletedQuestIDs() or {}) do out[id] = true end
  end
  return out
end

-- { [questId] = { title, level, complete, objectives = { {text, finished, type,
--   have, need}, ... } } }
function G.QuestLog()
  local out = {}
  if not has(C_QuestLog, "GetNumQuestLogEntries") or not has(C_QuestLog, "GetInfo") then return out end
  local n = C_QuestLog.GetNumQuestLogEntries() or 0
  for i = 1, n do
    local info = C_QuestLog.GetInfo(i)
    if info and not info.isHeader and info.questID and info.questID > 0 then
      local id = info.questID
      local complete = (has(C_QuestLog, "IsComplete") and C_QuestLog.IsComplete(id))
        or (has(C_QuestLog, "ReadyForTurnIn") and C_QuestLog.ReadyForTurnIn(id)) or false
      local objectives = {}
      if has(C_QuestLog, "GetQuestObjectives") then
        for _, o in ipairs(C_QuestLog.GetQuestObjectives(id) or {}) do
          objectives[#objectives + 1] = { text = o.text, finished = o.finished, type = o.type,
            have = o.numFulfilled, need = o.numRequired }
        end
      end
      out[id] = { title = info.title, level = info.level, complete = complete and true or false,
        objectives = objectives }
    end
  end
  return out
end

function G.Skills()
  if not GetProfessions or not GetProfessionInfo then return nil end
  local out = {}
  local slots = { GetProfessions() }
  for i = 1, 7 do
    local idx = slots[i]
    if idx then
      local _, _, rank, _, _, _, skillLine = GetProfessionInfo(idx)
      if skillLine then out[skillLine] = rank or 0 end
    end
  end
  return out
end

-- Current uiMap and position on it (percent), or nil.
-- The player's spot { map, x, y } (map percent), or nil. Pass `out` to have it
-- filled instead of a new table (the arrow and the minimap ask many times a second).
function G.Position(out)
  if not has(C_Map, "GetBestMapForUnit") or not has(C_Map, "GetPlayerMapPosition") then return nil end
  local map = C_Map.GetBestMapForUnit("player")
  if not map then return nil end
  local v = C_Map.GetPlayerMapPosition(map, "player")
  if not v then return nil end
  local x, y
  if v.GetXY then x, y = v:GetXY() else x, y = v.x, v.y end
  if not x or not y or (x == 0 and y == 0) then return nil end
  out = out or {}
  out.map, out.x, out.y = map, x * 100, y * 100
  return out
end

function G.Character()
  -- (not `UnitRace and UnitRace(...)`: `and` keeps only the first return value)
  local race, class
  if UnitRace then race = select(3, UnitRace("player")) end
  if UnitClass then class = select(3, UnitClass("player")) end
  local faction = UnitFactionGroup and UnitFactionGroup("player")
  return {
    level = (UnitLevel and UnitLevel("player")) or 1,
    xp = UnitXP and UnitXP("player") or 0,
    xpMax = UnitXPMax and UnitXPMax("player") or nil,
    faction = faction, race = race, class = class,
    completed = G.Completed(), active = G.QuestLog(), skills = G.Skills(),
    pos = G.Position(),
  }
end

-- Run speed in yards per second: the fastest seen on the ground (mounted counts),
-- 7 until you have moved. Flights and boats are not ground speed.
local runSpeed = 7
function G.RunSpeed()
  if GetUnitSpeed and not (UnitOnTaxi and UnitOnTaxi("player")) then
    local sp = GetUnitSpeed("player") or 0
    if sp > runSpeed and sp <= 20 then runSpeed = sp end
  end
  return runSpeed
end

-- geo resolver for the engine (Engine/Geo.lua): world yards via the client
local worldCache = {}
G.geo = {
  world = function(map, x, y)
    if not has(C_Map, "GetWorldPosFromMapPos") or not CreateVector2D then return nil end
    local key = map * 1e7 + math.floor(x * 10 + 0.5) * 1000 + math.floor(y * 10 + 0.5)
    local c = worldCache[key]
    if c == nil then
      local cont, pos = C_Map.GetWorldPosFromMapPos(map, CreateVector2D(x / 100, y / 100))
      if cont and pos then
        local wx, wy
        if pos.GetXY then wx, wy = pos:GetXY() else wx, wy = pos.x, pos.y end
        c = { cont, wx, wy }
      else
        c = false
      end
      worldCache[key] = c
    end
    if c then return c[1], c[2], c[3] end
  end,
  size = function(map)
    if not has(C_Map, "GetMapWorldSize") then return nil end
    return C_Map.GetMapWorldSize(map)
  end,
}

function G.MapName(map)
  if has(C_Map, "GetMapInfo") then
    local info = C_Map.GetMapInfo(map)
    if info and info.name then return info.name end
  end
  local ds = ns.ActiveDataset()
  return ds and ds.maps[map] or ("map " .. tostring(map))
end

-- Point at a spot: the Lvls! arrow, and the client's own map pin + super-tracked
-- arrow too when the nativeArrow setting is on.
function G.Waypoint(spot, title)
  if not spot then return false end
  if ns.Arrow then ns.Arrow.SetTarget(spot, title, true) end
  if not (ns.db and ns.db.settings.nativeArrow) then return true end
  if not has(C_Map, "SetUserWaypoint") or not UiMapPoint then return false end
  if has(C_Map, "CanSetUserWaypointOnMap") and not C_Map.CanSetUserWaypointOnMap(spot.map) then return false end
  C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(spot.map, spot.x / 100, spot.y / 100))
  if has(C_SuperTrack, "SetSuperTrackedUserWaypoint") then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
  return true
end

-- Bridge game events to one throttled "LVLS_STATE" message.
local STATE_EVENTS = { "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED",
  "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA", "SKILL_LINES_CHANGED", "PLAYER_ENTERING_WORLD" }
if CreateFrame then
  local f = CreateFrame("Frame")
  for _, e in ipairs(STATE_EVENTS) do f:RegisterEvent(e) end
  local pending = false
  f:SetScript("OnEvent", function(_, event)
    if event == "QUEST_TURNED_IN" then G.dirtyCompleted = true end
    if pending then return end
    pending = true
    local fire = function() pending = false; ns.Events.Fire("LVLS_STATE", event) end
    if C_Timer and C_Timer.After then C_Timer.After(0.3, fire) else fire() end
  end)
end

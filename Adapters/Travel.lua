-- Travel facts from the client, and what Lvls! learns while you play. Feeds
-- Engine/Travel (ctx) and the "Get the flight path" lines.
--
-- From the client (forever, Blizzard_APIDocumentation): C_TaxiMap.GetTaxiNodesForMap
-- (every flight point of a map, with isUndiscovered and faction: works anywhere, not
-- only at a flight master), C_Map.GetMapInfo / GetMapInfoAtPosition (map types:
-- 2 continent, 3 zone, 4 dungeon, 5 micro = caves, mines, buildings with their own
-- map), GetBindLocation, C_Container.GetItemCooldown, UnitOnTaxi.
--
-- Learned and kept in LvlsDB (account wide; the shipped Data/forever/Travel.lua
-- holds the ones we recorded ourselves):
--   flights[from>to]   measured flight seconds between flight points
--   transit            boat / zeppelin links: the last spot before you reached another
--                      continent without a flight, and the first spot after
--   entrances[mapId]   where you walked from the zone into a cave / building map
--   recordings[name]   paths recorded with /lvls record (to author "follow the path")
-- and in LvlsCharDB: hearth = { name, spot } where you set your hearthstone.
local _, ns = ...
local TR = ns:NewModule("TravelData")
local G = ns.Geo

local HEARTHSTONE = 6948
local HEARTH_SPELL = 8690
local FACTION = { Alliance = 2, Horde = 1 } -- Enum.FlightPathFaction; 0 neutral
local CONTINENT, ZONE, DUNGEON, MICRO = 2, 3, 4, 5

local function has(t, k) return type(t) == "table" and type(t[k]) == "function" end

local mapInfoCache = {}
function TR.MapInfo(map)
  if not map then return nil end
  local c = mapInfoCache[map]
  if c == nil then
    c = has(C_Map, "GetMapInfo") and C_Map.GetMapInfo(map) or false
    mapInfoCache[map] = c
  end
  return c or nil
end

function TR.Continent(map)
  local guard = 0
  local info = TR.MapInfo(map)
  while info and info.mapType ~= CONTINENT and info.parentMapID and info.parentMapID > 0 and guard < 10 do
    info = TR.MapInfo(info.parentMapID)
    guard = guard + 1
  end
  return info and info.mapType == CONTINENT and info.mapID or nil
end

local function db() return ns.db or {} end

-- npc spots of a dataset travel kind
local function travelNpcs(ds, kind)
  local out = {}
  for _, id in ipairs((ds and ds.travel and ds.travel[kind]) or {}) do
    local rec = ds.npcs[id]
    for _, s in ipairs(G.Spots(ds, "n", id)) do
      s.kind, s.id, s.name = "n", id, rec and rec.n
      out[#out + 1] = s
    end
  end
  return out
end

-- Flight points of the continent you are on: discovered ones (for travel) and
-- undiscovered ones of your faction (to pick up on the way). Each gets the flight
-- master standing there, from the dataset.
local flyCache = {}
function TR.FlyNodes(ds, map, faction)
  local cont = TR.Continent(map)
  if not cont or not has(C_TaxiMap, "GetTaxiNodesForMap") then return {}, {} end
  local key = cont .. ":" .. tostring(faction)
  if flyCache[key] then return flyCache[key][1], flyCache[key][2] end
  local known, unknown = {}, {}
  local masters = travelNpcs(ds, "fly")
  for _, n in ipairs(C_TaxiMap.GetTaxiNodesForMap(cont) or {}) do
    local fac = n.faction or 0
    if fac == 0 or fac == FACTION[faction] then
      local x, y = n.position.x, n.position.y
      if n.position.GetXY then x, y = n.position:GetXY() end
      local spot = { map = cont, x = x * 100, y = y * 100 }
      local npc, d = G.Nearest(ns.Game.geo, spot, masters)
      local f = { id = n.nodeID, name = (n.name or "?"):gsub(",.*$", ""), spot = spot }
      if npc and d <= 50 then -- the flight master stands at the flight point
        f.npc = { kind = "n", id = npc.id, name = npc.name }
        f.spot = { map = npc.map, x = npc.x, y = npc.y }
      end
      if n.isUndiscovered then unknown[#unknown + 1] = f else known[#known + 1] = f end
    end
  end
  flyCache[key] = { known, unknown }
  return known, unknown
end

function TR.Forget() flyCache = {} end

function TR.FlyTime(a, b)
  local f = db().flights
  return f and f[a .. ">" .. b]
end

function TR.Hearth()
  local h = ns.cdb and ns.cdb.hearth
  if not h or not h.spot then return nil end
  if C_Item and C_Item.GetItemCount and C_Item.GetItemCount(HEARTHSTONE) == 0 then return nil end
  if has(C_Container, "GetItemCooldown") then
    local start, dur = C_Container.GetItemCooldown(HEARTHSTONE)
    if start and start > 0 and dur and dur > 2 then return nil end
  end
  return { spot = h.spot, name = (GetBindLocation and GetBindLocation()) or h.name }
end

-- shipped (Data/forever/Travel.lua) + learned
function TR.Transit()
  local out = {}
  for _, l in ipairs((ns.TravelShipped and ns.TravelShipped.transit) or {}) do out[#out + 1] = l end
  for _, l in ipairs(db().transit or {}) do out[#out + 1] = l end
  return out
end

-- The cave / building map a spot lies in, and its known way in.
local entranceCache = {}
function TR.Entrance(spot)
  if not spot or not has(C_Map, "GetMapInfoAtPosition") then return nil end
  local own = TR.MapInfo(spot.map)
  if own and (own.mapType == MICRO or own.mapType == DUNGEON) then
    return { name = own.name, inside = true } -- the spot is already on the cave's own map
  end
  local key = spot.map * 1e7 + G.Pack(spot.x, spot.y)
  local c = entranceCache[key]
  if c == nil then
    local info = C_Map.GetMapInfoAtPosition(spot.map, spot.x / 100, spot.y / 100)
    c = false
    if info and info.mapID ~= spot.map and (info.mapType == MICRO or info.mapType == DUNGEON) then
      local e = (db().entrances or {})[info.mapID]
        or (ns.TravelShipped and ns.TravelShipped.entrances and ns.TravelShipped.entrances[info.mapID])
      if e then c = { name = info.name, spot = { map = e.map, x = e.x, y = e.y }, mapID = info.mapID } end
    end
    entranceCache[key] = c
  end
  return c or nil
end

-- Recorded paths that end near `to` ("Run up the hill", "Follow the path inside").
function TR.PathTo(to)
  local best, bestD
  for _, p in ipairs((ns.TravelShipped and ns.TravelShipped.paths) or {}) do
    local last = p.points[#p.points]
    local d = G.Distance(ns.Game.geo, last, to)
    if d <= (p.radius or 60) and (not bestD or d < bestD) then best, bestD = p, d end
  end
  return best
end

function TR.Context(ds, char)
  local pos = char.pos
  local known = pos and TR.FlyNodes(ds, pos.map, char.faction) or {}
  return {
    geo = ns.Game.geo, speed = ns.Game.RunSpeed and ns.Game.RunSpeed() or 7,
    fly = known, flyTime = TR.FlyTime, transit = TR.Transit(), hearth = TR.Hearth(),
    entrance = TR.Entrance, path = TR.PathTo,
  }
end

-- learning ---------------------------------------------------------------------------

local last = {}   -- last outdoor sample: { spot, cont, t, mapType }
local flight      -- { from = nodeId, t }
local hearthCast  -- time of the last hearthstone cast

local function now() return GetTime and GetTime() or os.time() end

local function nearestKnown(ds, spot)
  local known = TR.FlyNodes(ds, spot.map, UnitFactionGroup and UnitFactionGroup("player"))
  local best, bestD
  for _, f in ipairs(known) do
    local d = G.Distance(ns.Game.geo, spot, f.spot)
    if d <= 120 and (not bestD or d < bestD) then best, bestD = f, d end
  end
  return best
end

local function learnTransit(a, b, secs)
  local d = ns.db
  if not d then return end
  d.transit = d.transit or {}
  local function near(p, q) return G.Distance(ns.Game.geo, p, q) < 80 end
  for _, l in ipairs(d.transit) do
    if (near(l.a, a) and near(l.b, b)) or (near(l.a, b) and near(l.b, a)) then return end -- both ways
  end
  local ds = ns.ActiveDataset()
  local zep = ds and G.Nearest(ns.Game.geo, a, travelNpcs(ds, "zeppelin"))
  local zepD = zep and G.Distance(ns.Game.geo, a, zep) or math.huge
  local what = zepD <= 60 and "zeppelin" or "boat"
  local nameB = (TR.MapInfo(b.map) or {}).name or "the other side"
  local nameA = (TR.MapInfo(a.map) or {}).name or "back"
  table.insert(d.transit, { a = a, b = b, secs = math.floor(secs + 0.5),
    title_ab = ("Take the %s to %s"):format(what, nameB), title_ba = ("Take the %s to %s"):format(what, nameA) })
  ns.Log("info", ("learned a %s link to %s"):format(what, nameB))
end

-- Called about once a second.
function TR.Sample()
  local pos = ns.Game.Position()
  local t = now()
  local ds = ns.ActiveDataset()
  local onTaxi = UnitOnTaxi and UnitOnTaxi("player")
  -- flights: from the flight point you took off at to the one you land at
  if onTaxi and not flight and last.spot and ds then
    local f = nearestKnown(ds, last.spot)
    flight = { from = f and f.id, t = t }
  elseif not onTaxi and flight and pos and ds then
    local f = nearestKnown(ds, pos)
    if flight.from and f and f.id ~= flight.from and ns.db then
      ns.db.flights = ns.db.flights or {}
      ns.db.flights[flight.from .. ">" .. f.id] = math.floor(t - flight.t + 0.5)
    end
    flight = nil
  end
  if not pos then return end
  local info = TR.MapInfo(pos.map)
  local mapType = info and info.mapType
  local cont = ns.Game.geo.world(pos.map, pos.x, pos.y)
  -- entrances: from a zone straight into one of its caves / buildings
  if last.spot and last.mapType == ZONE and (mapType == MICRO or mapType == DUNGEON) and info.parentMapID == last.spot.map
    and ns.db then
    ns.db.entrances = ns.db.entrances or {}
    if not ns.db.entrances[pos.map] then
      ns.db.entrances[pos.map] = { map = last.spot.map, x = last.spot.x, y = last.spot.y }
      entranceCache = {}
      ns.Log("info", "learned the way into " .. (info.name or "this place"))
    end
  end
  -- transit: another continent without a flight, hearthstone or death in between
  if last.spot and last.cont and cont and cont ~= last.cont and not onTaxi and last.mapType == ZONE
    and mapType == ZONE and not (hearthCast and t - hearthCast < 60)
    and not (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) and t - last.t < 600 then
    learnTransit(last.spot, pos, t - last.t)
  end
  -- recorder
  local rec = TR.recording
  if rec then
    local lp = rec.points[#rec.points]
    if not lp or G.Distance(ns.Game.geo, lp, pos) >= 8 then
      rec.points[#rec.points + 1] = { map = pos.map, x = math.floor(pos.x * 10 + 0.5) / 10, y = math.floor(pos.y * 10 + 0.5) / 10 }
    end
  end
  if not onTaxi then last = { spot = pos, cont = cont, t = t, mapType = mapType } end
end

function TR.OnEvent(event, unit, _, spell)
  if event == "HEARTHSTONE_BOUND" then
    local pos = ns.Game.Position()
    if pos and ns.cdb then ns.cdb.hearth = { name = GetBindLocation and GetBindLocation(), spot = pos } end
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" and unit == "player" and spell == HEARTH_SPELL then
    hearthCast = now()
  elseif event == "TAXIMAP_CLOSED" or event == "TAXI_NODE_STATUS_CHANGED" then
    TR.Forget()
  end
end

-- /lvls record <title> ... /lvls record stop
function TR.Record(arg)
  arg = arg or ""
  if arg == "stop" or (arg == "" and TR.recording) then
    local r = TR.recording
    TR.recording = nil
    if r and ns.db then
      ns.db.recordings = ns.db.recordings or {}
      table.insert(ns.db.recordings, r)
      ns.Log("info", ("recorded %d points: %s"):format(#r.points, r.title))
    end
    return
  end
  TR.recording = { title = arg ~= "" and arg or "Follow the path", points = {} }
  ns.Log("info", "recording; walk the path, then /lvls record stop")
end

if CreateFrame then
  local f = CreateFrame("Frame")
  for _, e in ipairs({ "HEARTHSTONE_BOUND", "UNIT_SPELLCAST_SUCCEEDED", "TAXIMAP_CLOSED", "TAXI_NODE_STATUS_CHANGED" }) do
    f:RegisterEvent(e)
  end
  f:SetScript("OnEvent", function(_, ...) TR.OnEvent(...) end)
  local acc = 0
  f:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + (elapsed or 0)
    if acc >= 1 and ns.db then acc = 0; TR.Sample() end
  end)
end

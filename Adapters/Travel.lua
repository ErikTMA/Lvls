-- Travel facts from the client, and what Lvls! learns while you play. Feeds
-- Engine/Travel (ctx) and the "Get the flight path" lines.
--
-- From the client (forever, Blizzard_APIDocumentation): C_TaxiMap.GetTaxiNodesForMap
-- (every flight point of a map, with isUndiscovered and faction: works anywhere, not
-- only at a flight master), C_Map.GetMapInfo / GetMapInfoAtPosition (map types:
-- 2 continent, 3 zone, 4 dungeon, 5 micro = caves, mines, buildings with their own
-- map), GetBindLocation, C_Container.GetItemCooldown, C_Spell.GetSpellCooldown
-- (start and duration; secret while cooldowns are restricted), UnitOnTaxi.
--
-- Learned and kept in LvlsDB (account wide; the shipped Data/forever/Travel.lua
-- holds the ones we recorded ourselves):
--   flights[from>to]   measured flight seconds between flight points
--   transit            boat / zeppelin links: the last spot before you reached another
--                      continent without a flight, and the first spot after
--   entrances[mapId]   where you walked from the zone into a cave / building map
--   recordings[name]   paths recorded with /lvls record (to author "follow the path")
--   ports[spellId]     where a teleport landed you (the first spot on its map after the cast)
--   cooldowns[spellId] a port's full cooldown, as the client reported it right after a use
-- and in LvlsCharDB: hearth = { name, spot } where you set your hearthstone.
local _, ns = ...
local TR = ns:NewModule("TravelData")
local G = ns.Geo

local HEARTHSTONE = 6948
local HEARTH_SPELL = 8690
local RUNE = 17031 -- Rune of Teleportation
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

-- Flight points of the continent you are on, of your faction: the ones you have (for
-- travel), the ones you lack (to pick up on the way), and the ones nobody confirmed
-- either way. Each gets the flight master standing there, from the dataset.
-- Only a confirmed point is flown to: the client's isUndiscovered calls points
-- discovered that you never got (Darkshire at level 28, Refuge Pointe at 30), so
-- it counts only when it says you lack one. A point is confirmed yours by a flight
-- master's map (TR.LearnTaxi) or by taking off or landing there (TR.Sample).
local flyCache = {}
function TR.FlyNodes(ds, map, faction)
  local cont = TR.Continent(map)
  if not cont or not has(C_TaxiMap, "GetTaxiNodesForMap") then return {}, {}, {} end
  local key = cont .. ":" .. tostring(faction)
  if flyCache[key] then return flyCache[key][1], flyCache[key][2], flyCache[key][3] end
  local known, unknown, unsure, all = {}, {}, {}, {}
  local masters = travelNpcs(ds, "fly")
  local byNpc = {} -- [flight master id] = the points standing at it
  for _, n in ipairs(C_TaxiMap.GetTaxiNodesForMap(cont) or {}) do
    local fac = n.faction or 0
    -- "zz" in front of a name: a record the game retired ("zzOLDRiverglades" at the
    -- Southshore flight master), listed still but on no flight master's map
    if (fac == 0 or fac == FACTION[faction]) and not tostring(n.name or ""):find("^zz") then
      local x, y = n.position.x, n.position.y
      if n.position.GetXY then x, y = n.position:GetXY() end
      local spot = { map = cont, x = x * 100, y = y * 100 }
      local npc, d = G.Nearest(ns.Game.geo, spot, masters)
      local f = { id = n.nodeID, name = (n.name or "?"):gsub(",.*$", ""), spot = spot }
      if npc and d <= 50 then -- the flight master stands at the flight point
        f.npc = { kind = "n", id = npc.id, name = npc.name }
        f.spot = { map = npc.map, x = npc.x, y = npc.y }
      end
      local seen = TR.Seen(f.name)
      f.state = seen == true and "known" or (seen == false or n.isUndiscovered) and "unknown" or "unsure"
      if f.npc then
        byNpc[f.npc.id] = byNpc[f.npc.id] or {}
        table.insert(byNpc[f.npc.id], f)
      end
      all[#all + 1] = f
    end
  end
  -- one flight master is one flight point: of several points at one, the one you
  -- have stands for it (the others are leftovers you can never get), else the first
  local drop = {}
  for _, group in pairs(byNpc) do
    if #group > 1 then
      local keep = group[1]
      for _, f in ipairs(group) do if f.state == "known" then keep = f break end end
      for _, f in ipairs(group) do if f ~= keep then drop[f] = true end end
    end
  end
  local lists = { known = known, unknown = unknown, unsure = unsure }
  for _, f in ipairs(all) do
    if not drop[f] then table.insert(lists[f.state], f) end
  end
  flyCache[key] = { known, unknown, unsure }
  return known, unknown, unsure
end

function TR.Forget() flyCache = {} end

-- The flight points a flight master's map showed you know (true) or not (false),
-- by name without the zone suffix; kept per character in LvlsCharDB.taxi. nil:
-- never seen at a flight master.
local function short(name) return (tostring(name or ""):gsub(",.*$", "")) end
function TR.Seen(name)
  local t = ns.cdb and ns.cdb.taxi
  if t then return t[short(name)] end
end

-- A flight master's map is open: learn which points you know. Only CURRENT and
-- REACHABLE are yours: TaxiNodeGetType says "NONE" or "DISTANT" for the others, and
-- C_TaxiMap.GetAllTaxiNodes state Unreachable (2), the points the client's own
-- flight map hides (Blizzard_FlightMap, forever: Refuge Pointe at level 30 was
-- "DISTANT" and taken for yours). Returns true when something changed.
local UNREACHABLE = 2 -- Enum.FlightPathState
function TR.LearnTaxi()
  if not ns.cdb then return false end
  local found = {}
  local map = has(C_TaxiMap, "GetAllTaxiNodes") and type(GetTaxiMapID) == "function" and GetTaxiMapID()
  local nodes = map and C_TaxiMap.GetAllTaxiNodes(map) or {}
  local n = type(NumTaxiNodes) == "function" and NumTaxiNodes() or 0
  if #nodes > 0 then
    for _, node in ipairs(nodes) do
      if node.name then found[short(node.name)] = node.state ~= UNREACHABLE end
    end
  elseif n > 0 and type(TaxiNodeName) == "function" and type(TaxiNodeGetType) == "function" then
    for i = 1, n do
      local name, kind = TaxiNodeName(i), TaxiNodeGetType(i)
      if name and kind then found[short(name)] = kind == "CURRENT" or kind == "REACHABLE" end
    end
  end
  if next(found) == nil then return false end
  -- the continent's other points of your faction, missing from the map: not yours
  -- yet (the TaxiFrame may leave out the ones you lack instead of calling them NONE)
  local pos = ns.Game.Position and ns.Game.Position()
  local cont = pos and TR.Continent(pos.map)
  local fac = FACTION[UnitFactionGroup and UnitFactionGroup("player") or ""]
  for _, node in ipairs(cont and has(C_TaxiMap, "GetTaxiNodesForMap") and C_TaxiMap.GetTaxiNodesForMap(cont) or {}) do
    local nf = node.faction or 0
    if (nf == 0 or nf == fac) and found[short(node.name)] == nil then found[short(node.name)] = false end
  end
  local t = ns.cdb.taxi or {}
  ns.cdb.taxi = t
  local changed = false
  for name, v in pairs(found) do
    if t[name] ~= v then t[name] = v; changed = true end
  end
  return changed
end

-- You stood at this flight point and flew (took off or landed): it is yours.
function TR.Confirm(f)
  if not (f and ns.cdb) then return end
  ns.cdb.taxi = ns.cdb.taxi or {}
  local name = short(f.name)
  if ns.cdb.taxi[name] ~= true then
    ns.cdb.taxi[name] = true
    TR.Forget()
    return true
  end
end

function TR.FlyTime(a, b)
  local f = db().flights
  return f and f[a .. ">" .. b]
end

-- Ports: ways to port yourself. To your hearth (the bind spot) or to a fixed map.
-- id is the spell the client casts (UNIT_SPELLCAST_SUCCEEDED). cd: the full cooldown
-- when the client has not told us (learned after a use; GetSpellBaseCooldown when
-- the client has it). Where a teleport lands is learned on the first use; until
-- then the middle of its map stands in (guess = true).
TR.PORTS = {
  { id = HEARTH_SPELL, item = HEARTHSTONE, bind = true, title = "Hearth to %s", cd = 3600 },
  { id = 556, bind = true, title = "Astral Recall to %s", cd = 900 },          -- shaman
  { id = 18960, map = 1450, title = "Teleport to Moonglade", cd = 0 },          -- druid
  { id = 3561, map = 1453, title = "Teleport to Stormwind", reagent = RUNE, cd = 0 }, -- mage
  { id = 3562, map = 1455, title = "Teleport to Ironforge", reagent = RUNE, cd = 0 },
  { id = 3565, map = 1457, title = "Teleport to Darnassus", reagent = RUNE, cd = 0 },
  { id = 3567, map = 1454, title = "Teleport to Orgrimmar", reagent = RUNE, cd = 0 },
  { id = 3563, map = 1458, title = "Teleport to Undercity", reagent = RUNE, cd = 0 },
  { id = 3566, map = 1456, title = "Teleport to Thunder Bluff", reagent = RUNE, cd = 0 },
}
local portById = {}
for _, p in ipairs(TR.PORTS) do portById[p.id] = p end
TR.PortById = portById

local plain = function(v) return ns.Util.plain(v) end

local function itemCount(item)
  if C_Item and C_Item.GetItemCount then return plain(C_Item.GetItemCount(item)) or 0 end
  return 0
end

local function knows(spell)
  if has(C_SpellBook, "IsSpellKnown") then return C_SpellBook.IsSpellKnown(spell) and true or false end
  if type(IsSpellKnown) == "function" then return IsSpellKnown(spell) and true or false end
  if type(IsPlayerSpell) == "function" then return IsPlayerSpell(spell) and true or false end
  return false
end

-- start, duration of a port's cooldown as the client says (0, 0: none), or nil when
-- it does not say (secret: the last ones read stand)
local lastCd = {}
local function readCooldown(p)
  local start, dur
  if p.item and has(C_Container, "GetItemCooldown") then
    start, dur = C_Container.GetItemCooldown(p.item)
  elseif p.item and has(C_Item, "GetItemCooldown") then
    start, dur = C_Item.GetItemCooldown(p.item)
  elseif has(C_Spell, "GetSpellCooldown") then
    local info = C_Spell.GetSpellCooldown(p.id)
    if type(info) == "table" then start, dur = info.startTime, info.duration end
  elseif type(GetSpellCooldown) == "function" then
    start, dur = GetSpellCooldown(p.id)
  end
  start, dur = plain(start), plain(dur)
  if type(start) ~= "number" or type(dur) ~= "number" then
    local l = lastCd[p.id]
    if l then return l[1], l[2] end
    return nil
  end
  lastCd[p.id] = { start, dur }
  return start, dur
end

-- A port's cooldown: seconds until it is ready (0: now) and how long it is in full.
-- The full length: what the client reported right after a use (kept), else its
-- base cooldown when the client has GetSpellBaseCooldown, else TR.PORTS' default.
function TR.Cooldown(p)
  local start, dur = readCooldown(p)
  local ready = 0
  local now = GetTime and GetTime() or 0
  if start and dur and start > 0 and dur > 2 then -- 2: not the global cooldown
    ready = math.max(0, start + dur - now)
    local d = ns.db
    if d then
      d.cooldowns = d.cooldowns or {}
      d.cooldowns[p.id] = math.floor(dur + 0.5)
    end
  end
  local full = ns.db and ns.db.cooldowns and ns.db.cooldowns[p.id]
  if not full and type(GetSpellBaseCooldown) == "function" then
    local ms = plain(GetSpellBaseCooldown(p.id))
    if type(ms) == "number" and ms > 2000 then full = ms / 1000 end
  end
  return ready, full or p.cd or 0
end

-- The bind spot: where you set your hearthstone, or nil.
function TR.Hearth()
  local h = ns.cdb and ns.cdb.hearth
  if not h or not h.spot then return nil end
  return { spot = h.spot, name = (GetBindLocation and GetBindLocation()) or h.name }
end

-- The ports you have (Engine/Travel ctx.ports), with their cooldowns now.
function TR.Ports()
  local out = {}
  local bind = TR.Hearth()
  for _, p in ipairs(TR.PORTS) do
    local have
    if p.item then have = itemCount(p.item) > 0 else have = knows(p.id) end
    if have and p.reagent and itemCount(p.reagent) == 0 then have = false end
    local spot, title, guess
    if have and p.bind then
      if bind then spot, title = bind.spot, p.title:format(bind.name or "your inn") end
    elseif have then
      local l = ns.db and ns.db.ports and ns.db.ports[p.id]
      if l then spot = { map = l.map, x = l.x, y = l.y } else spot, guess = { map = p.map, x = 50, y = 50 }, true end
      title = p.title
    end
    if spot then
      local ready, cd = TR.Cooldown(p)
      out[#out + 1] = { id = p.id, title = title, spot = spot, guess = guess, secs = 15, ready = ready, cd = cd,
        reagent = p.reagent and true or nil }
    end
  end
  return out
end

-- from the client's tables (Data/forever/Transports.lua: boats, zeppelins, the tram;
-- a link with a side is for that faction only) + shipped hints (Data/forever/Travel.lua)
-- + learned
local SIDES = { Alliance = "A", Horde = "H" }
function TR.Transit(faction)
  local out, side = {}, SIDES[faction]
  for _, l in ipairs(ns.TravelTransports or {}) do
    if not l.side or not side or l.side == side then out[#out + 1] = l end
  end
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
    fly = known, flyTime = TR.FlyTime, transit = TR.Transit(char.faction), ports = TR.Ports(),
    entrance = TR.Entrance, path = TR.PathTo,
  }
end

-- learning ---------------------------------------------------------------------------

local last = {}   -- last outdoor sample: { spot, cont, t, mapType }
local flight      -- { from = nodeId, t }
local hearthCast  -- time of the last port's cast (hearthstone, teleport)
local portCast    -- { id, t }: a teleport cast, its landing spot not yet seen

local function now() return GetTime and GetTime() or os.time() end

-- The flight point you stand at, of all of the continent's (you take off and land
-- only at ones you have, whatever we thought of them)
local function nearestKnown(ds, spot)
  local best, bestD
  for _, list in ipairs({ TR.FlyNodes(ds, spot.map, UnitFactionGroup and UnitFactionGroup("player")) }) do
    for _, f in ipairs(list) do
      local d = G.Distance(ns.Game.geo, spot, f.spot)
      if d <= 120 and (not bestD or d < bestD) then best, bestD = f, d end
    end
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
    if TR.Confirm(f) and ns.Refresh then ns.Refresh(true) end
  elseif not onTaxi and flight and pos and ds then
    local f = nearestKnown(ds, pos)
    if TR.Confirm(f) and ns.Refresh then ns.Refresh(true) end
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
  -- where a teleport lands: the first spot on its map after the cast
  if portCast then
    local p = portById[portCast.id]
    if not p or t - portCast.t > 60 then
      portCast = nil
    elseif pos.map == p.map and ns.db then
      ns.db.ports = ns.db.ports or {}
      ns.db.ports[p.id] = { map = pos.map, x = math.floor(pos.x * 10 + 0.5) / 10, y = math.floor(pos.y * 10 + 0.5) / 10 }
      portCast = nil
      ns.Log("debug", "learned where " .. p.title:lower() .. " lands")
    end
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
  spell = ns.Util.plain(spell)
  if event == "HEARTHSTONE_BOUND" then
    local pos = ns.Game.Position()
    if pos and ns.cdb then ns.cdb.hearth = { name = GetBindLocation and GetBindLocation(), spot = pos } end
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" and unit == "player" and portById[spell] then
    hearthCast = now() -- no boat link learned from it
    if portById[spell].map then portCast = { id = spell, t = hearthCast } end
  elseif event == "TAXIMAP_OPENED" then
    TR.Forget()
    if TR.LearnTaxi() and ns.Refresh and ns.db then
      -- plan again now: the trip must not fly to a point you do not have, and the
      -- open map rings the one it flies to instead
      ns.Refresh(true)
      if ns.FlightMap and TaxiFrame and TaxiFrame.IsShown and TaxiFrame:IsShown() then ns.FlightMap.OnTaxiShow() end
    end
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
  for _, e in ipairs({ "HEARTHSTONE_BOUND", "UNIT_SPELLCAST_SUCCEEDED", "TAXIMAP_OPENED", "TAXIMAP_CLOSED", "TAXI_NODE_STATUS_CHANGED" }) do
    f:RegisterEvent(e)
  end
  f:SetScript("OnEvent", function(_, ...) TR.OnEvent(...) end)
  local acc = 0
  f:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + (elapsed or 0)
    if acc >= 1 and ns.db then acc = 0; TR.Sample() end
  end)
end

-- Zone guides: pick a zone, quest there. The leveling route as always, but only
-- with the quests of that zone: the ones given there, and the ones in your log
-- that are worked or handed in there. Pure.
--
-- A quest belongs to the zones its givers stand in (a zone's map, not a
-- continent's), else to the zone it is filed under. Only quests the route would
-- plan anyway count: no dungeon, raid, battleground, world event or repeatable
-- ones, nothing for another faction, race or class.
-- A zone's levels are those of its quests for this character without strays more
-- than STRAY levels from the middle one (as dungeons): a zone's one level-40
-- errand does not make it a 14-40 zone.
-- The list puts the zones that suit you best first: the most experience in quests
-- you can take now (not grey, at most `above` levels over you) and in your log.
local _, ns = ...
local Z = ns:NewModule("Zones")
local A = ns.Availability

Z.STRAY = 10 -- levels from a zone's middle quest level beyond which a quest is a stray
Z.ABOVE = 3 -- levels over you a quest still counts as one for you now (the route's maxAbove)
local EVENT_SORT = 9 -- world events (Engine/Route R.EVENT_SORT)

local function routed(q)
  return (q.sn or q.so) and not q.rep and not q.inst and q.kind ~= "dungeon" and q.kind ~= "raid"
    and q.kind ~= "pvp" and q.sort ~= EVENT_SORT
end

-- The zone maps a quest is given in: its givers' zone maps, else the map of the
-- zone it is filed under.
function Z.MapsOf(ds, q)
  local out, seen = {}, {}
  for _, s in ipairs(ns.Quests.SharedGivers(ds, q)) do
    if ds.areaOfMap and ds.areaOfMap[s.map] and not seen[s.map] then
      seen[s.map] = true
      out[#out + 1] = s.map
    end
  end
  if #out == 0 then
    local m = q.zone and ds.zones and ds.zones[q.zone]
    if m and ds.maps and ds.maps[m] then out[1] = m end
  end
  return out
end

-- Each zone's quests, built once (Engine/GuideCache): { [map] = { ids (sorted),
-- minLevel, maxLevel } }.
local function build(ds, char)
  local by = {}
  for id, q in pairs(ds.quests) do
    if routed(q) and not A.Fixed(q, char) then
      for _, m in ipairs(Z.MapsOf(ds, q)) do
        local z = by[m]
        if not z then z = { ids = {}, levels = {} }; by[m] = z end
        z.ids[#z.ids + 1] = id
        if q.l and q.l > 0 then z.levels[#z.levels + 1] = q.l end
      end
    end
  end
  for _, z in pairs(by) do
    table.sort(z.ids)
    local l, n = z.levels, #z.levels
    if n > 0 then
      table.sort(l)
      local median = l[math.floor((n + 1) / 2)]
      for _, v in ipairs(l) do
        if v >= median - Z.STRAY and v <= median + Z.STRAY then
          z.minLevel = math.min(z.minLevel or v, v)
          z.maxLevel = math.max(z.maxLevel or v, v)
        end
      end
    end
    z.levels = nil
  end
  return by
end
local function index(ds, char) return ns.GuideCache.Get(ds, char, "zones", build) end

local function readyFor(q, char, above)
  return A.Status(q, char) == "available" and (not q.l or q.l <= (char.level or 1) + above)
end

-- A quest in the log that is worked or handed in on this map.
local function logHere(ds, q, map)
  if #ns.Quests.TurnIns(ds, q, map) > 0 then return true end
  for i in ipairs(q.obj or {}) do
    if #ns.Quests.ObjectiveSpots(ds, q, i, map) > 0 then return true end
  end
  return false
end

-- The zone guide's quests: { set = { [questId] = true }, map, name }. Every quest
-- given in the zone (follow-ups too, the route takes them once they open) and the
-- quests in your log worked or handed in there.
-- given: only the quests given there (the menu, for every zone at once).
function Z.Set(ds, char, map, given)
  local set = {}
  local z = index(ds, char)[map]
  for _, id in ipairs(z and z.ids or {}) do set[id] = true end
  for qid in pairs(not given and char.active or {}) do
    local q = ds.quests[qid]
    if q and not set[qid] and logHere(ds, q, map) then set[qid] = true end
  end
  return { set = set, map = map, name = ds.maps and ds.maps[map] or ("Map " .. map) }
end

-- What is left for you in a zone: quests you can take now (`ready`, by level) and
-- quests of the zone in your log (`active`), with their experience at your level.
function Z.Left(ds, char, map, above, given)
  above = above or Z.ABOVE
  local g = Z.Set(ds, char, map, given)
  local ready, active, xp, open = {}, {}, 0, 0
  local level = char.level or 1
  for id in pairs(g.set) do
    local q = ds.quests[id]
    if char.active and char.active[id] then
      active[#active + 1] = id
      xp = xp + ns.Route.QuestXP(q, level)
    elseif not char.completed[id] then
      open = open + 1
      if readyFor(q, char, above) then
        ready[#ready + 1] = id
        xp = xp + ns.Route.QuestXP(q, level)
      end
    end
  end
  local function byLevel(a, b)
    local la, lb = ds.quests[a].l or 0, ds.quests[b].l or 0
    if la ~= lb then return la < lb end
    return a < b
  end
  table.sort(ready, byLevel)
  table.sort(active, byLevel)
  return { ready = ready, active = active, xp = xp, open = open }
end

-- A zone guide is done when the zone has nothing left for you now.
function Z.Done(ds, char, map, above)
  local l = Z.Left(ds, char, map, above)
  return #l.ready == 0 and #l.active == 0
end

-- Zones with quests for this character: { map, name, minLevel, maxLevel, ready,
-- active, open, xp }, the best for you first (most experience to be had now), then
-- by level. A zone with nothing left to do at all is left out.
function Z.List(ds, char, above)
  local out = {}
  for map, z in pairs(index(ds, char)) do
    local l = Z.Left(ds, char, map, above, true)
    if l.open > 0 or #l.active > 0 then
      out[#out + 1] = { map = map, name = ds.maps and ds.maps[map] or ("Map " .. map), minLevel = z.minLevel,
        maxLevel = z.maxLevel, ready = #l.ready, active = #l.active, open = l.open, xp = l.xp }
    end
  end
  table.sort(out, function(a, b)
    if a.xp ~= b.xp then return a.xp > b.xp end
    if (a.minLevel or 0) ~= (b.minLevel or 0) then return (a.minLevel or 0) < (b.minLevel or 0) end
    return a.name < b.name
  end)
  return out
end

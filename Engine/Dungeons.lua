-- Dungeon guides: pick a dungeon, get every quest for it and every quest that
-- leads to those (prerequisites, series, breadcrumbs), planned as one route that
-- ends at the dungeon's entrance. Pure; names and entrances come in through `env`.
--
-- A dungeon is an instance area (AreaTable id) that quests are filed under
-- (q.zone with q.inst; raids and battlegrounds are not dungeons here).
-- The set: the dungeon's quests this character can still do, then, walking back
-- from each, what has to be done first:
--   provider prerequisites (QuestieDB): all of `group`; of `single` (any one of)
--     nothing when one is done, else the lowest-level one this character can do;
--   without provider data the series predecessor (q.prev);
--   breadcrumbs: quests whose provider breadcrumbFor names a quest in the set
--     (they lead to its giver; optional, so only ones this character can do).
local _, ns = ...
local D = ns:NewModule("Dungeons")
local A, P = ns.Availability, ns.Prereqs

local function isDungeonQuest(q)
  return q.inst and q.zone and q.kind ~= "raid" and q.kind ~= "pvp"
end

local function usable(q, char)
  local s = A.Status(q, char)
  return s ~= "wrong" and s ~= "done"
end

-- Each dungeon's quests, built once (Engine/GuideCache): { [area] = { ids = every
-- quest filed under it, sorted; minLevel, maxLevel of the ones for this character
-- at all (Availability.Fixed), without strays far below the typical level (a level
-- 1 quest filed under Blackrock Depths) } }.
local function areas(ds, char)
  local by = {}
  for id, q in pairs(ds.quests) do
    if isDungeonQuest(q) then
      local d = by[q.zone]
      if not d then d = { ids = {}, levels = {} }; by[q.zone] = d end
      d.ids[#d.ids + 1] = id
      if q.l and q.l > 0 and not A.Fixed(q, char) then d.levels[#d.levels + 1] = q.l end
    end
  end
  for _, d in pairs(by) do
    table.sort(d.ids)
    if #d.levels > 0 then
      table.sort(d.levels)
      local median = d.levels[math.floor((#d.levels + 1) / 2)]
      for _, l in ipairs(d.levels) do
        if l >= median - 10 then
          d.minLevel = math.min(d.minLevel or l, l)
          d.maxLevel = math.max(d.maxLevel or l, l)
        end
      end
    end
    d.levels = nil
  end
  return by
end

local function areaIndex(ds, char) return ns.GuideCache.Get(ds, char, "dungeons", areas) end

-- Dungeons with quests for this character: { area, quests, open, minLevel,
-- maxLevel } sorted by level; env.name(area) names them (nil: "Dungeon <area>").
function D.List(ds, char, env)
  local out = {}
  for area, a in pairs(areaIndex(ds, char)) do
    local d = { area = area, quests = 0, open = 0, minLevel = a.minLevel, maxLevel = a.maxLevel }
    for _, id in ipairs(a.ids) do
      if A.Status(ds.quests[id], char) ~= "wrong" then
        d.quests = d.quests + 1
        if not char.completed[id] then d.open = d.open + 1 end
      end
    end
    if d.quests > 0 then
      d.name = env and env.name and env.name(area) or ("Dungeon " .. area)
      out[#out + 1] = d
    end
  end
  table.sort(out, function(a, b)
    if (a.minLevel or 0) ~= (b.minLevel or 0) then return (a.minLevel or 0) < (b.minLevel or 0) end
    return a.area < b.area
  end)
  return out
end

-- breadcrumb index: target quest -> quests that lead to it (provider data), cached
local function buildCrumbs(ds)
  local by = {}
  for id in pairs(ds.quests) do
    local info = P.Info(id)
    local t = info and info.breadcrumbFor
    if t then
      by[t] = by[t] or {}
      table.insert(by[t], id)
    end
  end
  for _, list in pairs(by) do table.sort(list) end
  return by
end

function D.Breadcrumbs(ds, char) return ns.GuideCache.Get(ds, char, "crumbs", buildCrumbs) end

-- A guide's quests from its main quests (roots): { set = { [id] = true }, roots =
-- the open main quests, order = { ids, prerequisites first } }. Shared by the
-- dungeon and the class quest guides.
function D.Closure(ds, char, ids)
  local set, order, roots, seen = {}, {}, {}, {}
  local crumbs = D.Breadcrumbs(ds, char)
  local function add(id, depth)
    if seen[id] or depth > 30 then return end
    seen[id] = true
    local q = ds.quests[id]
    if not q or char.completed[id] or not usable(q, char) then return end
    local info = P.Info(id)
    if info then
      for _, p in ipairs(info.group or {}) do add(p, depth + 1) end
      local single = info.single or {}
      local any = false
      for _, p in ipairs(single) do if char.completed[p] then any = true end end
      if not any and #single > 0 then
        local pick
        for _, p in ipairs(single) do
          local pq = ds.quests[p]
          if pq and usable(pq, char) and (not pick or (pq.l or 0) < (ds.quests[pick].l or 0)) then pick = p end
        end
        if pick then add(pick, depth + 1) end
      end
    elseif q.prevAny then
      local any = false
      for _, p in ipairs(q.prevAny) do if char.completed[p] then any = true end end
      if not any then
        for _, p in ipairs(q.prevAny) do
          local pq = ds.quests[p]
          if pq and usable(pq, char) then add(p, depth + 1) break end
        end
      end
    elseif q.prev and not q.prevLoop then
      add(q.prev, depth + 1)
    end
    for _, b in ipairs(crumbs[id] or {}) do add(b, depth + 1) end
    set[id] = true
    order[#order + 1] = id
  end
  for _, id in ipairs(ids) do
    local q = ds.quests[id]
    if q and not char.completed[id] and usable(q, char) then roots[#roots + 1] = id end
    add(id, 0)
  end
  return { set = set, roots = roots, order = order }
end

-- The dungeon guide's quests: its quests and what leads to them (D.Closure).
function D.Set(ds, char, area)
  local a = areaIndex(ds, char)[area]
  local g = D.Closure(ds, char, a and a.ids or {})
  g.area = area
  return g
end

-- Is the guide finished? Every quest in the set is done (or became impossible).
function D.Done(ds, char, guide)
  for id in pairs(guide.set) do
    local q = ds.quests[id]
    if q and not char.completed[id] and usable(q, char) then return false end
  end
  return true
end

-- The dungeon step: go in and do the objectives of the guide's dungeon quests.
-- `planned`: quests the route picks up before it. Lines, in order:
--   "Also needed first: X"  quests of the set the route could not place (no
--                           locatable objective, e.g. an escort) and not in the log
--   "Pick up X"             dungeon quests the route does not pick up (they start
--                           inside, or wait for such a quest)
--   the objectives of every dungeon quest, ticking off from the quest log
-- spot: the entrance (nil when unknown).
function D.Step(ds, char, guide, name, entrance, planned)
  planned = planned or {}
  local lines, isRoot = {}, {}
  for _, id in ipairs(guide.roots) do isRoot[id] = true end
  local function open(id) return not char.completed[id] and not (char.active and char.active[id]) and not planned[id] end
  for _, id in ipairs(guide.order) do
    local q = ds.quests[id]
    if q and not isRoot[id] and open(id) then
      lines[#lines + 1] = { kind = "accept", quest = id, text = "Also needed first: " .. q.n, dungeon = true }
    end
  end
  for _, id in ipairs(guide.roots) do
    local q = ds.quests[id]
    if q and open(id) then
      lines[#lines + 1] = { kind = "accept", quest = id, text = "Pick up " .. q.n, dungeon = true }
    end
  end
  for _, id in ipairs(guide.roots) do
    local q = ds.quests[id]
    if q and not char.completed[id] then
      for i, o in ipairs(q.obj or {}) do
        if o.from ~= "provided" then
          lines[#lines + 1] = { kind = ns.Steps.ObjectiveKind(o), quest = id, index = i,
            text = ns.Steps.ObjectiveText(o, ds, id, i), dungeon = true }
        end
      end
    end
  end
  if #lines == 0 then return nil end
  return { kind = "dungeon", title = "Enter " .. (name or "the dungeon"), spot = entrance,
    lines = lines, area = guide.area }
end

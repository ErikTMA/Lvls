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

-- Who an objective comes from, wherever they stand: the dataset's sources (not
-- vendors), else the provider's (it knows who drops what inside a dungeon, though
-- not where), else the kill target itself. { {kind, id}, ... }
local function sources(qid, i, o)
  local out = {}
  for _, s in ipairs(o.src or {}) do
    if s[1] ~= "v" then out[#out + 1] = { s[1], s[2] } end
  end
  local p = P.Provider()
  if #out == 0 and p and p.ObjectiveSources then
    local ok, src = pcall(p.ObjectiveSources, qid, i, o)
    if ok and type(src) == "table" then
      for _, s in ipairs(src) do out[#out + 1] = { s[1], s[2] } end
    end
  end
  if #out == 0 and o.t == "kill" and o.id then out[1] = { "n", o.id } end
  return out
end
D.Sources = sources

local function nameOf(ds, kind, id)
  local rec = (kind == "o" and ds.objects or ds.npcs)[id]
  if rec and rec.n then return rec.n end
  local p = P.Provider()
  if p and p.Name then
    local ok, n = pcall(p.Name, kind, id)
    if ok and type(n) == "string" then return n end
  end
end

-- Does the npc / object ("n" / "o", id) stand in one of `areas` ({ [area] = true })?
-- The provider says (QuestieDB files instance spawns under the dungeon's area).
local function within(kind, id, areas)
  local p = P.Provider()
  if not (p and p.Areas and id) then return false end
  local ok, a = pcall(p.Areas, kind, id)
  if not ok or type(a) ~= "table" then return false end
  for area in pairs(areas) do if a[area] then return true end end
  return false
end
D.Within = within

-- The first npc / object of a giver or ender list (sn/so, en/eo): kind, id
local function first(ns_, os_)
  if ns_ and ns_[1] then return "n", ns_[1] end
  if os_ and os_[1] then return "o", os_[1] end
end

-- Which boss a creature's name is, in `order` ({ [lowercase boss name] = n }): the
-- boss itself, or what the encounter is named after ("Sneed's Shredder": Sneed).
local function bossNamed(n, order)
  n = n:lower()
  if order[n] then return order[n] end
  local owner = n:match("^(.-)'s ")
  return owner and order[owner]
end

-- An objective's place in the boss order: n when a source, or the kill target by
-- name, is one of the bosses; else nil.
local function bossOf(ds, qid, i, o, order)
  if not order then return nil end
  local best
  for _, s in ipairs(sources(qid, i, o)) do
    local n = nameOf(ds, s[1], s[2])
    local at = n and bossNamed(n, order)
    if at and (not best or at < best) then best = at end
  end
  if not best and o.t == "kill" and o.text then
    best = bossNamed((o.text:gsub("%s+[Ss]lain$", "")), order)
  end
  return best
end

-- The dungeon step: go in and do the objectives of the guide's dungeon quests.
-- `planned`: quests the route picks up before it. Lines, in order:
--   "Also needed first: X"  quests of the set the route could not place (no
--                           locatable objective, e.g. an escort) and not in the log
--   "Pick up X from Y"      dungeon quests the route does not pick up (they start
--                           inside, or wait for such a quest)
--   the objectives of every dungeon quest, ticking off from the quest log, with who
--                           drops them; in the order of the dungeon's bosses (those
--                           not at a boss first: they are done on the way), "(boss
--                           3 of 8)" on the ones a boss gives
--   "Turn in X to Y"        quests whose ender stands inside the dungeon
-- spot: the entrance (nil when unknown). opts: { bosses = { name, ... } in the order
-- you meet them, areas = { [area] = true } the dungeon (default guide.area), title }.
function D.Step(ds, char, guide, name, entrance, planned, opts)
  planned, opts = planned or {}, opts or {}
  local areas = opts.areas or (guide.area and { [guide.area] = true }) or {}
  local order
  if opts.bosses and #opts.bosses > 0 then
    order = {}
    for k, b in ipairs(opts.bosses) do
      if not order[b:lower()] then order[b:lower()] = k end
    end
  end
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
      local kind, who = first(q.sn, q.so)
      local giver = who and nameOf(ds, kind, who)
      lines[#lines + 1] = { kind = "accept", quest = id, dungeon = true,
        text = "Pick up " .. q.n .. (giver and (" from " .. giver) or "") }
    end
  end
  local objectives = {}
  for _, id in ipairs(guide.roots) do
    local q = ds.quests[id]
    if q and not char.completed[id] then
      for i, o in ipairs(q.obj or {}) do
        if o.from ~= "provided" then
          local boss = bossOf(ds, id, i, o, order)
          local text = ns.Steps.ObjectiveText(o, ds, id, i)
          if boss then text = ("%s (boss %d of %d)"):format(text, boss, #opts.bosses) end
          objectives[#objectives + 1] = { kind = ns.Steps.ObjectiveKind(o), quest = id, index = i,
            text = text, dungeon = true, boss = boss, at = #objectives }
        end
      end
    end
  end
  table.sort(objectives, function(a, b)
    if (a.boss or 0) ~= (b.boss or 0) then return (a.boss or 0) < (b.boss or 0) end
    return a.at < b.at
  end)
  for _, l in ipairs(objectives) do
    l.at = nil
    lines[#lines + 1] = l
  end
  for _, id in ipairs(guide.roots) do
    local q = ds.quests[id]
    local kind, who = first(q and q.en, q and q.eo)
    if q and not char.completed[id] and who and within(kind, who, areas) then
      local ender = nameOf(ds, kind, who)
      lines[#lines + 1] = { kind = "turnin", quest = id, dungeon = true,
        text = "Turn in " .. q.n .. (ender and (" to " .. ender) or "") }
    end
  end
  if #lines == 0 then return nil end
  return { kind = "dungeon", title = opts.title or ("Enter " .. (name or "the dungeon")), spot = entrance,
    lines = lines, area = guide.area }
end

-- In a dungeon (`areas`: its quest areas, { [area] = true }; `area` the main one):
-- the step for what you can do in there now, with or without a guide. Its quests:
--   in your log and filed under the dungeon;
--   in your log, filed elsewhere, with an objective from someone inside (Red Silk
--     Bandanas, a Westfall quest, drop in The Deadmines);
--   not taken yet, filed under the dungeon, given by someone inside, and yours to
--     take now (available, or grey).
-- nil when there is nothing. opts as D.Step (bosses).
function D.Inside(ds, char, area, areas, name, opts)
  local roots, seen, named = {}, {}, {}
  local function add(id) if not seen[id] then seen[id] = true; roots[#roots + 1] = id end end
  local index = areaIndex(ds, char)
  local offered = {}
  for a in pairs(areas) do
    for _, id in ipairs(index[a] and index[a].ids or {}) do
      local q = ds.quests[id]
      local st = A.Status(q, char)
      if st == "active" then
        add(id)
        named[q.n] = true
      elseif st == "available" or st == "trivial" then
        local kind, who = first(q.sn, q.so)
        if who and within(kind, who, areas) then offered[#offered + 1] = id end
      end
    end
  end
  -- one of a kind: Gnomeregan's three Sparklematic 5200s each give "The Sparklematic
  -- 5200!" under its own id; once one is in the log, none
  table.sort(offered)
  for _, id in ipairs(offered) do
    local n = ds.quests[id].n
    if not named[n] then named[n] = true; add(id) end
  end
  for id, entry in pairs(char.active or {}) do
    local q = ds.quests[id]
    if q and not seen[id] and not entry.simulated and not entry.complete then
      for i, o in ipairs(q.obj or {}) do
        local hit = false
        for _, s in ipairs(sources(id, i, o)) do
          if within(s[1], s[2], areas) then hit = true break end
        end
        if hit then add(id) break end
      end
    end
  end
  if #roots == 0 then return nil end
  table.sort(roots)
  local guide = { roots = roots, order = roots, set = seen, area = area }
  opts = opts or {}
  local st = D.Step(ds, char, guide, name, nil, nil,
    { bosses = opts.bosses, areas = areas, title = name or "In the dungeon" })
  if st then st.inside = true end
  return st
end

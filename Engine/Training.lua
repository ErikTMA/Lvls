-- Training: what your class trainer has waiting for you, and how much it is worth
-- going back for. Pure; the game side is Adapters/Training.lua.
--
-- What it reads (T.Summary's `seen`):
--   list    what a class trainer of yours teaches, read the last time you had one
--           open (kept per character): { { n = name, r = "Rank 4" | "", l = level,
--           c = copper, s = "available" | "unavailable" | "used" }, ... }, at = the
--           level you were then. nil: no trainer seen yet.
--   future  the spellbook's spells you do not have yet: { { n, l }, ... }. Used only
--           without a list (the trainer's list is exact, and the spellbook may also
--           hold spells a quest gives).
--   known   { [spell name] = true }: spells in your spellbook
--   bars    { [spell name] = true }: spells on your action bars
--
-- A spell waits when you reached its level and do not have it (the trainer says
-- "used" once you do). One a trainer called unavailable at a level you already had
-- needs something else (a talent, a skill) and does not count. Each spell counts
-- once however many ranks wait (all of them are paid for):
--   NEW   a spell you do not have at all: an ability, a form, a pet skill
--   USED  a new rank of a spell on your action bars
--   RANK  a new rank of a spell you have but do not use
-- What it is worth: the sum ("value"), and what you can pay for of it ("afford",
-- the best spells first). TRIP or more is worth a trip to a trainer; less than
-- that, but at least PASS, is trained when the route passes one.
local _, ns = ...
local T = ns:NewModule("Training")

T.NEW, T.USED, T.RANK = 3, 2, 0.5
T.TRIP = 6
T.PASS = 1

local function rankOf(r)
  return tonumber(type(r) == "string" and r:match("(%d+)") or nil)
end

-- { count, spells = { { n, rank, l, c, kind, weight }, ... } (best first), value,
--   afford, cost, affordCost, new, used, ranks, source = "trainer" | "spellbook",
--   nextLevel = the level the next spell comes at (nil: none known), worth =
--   "trip" | "pass" | nil } or nil when nothing is known.
function T.Summary(seen, level, money)
  if not seen then return nil end
  level = level or 1
  local known, bars = seen.known or {}, seen.bars or {}
  local by = {} -- spell name -> waiting entry
  local nextLevel
  local function wait(n, r, l, c)
    local e = by[n]
    if not e then
      local kind
      if not known[n] then kind = "new"
      elseif bars[n] then kind = "used"
      else kind = "rank" end
      e = { n = n, kind = kind, weight = kind == "new" and T.NEW or kind == "used" and T.USED or T.RANK,
        rank = rankOf(r), l = l, c = 0, ranks = 0 }
      by[n] = e
    end
    e.c = e.c + (c or 0)
    e.ranks = e.ranks + 1
    local rk = rankOf(r)
    if rk and (not e.rank or rk > e.rank) then e.rank = rk end
    if l and l > (e.l or 0) then e.l = l end
  end
  local source
  if seen.list then
    source = "trainer"
    local at = seen.at or 0
    for _, s in ipairs(seen.list) do
      local l = s.l or 0
      if type(s.n) == "string" and s.s ~= "used" then
        if l > level then
          if not nextLevel or l < nextLevel then nextLevel = l end
        elseif not (s.s == "unavailable" and l <= at) then
          wait(s.n, s.r, l, s.c)
        end
      end
    end
  elseif seen.future then
    source = "spellbook"
    for _, s in ipairs(seen.future) do
      local l = s.l or 0
      if type(s.n) == "string" and l > 0 then
        if l > level then
          if not nextLevel or l < nextLevel then nextLevel = l end
        elseif not known[s.n] then
          wait(s.n, nil, l, nil)
        end
      end
    end
  else
    return nil
  end
  local spells = {}
  for _, e in pairs(by) do spells[#spells + 1] = e end
  table.sort(spells, function(a, b)
    if a.weight ~= b.weight then return a.weight > b.weight end
    if a.l ~= b.l then return a.l > b.l end
    return a.n < b.n
  end)
  local sum = { count = #spells, spells = spells, value = 0, afford = 0, cost = 0, affordCost = 0,
    new = 0, used = 0, ranks = 0, source = source, nextLevel = nextLevel }
  local left = money
  for _, e in ipairs(spells) do
    sum.value = sum.value + e.weight
    sum.cost = sum.cost + e.c
    if e.kind == "new" then sum.new = sum.new + 1 elseif e.kind == "used" then sum.used = sum.used + 1
    else sum.ranks = sum.ranks + 1 end
    -- unknown money (nil): as if you can pay
    if left == nil or e.c <= left then
      sum.afford = sum.afford + e.weight
      sum.affordCost = sum.affordCost + e.c
      if left then left = left - e.c end
    end
  end
  if sum.afford >= T.TRIP then sum.worth = "trip" elseif sum.afford >= T.PASS then sum.worth = "pass" end
  return sum
end

-- "Fireball, Frost Armor +2 more"
function T.Names(sum, max)
  max = max or 2
  local parts = {}
  for i = 1, math.min(#sum.spells, max) do
    local e = sum.spells[i]
    parts[i] = e.n .. ((e.kind ~= "new" and e.rank) and (" " .. e.rank) or "")
  end
  local t = table.concat(parts, ", ")
  if #sum.spells > max then t = t .. (" +%d more"):format(#sum.spells - max) end
  return t
end

-- One line for the viewer and /lvls train, or nil with nothing waiting:
-- "3 spells to train (Fireball 4, Frost Armor +1 more), 1s 20c: worth a trip"
function T.Line(sum, money)
  if not sum or sum.count == 0 then return nil end
  local t = ("%d spell%s to train (%s)"):format(sum.count, sum.count == 1 and "" or "s", T.Names(sum))
  if sum.source == "trainer" and sum.cost > 0 then t = t .. ", " .. ns.Util.money(sum.cost) end
  if sum.afford < sum.value and money then
    t = t .. (sum.afford > 0 and (": you can pay for %s of it"):format(ns.Util.money(sum.affordCost))
      or (": you have %s"):format(ns.Util.money(money)))
  end
  if sum.worth == "trip" then t = t .. ": worth a trip"
  elseif sum.worth == "pass" then t = t .. ": when you pass a trainer" end
  return t
end

-- The line of a train step: "Learn Fireball 4, Frost Armor +1 more"
function T.StepText(sum)
  return "Learn " .. T.Names(sum, 3)
end

-- Class trainers of your class and faction in the dataset (friendly to you, or with
-- no reaction known): { { map, x, y, kind = "n", id, name }, ... }.
function T.Trainers(ds, class, faction)
  local out = {}
  local ids = ds and ds.trainers and class and ds.trainers[class]
  local key = faction == "Alliance" and "ra" or faction == "Horde" and "rh" or nil
  for _, id in ipairs(ids or {}) do
    local rec = ds.npcs[id]
    local r = rec and key and rec[key]
    if rec and (r == 1 or (rec.ra == nil and rec.rh == nil)) then
      for _, s in ipairs(ns.Geo.Spots(ds, "n", id)) do
        s.kind, s.id, s.name = "n", id, rec.n
        out[#out + 1] = s
      end
    end
  end
  return out
end

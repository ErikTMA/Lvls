-- Leveling route: an ordered list of accept / do / turn-in steps computed for THIS
-- character from the data, not a hand-written guide. Pure; positions through `geo`.
--
-- Method (first version: greedy simulation).
--   1. Pool: quests within ten levels of the character whose giver, every
--      objective and turn-in can be located (and walked to from one another), and
--      whose killing / looting takes at most maxWork seconds (drop chances count).
--   2. Repeat: from the current position, every possible next action (accept an
--      available quest when the log has room, work an objective of an accepted
--      quest, hand in a finished one) is charged the seconds it adds: getting
--      there, plus how much longer it makes the walk through the open work of
--      accepted quests (nearest first). Work on the way costs next to nothing, a
--      zig-zag costs its detour, and a far errand pays the walk back. With no
--      accepted work, the walk back to the nearest quests to pick up counts
--      instead. The cheapest wins. Experience does not order the work: everything
--      accepted gets done anyway, and dividing by it sent the route across the map
--      for one short, rewarding quest.
--      Everything at the npc you stand at is done before walking off; zoneFirst
--      finishes this map before leaving it, then chooses the next map as a whole
--      (R.Choose); quests in the log are always candidates, however
--      far, and count their experience once overdue; a hand-in counts part of what
--      it opens; class quests count more and keep their order; a pick-up or
--      hand-in within a small detour of the way to the chosen action is done in
--      passing; objectives close to the one being worked are worked at the same
--      time (one step: kill these, collect that); opts.skip leaves quests out.
--      Turn-ins add experience (reduced for quests below the simulated level),
--      level the simulation up, and complete the quest, which unlocks its
--      follow-ups through the normal prerequisite rules.
--      opts.training (Engine/Training: what a trainer of your class has waiting,
--      and the trainers): a "train" action at the nearest one, once per plan,
--      worth trainShare of a level's experience per point of what you can pay for,
--      so it is taken when the route passes a trainer or goes to the city anyway,
--      and a trip of its own once enough waits.
-- With opts.travel (Engine/Travel), long walks are priced by the fastest trip:
-- a known flight path makes a far quest hub cheap, and the boats, zeppelins and the
-- tram make the other continent a destination like any other (without opts.travel
-- it cannot be reached).
-- Ports (opts.ports, Engine/Travel: the hearthstone, teleports) are used by the
-- simulation as by a player: one that is on cooldown waits until it is ready on the
-- route's clock (the seconds of travel and work so far), and one the route uses goes
-- on cooldown for the steps after it. What a port costs (Travel.PortCost: a share of
-- its cooldown, a reagent) is part of its trip's seconds, so it is taken only when it
-- wins at least that much.
-- The route therefore follows chains and stays in an area while it pays, and moves
-- on when the quests that are left are worth less than the walk.
local _, ns = ...
local R = ns:NewModule("Route")
local G = ns.Geo

-- Experience to the next level, classic table (unverified for forever; the Game
-- adapter overrides the current level with the client's UnitXPMax).
R.XP_TO_LEVEL = {
  400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900, 14400,
  16000, 17700, 19400, 21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400,
  44300, 47400, 50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700, 95800,
  101000, 106300, 111800, 117500, 123200, 129100, 135100, 141200, 147500, 153900, 160400,
  167100, 173900, 180800, 187900, 195000, 202300, 209800,
}
R.MAX_LEVEL = 60 -- classic's; the client's cap (char.maxLevel) when it says
local function maxLevel(st) return st.char.maxLevel or R.MAX_LEVEL end
R.EVENT_SORT = 9 -- quest sort (Wowhead category2) of world events

R.DEFAULTS = {
  steps = 40,          -- route length
  logSize = 20,        -- quest log slots (Core/Init passes the client's: 40 on forever)
  speed = 7,           -- yards per second on foot
  killSeconds = 15,    -- per kill, including the walk between mobs
  objectSeconds = 15,  -- per object used / looted
  maxWork = 1200,      -- seconds of killing / looting: longer quests are not picked up (grinds)
  maxSecs = 600,       -- travel seconds; farther actions are left for later
  travelAbove = 90,    -- walks longer than this many seconds ask opts.travel (flights, boats)
  maxAbove = 3,        -- quest level at most this far above the character (mobs too hard)
  here = 20,           -- yards: actions at the npc you stand at come first
  together = 250,      -- yards: open objectives this close are worked at the same time
  localSecs = 60,      -- travel seconds: closer work is done in walking order
  hubYards = 300,      -- yards: farther work this close together is one destination
  onTheWay = 40,       -- yards: a pick-up / hand-in costing at most this detour is done in passing
  zoneFirst = true,    -- finish the current map before leaving it; then choose the next map as a whole
  skip = nil,          -- { [questId] = true }: quests the player does not want
  focus = nil,         -- { [questId] = true }: a guide: only these quests (any kind, any distance)
  grind = false,       -- suggest "grind to the next level" when quests here wait only on the margin
  grindAbove = 3,      -- the margin quests would have without the difficulty model
  grindNear = 700,     -- yards: quests and mobs this close count as "here"
  grindMaxSecs = 600,  -- a grind step is at most this long (else: quests elsewhere first)
  groupMargin = 0,     -- group (elite) quests need this many levels more
  dungeon = nil,       -- AreaTable id: objectives of quests in this instance wait for the dungeon step
  -- what makes a destination worth more than the experience of its pick-ups:
  leaveSecs = 1200,    -- zoneFirst: seconds another map is charged for leaving this one (what it must offer)
  continentSecs = 1800, -- zoneFirst: and more for another continent (a boat there and one back later)
  overdueBelow = 4,    -- a quest in the log this many levels below you is overdue: its work and hand-in
                       --   count their experience (it loses 20% a level from 6 below, then goes grey)
  unlockShare = 0.5,   -- a hand-in counts this share of the experience of what it opens (halved per step, 3 deep)
  classQuests = true,  -- class quests in the route (their order kept, farther trips allowed)
  classWeight = 2,     -- a class quest counts this much more than its experience (spells, forms, pets)
  classMaxSecs = 1800, -- travel seconds a class quest may be away (instead of maxSecs)
  training = nil,      -- { afford = points (Engine/Training), trainers = { spot, ... } }
  trainShare = 0.03,   -- a point of training is worth this share of the level's experience
  trainSecs = 30,      -- seconds at the trainer
  respawnSecs = 300,   -- seconds a cleared area takes to respawn: a small area that cannot
                       --   give the whole objective is charged for the waits
}

-- Experience a quest gives at a character level (classic reduction: 20% less per
-- level above questLevel + 5, at least 10%).
function R.QuestXP(q, level)
  local xp = q.xp or 0
  if not q.l then return xp end
  local over = level - q.l - 5
  if over <= 0 then return xp end
  return math.floor(xp * math.max(0.1, 1 - 0.2 * over) + 0.5)
end

-- Work seconds for one objective (qty / drop chance kills, objects, purchases).
local function workSeconds(o, spots, opts)
  local qty = o.qty or 1
  if o.t == "kill" then return qty * opts.killSeconds end
  if o.t == "object" then return qty * opts.objectSeconds end
  if o.t == "item" then
    local best = 0
    local vendor = false
    for _, s in ipairs(spots) do
      if s.vendor then vendor = true end
      if s.pct and s.pct > best then best = s.pct end
      if s.kind == "o" and (not s.pct or s.pct == 0) then best = math.max(best, 100) end
    end
    if vendor and best == 0 then return 10 end
    if best <= 0 then best = 30 end
    return qty * opts.killSeconds * 100 / best
  end
  return 60
end

-- What one spawn of an objective gives towards it: a kill or an object 1, a drop its
-- chance (30% when unknown), a vendor all of it.
local function spawnYield(o)
  if o.t ~= "item" then return function() return 1 end end
  return function(s)
    if s.vendor then return 1e6 end
    if s.pct and s.pct > 0 then return s.pct / 100 end
    if s.kind == "o" then return 1 end
    return 0.3
  end
end

-- Objective areas (G.Group) with `rounds`: how many times an area must respawn before
-- it has given the objective (0 when it is big enough). The route weighs an area by
-- the walk plus those waits, so a patch of a few mobs close by does not win over the
-- big area the objective is meant for.
local function objectiveTargets(o, spots)
  local targets = G.Group(spots, 5, spawnYield(o))
  local qty = o.qty or 1
  for _, t in ipairs(targets) do
    t.rounds = t.area > 0 and math.max(0, qty - t.area) / t.area or 0
  end
  return targets
end

-- Plannable shape of a quest: giver spots, per-objective target clusters, turn-in
-- spots. nil and why when any part cannot be located.
-- entry: the quest log's entry when the quest is in the log. Then the log decides:
-- an objective it reports done is done, whatever the data knows of it; one the route
-- cannot plan (no location, reputation, a spell, inside a dungeon) is left to you,
-- and the quest is handed in once the client says it is complete. No experience
-- or giver needed: it is yours already.
local function shape(ds, q, dungeon, bagStart, pos, opens, entry)
  -- no experience: only a link that opens others (a delivery, a breadcrumb chain)
  if not entry and (not q.xp or q.xp <= 0) and not opens then return nil, "no experience and opens nothing" end
  local givers = ns.Quests.Givers(ds, q)
  -- started by an item in your bags: picked up where you stand (use the item)
  if #givers == 0 and bagStart and pos then
    givers = { { map = pos.map, x = pos.x, y = pos.y, kind = "item", id = bagStart } }
  end
  local ends = ns.Quests.TurnIns(ds, q)
  -- no known giver (it starts inside a dungeon): plannable once in the log
  if #ends == 0 then return nil, "no known place to hand it in" end
  local objs = {}
  for i, o in ipairs(q.obj or {}) do
    local why
    if o.from == "provided" or o.dup or (entry and ns.Quests.ObjectiveDone(entry, o, i)) then
      objs[i] = { free = true }
    elseif (dungeon and q.inst and q.zone == dungeon) or (entry and q.inst) then
      objs[i] = { dungeon = true } -- done inside: never planned as field work (a dungeon guide)
    elseif o.t == "faction" or o.t == "spell" then
      why = ("objective %d needs %s"):format(i, o.t == "faction" and "reputation" or "a spell")
    else
      local spots = ns.Quests.ObjectiveSpots(ds, q, i)
      if #spots > 0 then
        objs[i] = { targets = objectiveTargets(o, spots), spots = spots }
      else
        why = ("no location known for: %s"):format(o.text or ("objective " .. i))
      end
    end
    if why then
      if not entry then return nil, why end
      objs[i] = { blocked = true } -- in the log: yours to do; handed in once complete
    end
  end
  return { givers = givers, ends = ends, objs = objs }
end

-- Travel seconds between two spots: walking, or opts.travel (Engine/Travel: flight
-- paths, boats, hearthstone) when the walk is long.
-- Also returns the port the trip starts with (opts.ports), if any.
local function travelSecs(o, a, b, d)
  local walk = d / o.speed
  if o.travel and walk > o.travelAbove and walk < math.huge then
    local ok, t, via = pcall(o.travel, a, b, o.usable)
    if ok and t and t < walk then return t, via end
  end
  return walk
end

-- The objective area to work: the fewest seconds of walking plus respawn waits
-- (objectiveTargets). Returns the spot and its yards, as G.Nearest.
local function bestTarget(o, geo, from, targets)
  local best, bestD, bestC = nil, math.huge, math.huge
  for _, t in ipairs(targets) do
    local d = G.Distance(geo, from, t)
    if d < math.huge then
      local c = d / o.speed + (t.rounds or 0) * o.respawnSecs
      if c < bestC then best, bestD, bestC = t, d, c end
    end
  end
  return best, bestD
end

-- The area to work one objective in, from `from`, as the route chooses it (walk plus
-- respawn waits; opts as R.DEFAULTS). nil when the data cannot place it.
function R.WorkTarget(ds, q, i, geo, from, opts)
  local o = q.obj and q.obj[i]
  if not o or not from then return nil end
  local spots = ns.Quests.ObjectiveSpots(ds, q, i, from.map)
  if #spots == 0 then spots = ns.Quests.ObjectiveSpots(ds, q, i) end
  if #spots == 0 then return nil end
  local oo = { speed = opts and opts.speed or R.DEFAULTS.speed,
    respawnSecs = opts and opts.respawnSecs or R.DEFAULTS.respawnSecs }
  local targets = objectiveTargets(o, spots)
  return bestTarget(oo, geo, from, targets) or targets[1]
end

-- The spot to go to and the seconds it takes: the nearest on this continent, else
-- (all on another one) the fastest by opts.travel, which knows boats and zeppelins.
-- Returns spot, yards (math.huge across continents), seconds (math.huge: unreachable).
-- here: only this continent (the route stays on this map anyway).
local CROSS_TRIES = 4 -- spots tried on another continent (targets are biggest first)
local CROSS_AVAIL = 12 -- quests to pick up on another continent offered per step (the quickest)
local function reachSpot(o, geo, from, spots, here)
  local best, d = bestTarget(o, geo, from, spots)
  if best then return best, d, travelSecs(o, from, best, d) end
  if here or not o.travel then return nil, math.huge, math.huge end
  local secs
  for k = 1, math.min(#spots, CROSS_TRIES) do
    local ok, t = pcall(o.travel, from, spots[k], o.usable)
    if ok and t and t < math.huge and (not secs or t < secs) then best, secs = spots[k], t end
  end
  return best, math.huge, secs or math.huge
end

-- "Grind to the next level": when the only quests left here wait on the difficulty
-- margin (they would be planned without it) or on their required level, and one level
-- more unlocks them, kill easy mobs close by until then. Returns the action or nil.
-- Only the next level: more than that is the route's to solve by going elsewhere.
-- (A level-7 dwarf left Dun Morogh for Elwynn Forest when three quests in Kharanos
-- were a level away; a hand-written guide kills a few mobs and stays.)
-- npcs a quest asks you to kill once (named ones: Old Murk-Eye), per dataset
local namedTargets = setmetatable({}, { __mode = "k" })
local function named(ds)
  local t = namedTargets[ds]
  if t then return t end
  t = {}
  for _, q in pairs(ds.quests) do
    for _, ob in ipairs(q.obj or {}) do
      if ob.t == "kill" and ob.id and (ob.qty or 1) == 1 then t[ob.id] = true end
    end
  end
  namedTargets[ds] = t
  return t
end

-- Quests held back one level: by the difficulty margin (grindAbove, the margin they
-- would have without the difficulty model) or, "next level", by their required level
-- or the margin itself (their level is one above level + maxAbove). Returns the level
-- that opens them (or nil), how many have a giver within grindNear, and whether any
-- of those is a next-level one.
local function heldNext(o, st, sim, pos, geo, pool, consider, shapes, workSecs)
  if st.level >= maxLevel(st) then return nil, 0, false end
  local A = ns.Availability
  local unlock, held, byLevel = nil, 0, false
  local nextL = st.level + 1
  for _, q in ipairs(pool) do
    if not sim.completed[q.id] and not sim.active[q.id] then
      local need, nxt
      if q.l and q.l > st.level + o.maxAbove and q.l <= st.level + o.grindAbove then
        need = A.Status(q, sim) == "available" and q.l - o.maxAbove or nil
      elseif q.r and q.r == nextL and (not q.l or q.l <= nextL + o.maxAbove) then
        local stt, w = A.Status(q, sim)
        if stt == "low" and tostring(w):match("^level") then need, nxt = nextL, true end
      elseif q.l and q.l == nextL + o.maxAbove and A.Status(q, sim) == "available" then
        need, nxt = nextL, true
      end
      if need == nextL and consider(q) and workSecs[q.id] <= o.maxWork then
        local _, d = G.Nearest(geo, pos, shapes[q.id].givers)
        if d <= o.grindNear then
          held = held + 1
          if nxt then byLevel = true end
          unlock = need
        end
      end
    end
  end
  return unlock, held, byLevel
end

local function grindAction(ds, o, st, sim, pos, geo, pool, consider, shapes, nothingElse, workSecs)
  if not o.grind or st.level >= maxLevel(st) then return nil end
  local Df = ns.Difficulty
  local unlock, held, byLevel = heldNext(o, st, sim, pos, geo, pool, consider, shapes, workSecs)
  if not unlock then return nil end
  -- easy mobs close by: at most your level (the margin is below it), worth experience
  local best, bestScore
  local skipNamed = named(ds)
  for id, n in pairs(ds.npcs) do
    local lv = n.lv
    local top = lv and lv[2] or (lv and lv[1])
    -- normal mobs only: no elites, rares or bosses, no named quest targets
    if top and not n.elite and not skipNamed[id] and top <= st.level + math.min(0, o.maxAbove + 1)
      and top >= st.level - 2 and n.p and n.p[pos.map] then
      local near, nearest, nd = 0, nil, math.huge
      for _, packed in ipairs(n.p[pos.map]) do
        local x, y = G.Unpack(packed)
        local d = G.Distance(geo, pos, { map = pos.map, x = x, y = y })
        if d <= o.grindNear then
          near = near + 1
          if d < nd then nearest, nd = { map = pos.map, x = x, y = y }, d end
        end
      end
      if near >= 4 then
        local score = near / (1 + nd / 200)
        if not bestScore or score > bestScore then best, bestScore = { id = id, n = n, level = top, spot = nearest }, score end
      end
    end
  end
  if not best then return nil end
  local need = ((st.level == st.char.level and st.char.xpMax) or R.XP_TO_LEVEL[st.level] or 0) - st.xp
  if need <= 0 then return nil end
  local per = math.max(1, Df.MobXP(best.level, st.level))
  local kills = math.ceil(need / per)
  -- only the rest of a level, and only when it is short; a whole level of killing
  -- only when there is nothing else to do at all
  if not nothingElse and kills * o.killSeconds > o.grindMaxSecs then return nil end
  return { kind = "grind", level = st.level + 1, xp = need, npc = best.id, name = best.n.n, spot = best.spot,
    kills = math.ceil(need / per), held = held, byLevel = byLevel or nil }
end

local function simLevel(st, xpGain)
  st.xp = st.xp + xpGain
  while st.level < maxLevel(st) do
    local need = (st.level == st.char.level and st.char.xpMax) or R.XP_TO_LEVEL[st.level]
    if not need or st.xp < need then break end
    st.xp = st.xp - need
    st.level = st.level + 1
  end
end

-- Pick the next action from the candidates ({ action, score, secs, effort }).
--   Work within localSecs is done in walking order (lowest score: the seconds it
--   adds). Only when everything left is farther does the route travel, and then to
--   the best destination, not the nearest action: far candidates are grouped into
--   destinations (hubYards apart at most). A destination is worth the experience
--   of the quests to pick up there, divided by what going there costs: the seconds
--   the trip adds (travel, flight paths included, and how much longer it makes the
--   way through the work of accepted quests; a place you must go to anyway to hand
--   in costs next to nothing) plus the work of those quests. Hand-ins and
--   objectives of accepted quests add no worth: they are done anyway, and counting
--   them sent the route back and forth for one hand-in. One quest alone does not
--   pull the route across the map when a hub with five is as far. With nothing to
--   pick up anywhere, the cheapest action (accepted work in walking order).
--   Worth beyond the pick-ups (c.worth, from R.Plan): an overdue quest in the log,
--   a hand-in that opens a chain, a class quest. A plain hand-in still adds none.
--   zoneFirst, zone by zone like a hand-written guide: while this map has anything
--   left (pick-ups, objectives, hand-ins), the route stays; nothing elsewhere counts,
--   not even a chain, an overdue or a class quest (each of them pulled it away with
--   work left behind, and back again later). Leaving, the next map is chosen as a
--   whole: everything there (pick-ups, the log's hand-ins with their experience, what
--   they open, overdue work) per second of the trip, the pick-ups' work, leaveSecs,
--   and continentSecs for another continent. So deliveries wait until the route goes
--   there anyway, and the route does not cross an ocean for a quest or two. On that
--   map: its best destination, else its nearest.
-- point(spot) -> { continent, x, y } in yards; gain(questId) -> experience.
function R.Choose(cands, pos, o, point, gain)
  local near, far = nil, {}
  for _, c in ipairs(cands) do
    if c.secs <= o.localSecs and c.action.spot.map == pos.map then
      if not near or c.score < near.score then near = c end
    else
      far[#far + 1] = c
    end
  end
  if near then return near.action end
  if #far == 0 then return nil end
  table.sort(far, function(a, b) if a.secs ~= b.secs then return a.secs < b.secs end return a.score < b.score end)
  local hubs, r2, workHere = {}, o.hubYards * o.hubYards, false
  for _, c in ipairs(far) do
    local p, hub = point(c.action.spot), nil
    for _, h in ipairs(hubs) do
      local dx, dy = p[2] - h.p[2], p[3] - h.p[3]
      if h.p[1] == p[1] and h.map == c.action.spot.map and dx * dx + dy * dy <= r2 then hub = h; break end
    end
    if not hub then
      hub = { p = p, map = c.action.spot.map, secs = c.secs, effort = 0, quests = {}, worths = {}, xp = 0,
        first = c, members = {} }
      hubs[#hubs + 1] = hub
    end
    hub.members[#hub.members + 1] = c
    local q = c.action.quest
    if c.action.kind == "accept" and not hub.quests[q] then
      hub.quests[q] = true
      hub.xp = hub.xp + gain(q)
      hub.effort = hub.effort + c.effort
    end
    local wk = c.action.kind .. ":" .. tostring(q)
    if (c.worth or 0) > 0 and not hub.worths[wk] then
      hub.worths[wk] = true
      hub.xp = hub.xp + c.worth
    end
    if c.action.spot.map == pos.map then workHere = true end
    if c.score < hub.first.score then hub.first = c end
  end
  local leave = o.zoneFirst and o.leaveSecs or 0
  for _, h in ipairs(hubs) do
    local adds
    for _, c in ipairs(h.members) do if not adds or c.adds < adds then adds = c.adds end end
    h.adds = adds
    local away = h.map ~= pos.map and leave or 0
    h.cost = math.max(1, adds) + h.effort + away
    h.rate = h.xp / h.cost
  end
  -- zoneFirst, leaving: another map is chosen as a whole, by everything there (its
  -- pick-ups and the log's hand-ins and overdue work there) per second of the trip
  -- and the pick-ups' work, the way a hand-written guide moves zone by zone. So a
  -- delivery waits until the route goes there anyway, and then it adds its experience
  -- to the trip; one quest alone does not pull the route to a zone with nothing else.
  local maps, mapList, home = {}, {}, point(pos)
  if o.zoneFirst then
    for _, c in ipairs(far) do
      local m = c.action.spot.map
      if m ~= pos.map then
        local e = maps[m]
        if not e then
          e = { map = m, p = point(c.action.spot), xp = 0, effort = 0, seen = {} }
          maps[m] = e
          mapList[#mapList + 1] = e
        end
        if not e.adds or c.adds < e.adds then e.adds = c.adds end
        local k, q = c.action.kind, c.action.quest
        local key = k .. ":" .. tostring(q)
        if not e.seen[key] then
          e.seen[key] = true
          if k == "accept" or k == "turnin" then
            e.xp = e.xp + (q and gain(q) or 0) + (c.worth or 0)
            e.effort = e.effort + (c.effort or 0)
          else
            e.xp = e.xp + (c.worth or 0)
          end
        end
      end
    end
    for _, e in ipairs(mapList) do
      e.cost = math.max(1, e.adds) + e.effort + leave + (e.p[1] ~= home[1] and o.continentSecs or 0)
      e.rate = e.xp / e.cost
    end
  end
  local best, bestRate, cheapest, cheapestScore
  for _, h in ipairs(hubs) do
    -- zoneFirst: work left on this map, the route does not leave
    if not (o.zoneFirst and workHere and h.map ~= pos.map) then
      local away = h.map ~= pos.map and leave or 0
      -- zoneFirst: another map competes as a whole (below), not hub by hub
      if h.xp > 0 and (not bestRate or h.rate > bestRate) and not (o.zoneFirst and h.map ~= pos.map) then
        best, bestRate = h, h.rate
      end
      local score = h.first.score + away
      if not cheapest or score < cheapestScore then cheapest, cheapestScore = h, score end
    end
  end
  if o.zoneFirst and not workHere then
    local bestMap
    for _, e in ipairs(mapList) do
      if e.xp > 0 and (not bestRate or e.rate > bestRate) then bestMap, bestRate = e, e.rate end
    end
    if bestMap then
      -- there: the best destination of that map (else its nearest)
      best = nil
      local r, near
      for _, h in ipairs(hubs) do
        if h.map == bestMap.map then
          if h.xp > 0 and (not r or h.rate > r) then best, r = h, h.rate end
          if not near or h.adds < near.adds then near = h end
        end
      end
      best = best or near
    end
  end
  R.lastMaps = mapList -- for debugging and tests
  R.lastHubs = hubs -- for debugging and tests
  return (best or cheapest).first.action
end

-- What a quest opens: quest id -> the quests that need it (series, provider
-- prerequisites), per dataset and provider (Engine/GuideCache).
local function buildOpens(ds)
  local by = {}
  local function add(from, to)
    if from and from ~= to then by[from] = by[from] or {}; table.insert(by[from], to) end
  end
  for id, q in pairs(ds.quests) do
    local info = ns.Prereqs.Info(id)
    if info then
      for _, p in ipairs(info.group or {}) do add(p, id) end
      for _, p in ipairs(info.single or {}) do add(p, id) end
    elseif q.prevAny then
      for _, p in ipairs(q.prevAny) do add(p, id) end
    elseif q.prev and not q.prevLoop then
      add(q.prev, id)
    end
  end
  for _, l in pairs(by) do table.sort(l) end
  return by
end
function R.Opens(ds, char) return ns.GuideCache.Get(ds, char, "opens", buildOpens) end

function R.Plan(ds, char, geo, opts)
  local o = {}
  for k, v in pairs(R.DEFAULTS) do o[k] = v end
  for k, v in pairs(opts or {}) do o[k] = v end
  if o.focus then
    -- a guide: every quest of it as soon as the client allows, wherever it is
    -- (a finite limit: what cannot be reached at all stays out)
    o.maxAbove, o.maxSecs, o.zoneFirst = math.huge, 1e9, false
  end
  local A = ns.Availability
  -- simulated character: same tables, completed / active copied
  local sim = { level = char.level, faction = char.faction, race = char.race, class = char.class,
    skills = char.skills, rep = char.rep, completed = {}, active = {} }
  for k, v in pairs(char.completed) do sim.completed[k] = v end
  for k, v in pairs(char.active or {}) do sim.active[k] = v end
  local st = { level = char.level, xp = char.xp or 0, char = char }
  local pos = char.pos
  if not pos then return {}, "position unknown" end
  -- on the zone's map (geo.zone, optional): what is "here" compares maps, and the
  -- client reports some places on a building's or the continent's map
  pos = geo and geo.zone and geo.zone(pos) or pos

  -- pool and shapes
  local shapes, workSecs = {}, {}
  local bagStarts = ns.Quests.BagStarts(ds, char)
  local opens = R.Opens(ds, char)
  local function consider(q)
    if shapes[q.id] ~= nil then return shapes[q.id] end
    -- in the log: the log decides (shape); where it was picked up no longer matters
    -- (Unrequited Love: given in Darkshore, handed in at Menethil Harbor), each
    -- objective and the turn-in are reached on their own, across the sea by opts.travel
    local entry = char.active and char.active[q.id]
    local s = shape(ds, q, o.dungeon, bagStarts[q.id], pos, opens[q.id] ~= nil, entry)
    shapes[q.id] = s or false
    if s then
      -- not in the log: giver -> objectives -> turn-in must be walkable (one continent)
      local here = s.givers[1] or s.ends[1]
      workSecs[q.id] = 0
      for i in ipairs(q.obj or {}) do
        local ob = s.objs[i]
        if ob and ob.targets then
          workSecs[q.id] = workSecs[q.id] + workSeconds(q.obj[i], ob.spots, o)
          local tgt, d = bestTarget(o, geo, here, ob.targets)
          if not entry and d == math.huge then shapes[q.id] = false; return false end
          here = tgt or here
        end
      end
      local _, d = G.Nearest(geo, here, s.ends)
      if not entry and d == math.huge then shapes[q.id] = false; return false end
    end
    return shapes[q.id]
  end

  -- progress of quests already in the log: objectives the client reports done
  local progress = {}
  for qid, entry in pairs(sim.active) do
    local q = ds.quests[qid]
    progress[qid] = {}
    if q then
      for i, ob in ipairs(q.obj or {}) do
        if ns.Quests.ObjectiveDone(entry, ob, i) then progress[qid][i] = true end
      end
    end
  end

  -- what needs no work (a provided item) is done as soon as the quest is taken, so
  -- a lone delivery is handed in even when nothing else is on offer
  local function markFree(q)
    local s = consider(q)
    for i in ipairs(q.obj or {}) do
      if s and s.objs[i] and s.objs[i].free then progress[q.id][i] = true end
    end
  end
  for qid in pairs(progress) do if ds.quests[qid] then markFree(ds.quests[qid]) end end

  local function logCount()
    local n = 0
    for _ in pairs(sim.active) do n = n + 1 end
    return n
  end

  local function allDone(q)
    for i in ipairs(q.obj or {}) do
      if not progress[q.id][i] then return false end
    end
    return true
  end

  -- experience a quest gives now (reduced when it is low for the simulated level)
  local function gain(qid) return math.max(1, R.QuestXP(ds.quests[qid], st.level)) end

  -- class quests: the chain graph (Engine/ClassQuests), so their order is kept
  local classOf = o.classQuests and not o.focus and ns.ClassQuests and ns.ClassQuests.Graph(ds, char).of or {}
  local function classAfter(qid)
    local g = classOf[qid]
    local p, guard = g and g.after[qid], 0
    while p and A.Status(ds.quests[p], sim) == "wrong" and guard < 64 do p, guard = g.after[p], guard + 1 end
    return p
  end
  -- what a hand-in opens, in experience: unlockShare of each quest it opens that
  -- this character can do, halved per step, three steps deep
  local function unlockWorth(qid)
    local total, seen = 0, {}
    local function walk(id, depth, share)
      if depth > 3 then return end
      for _, f in ipairs(opens[id] or {}) do
        if not seen[f] then
          seen[f] = true
          local fq = ds.quests[f]
          if fq and not sim.completed[f] and not sim.active[f] and not A.Fixed(fq, sim)
            and (not fq.l or fq.l <= st.level + o.maxAbove + 2) and not (o.skip and o.skip[f]) and consider(fq) then
            total = total + share * gain(f)
            walk(f, depth + 1, share / 2)
          end
        end
      end
    end
    walk(qid, 1, o.unlockShare)
    return total
  end
  -- what an action is worth beyond the experience of a pick-up (R.Choose)
  local function worth(kind, qid)
    local q, w = ds.quests[qid], 0
    if kind ~= "accept" and q.l and st.level >= q.l + o.overdueBelow then w = w + gain(qid) end
    if kind == "turnin" then w = w + unlockWorth(qid) end
    if classOf[qid] then w = w + o.classWeight * gain(qid) end
    return w
  end

  -- training: once, at the nearest trainer of your class
  local trainAt = not o.focus and o.training and (o.training.afford or 0) >= ns.Training.PASS
    and o.training.trainers and #o.training.trainers > 0 and o.training.trainers or nil
  local trained = false

  local steps = {}
  local pool = {}
  for qid, q in pairs(ds.quests) do
    -- sort 9: world events (Winter Veil, Hallow's End): only while the event runs, which
    -- the data does not say; in the log they are still handed in
    local normal = not q.rep and not q.inst and q.kind ~= "dungeon" and q.kind ~= "raid"
      and q.kind ~= "pvp" and q.sort ~= R.EVENT_SORT and (not q.r or q.r <= char.level + 10)
    if (q.sn or q.so or bagStarts[qid]) and not (o.skip and o.skip[qid]) and (o.focus and o.focus[qid] or (not o.focus and normal)) then
      pool[#pool + 1] = q
    end
  end
  table.sort(pool, function(a, b) return a.id < b.id end)
  local inPool = {}
  for _, q in ipairs(pool) do inPool[q.id] = true end

  -- A chain's later quest that can be picked up on its own shuts its earlier ones
  -- off (Engine/Prereqs). It waits while an earlier one is worth doing: one the
  -- route would pick up itself, or one in the log (until it is handed in). An
  -- earlier one not worth it (grey, too high, too long, skipped, not on the map)
  -- holds nothing: the later quest is taken and the earlier one is left out.
  local function aboveFor(q) return q.kind == "group" and (o.maxAbove - o.groupMargin) or o.maxAbove end
  local function held(q)
    for _, e in ipairs(q.earlier or {}) do
      local eq = ds.quests[e]
      if eq and not sim.completed[e] and not (o.skip and o.skip[e]) and not (o.focus and not o.focus[e]) then
        if sim.active[e] then
          if consider(eq) then return e end
        elseif inPool[e] and (not eq.l or eq.l <= st.level + aboveFor(eq)) and A.Status(eq, sim) == "available"
          and consider(eq) and (o.focus or workSecs[e] <= o.maxWork) then
          return e
        end
      end
    end
  end

  -- the route's clock and its ports: ready at clock >= readyAt (the client's
  -- cooldown left at first, then the full cooldown from when the route used one)
  local clock, readyAt, portOf = 0, {}, {}
  for _, p in ipairs(o.ports or {}) do readyAt[p.id], portOf[p.id] = p.ready or 0, p end
  local efforts = setmetatable({}, { __mode = "k" }) -- action -> seconds of work there
  local function portsNow()
    if not o.ports then return nil end
    local u = {}
    for id, at in pairs(readyAt) do if at <= clock then u[id] = true end end
    return u
  end

  local guard = 0
  local yield = ns.Util.Yield -- a slice at a time when planned as a job (Core/Init)
  while #steps < o.steps and guard < o.steps * 4 do
    guard = guard + 1
    yield()
    o.usable = portsNow()
    local best
    -- open work: the next target of every accepted quest, so an action that leads
    -- away from it pays for the walk back (greedy steps otherwise wander off)
    local pending = {}
    for qid in pairs(sim.active) do
      local q = not (o.skip and o.skip[qid]) and not (o.focus and not o.focus[qid]) and ds.quests[qid]
      local s = q and consider(q)
      if s and progress[qid] then
        if allDone(q) then
          pending[#pending + 1] = { quest = qid, spot = G.Nearest(geo, pos, s.ends) or s.ends[1] }
        else
          for i in ipairs(q.obj or {}) do
            local so = s.objs[i]
            if so and so.targets and not progress[qid][i] then
              pending[#pending + 1] = { quest = qid, index = i, spot = bestTarget(o, geo, pos, so.targets) or so.targets[1] }
            end
          end
        end
      end
    end
    -- quests that could be picked up count as open work too (the nearest few)
    local avail, overseas = {}, {}
    local function limitOf(qid) return classOf[qid] and math.max(o.maxSecs, o.classMaxSecs) or o.maxSecs end
    -- zoneFirst: this map has work left (the log's, or quests to pick up here), so the
    -- route stays and nothing on another continent could be chosen
    local busyNow
    local function busy()
      if busyNow == nil then
        busyNow = false
        if o.zoneFirst then
          for _, p in ipairs(pending) do if p.spot and p.spot.map == pos.map then busyNow = true; break end end
          for _, a in ipairs(avail) do if busyNow or a.spot.map == pos.map then busyNow = true; break end end
        end
      end
      return busyNow
    end
    if logCount() < o.logSize then
      for _, q in ipairs(pool) do
        yield()
        if not sim.completed[q.id] and not sim.active[q.id] and (not q.l or q.l <= st.level + aboveFor(q))
          and (A.Status(q, sim) == "available" or (o.focus and A.Status(q, sim) == "trivial")) and consider(q) and (o.focus or workSecs[q.id] <= o.maxWork)
          and not (classOf[q.id] and classAfter(q.id) and not sim.completed[classAfter(q.id)])
          and not held(q) then
          local givers = shapes[q.id].givers
          local spot, d = G.Nearest(geo, pos, givers)
          if spot then
            local secs = travelSecs(o, pos, spot, d)
            if secs <= limitOf(q.id) then avail[#avail + 1] = { quest = q.id, spot = spot, d = d, secs = secs } end
          elseif o.travel then
            overseas[#overseas + 1] = q
          end
        end
      end
      -- on another continent: asked of opts.travel (the slow part of a step) only when
      -- this map has nothing left (zoneFirst: while it has, the route stays), and only
      -- the quickest few are offered, enough to judge the trip
      if not busy() and #overseas > 0 then
        local far = {}
        for _, q in ipairs(overseas) do
          local spot, d, secs = reachSpot(o, geo, pos, shapes[q.id].givers)
          if spot and secs <= limitOf(q.id) then far[#far + 1] = { quest = q.id, spot = spot, d = d, secs = secs } end
        end
        table.sort(far, function(x, y) if x.secs ~= y.secs then return x.secs < y.secs end return x.quest < y.quest end)
        for i = 1, math.min(#far, CROSS_AVAIL) do avail[#avail + 1] = far[i] end
      end
      table.sort(avail, function(x, y) if x.d ~= y.d then return x.d < y.d end
        if x.secs ~= y.secs then return x.secs < y.secs end return x.quest < y.quest end)
      for i = 1, math.min(#avail, 15) do pending[#pending + 1] = avail[i] end
    end
    -- the walk through the open work of accepted quests (nearest first), in
    -- seconds: an action is charged what it adds to that walk, so one on the way
    -- costs nothing extra and a zig-zag costs the detour
    local wp = {}
    local function point(spot)
      local p = wp[spot]
      if not p then
        local c, x, y
        if geo and geo.world then c, x, y = geo.world(spot.map, spot.x, spot.y) end
        if not c then
          local w, h = 1000, 1000
          if geo and geo.size then
            local sw, sh = geo.size(spot.map)
            if sw and sw > 0 and sh and sh > 0 then w, h = sw, sh end
          end
          c, x, y = "m" .. spot.map, spot.x / 100 * w, spot.y / 100 * h
        end
        p = { c, x, y }
        wp[spot] = p
      end
      return p
    end
    local FAR = 2000 -- yards charged for work that cannot be walked to (another continent)
    local work = {}
    for _, p in ipairs(pending) do
      if p.spot and not p.secs then work[#work + 1] = p end
    end
    local function tour(from, action)
      local left = {}
      for _, p in ipairs(work) do
        if not (action and p.quest == action.quest and (action.kind ~= "do" or p.index == action.index)) then
          left[#left + 1] = point(p.spot)
        end
      end
      local at, yards = point(from), 0
      while #left > 0 do
        local k, kd = 1, math.huge
        for i, q in ipairs(left) do
          local d = FAR
          if q[1] == at[1] then
            local dx, dy = q[2] - at[2], q[3] - at[3]
            d = math.sqrt(dx * dx + dy * dy)
          end
          if d < kd then k, kd = i, d end
        end
        yards = yards + kd
        at = table.remove(left, k)
      end
      return yards / o.speed
    end
    local tourNow = tour(pos)
    -- with no accepted work, the walk back to the nearest quests to pick up
    local function back(action)
      if #work > 0 then return tour(action.spot, action) - tourNow end
      local d = math.huge
      for _, p in ipairs(pending) do
        if p.spot and p.quest ~= action.quest then
          local x = G.Distance(geo, action.spot, p.spot)
          if x < d then d = x end
        end
      end
      if d == math.huge then return 0 end
      return d / o.speed
    end
    -- hand-ins and pick-ups at the npc you stand at always come first
    local here, hereScore
    local cands = {}      -- { action, score } of everything that is not "here"
    local talks = {}      -- pick-ups and hand-ins, for "on the way"
    -- at the npc you stand at: the most experience per second first; elsewhere: the
    -- seconds the action adds (see the method above)
    local function offer(action, secs, effort)
      efforts[action] = effort
      local value = worth(action.kind, action.quest)
      local xp = gain(action.quest)
      if action.kind ~= "do" and G.Distance(geo, pos, action.spot) <= o.here then
        local score = secs / xp
        if not hereScore or score < hereScore then here, hereScore = action, score end
        return
      end
      if action.kind ~= "do" then talks[#talks + 1] = action end
      -- adds: the trip plus how much longer it makes the way through accepted work
      local adds = secs + (#work > 0 and (tour(action.spot, action) - tourNow) or 0)
      cands[#cands + 1] = { action = action, score = secs + back(action), secs = secs, adds = adds,
        effort = effort or 0, worth = value }
    end
    -- hand in / work accepted quests
    for qid in pairs(sim.active) do
      yield()
      local q = not (o.skip and o.skip[qid]) and not (o.focus and not o.focus[qid]) and ds.quests[qid]
      local s = q and consider(q)
      if s and progress[qid] then
        if allDone(q) then
          local spot, _, secs = reachSpot(o, geo, pos, s.ends, busy())
          -- in the log: always a candidate, however far (priced by the trip)
          if secs < math.huge then
            offer({ kind = "turnin", quest = qid, spot = spot }, secs + 5, 5)
          end
        else
          for i, ob in ipairs(q.obj or {}) do
            if not progress[qid][i] then
              local so = s.objs[i]
              if so and so.free then
                progress[qid][i] = true
              elseif so and so.targets then
                local tgt, _, secs = reachSpot(o, geo, pos, so.targets, busy())
                if secs < math.huge then
                  offer({ kind = "do", quest = qid, index = i, spot = tgt },
                    secs, workSeconds(ob, so.spots, o) + (tgt.rounds or 0) * o.respawnSecs)
                end
              end
            end
          end
        end
      end
    end
    -- accept
    for _, a in ipairs(avail) do
      yield()
      offer({ kind = "accept", quest = a.quest, spot = a.spot }, a.secs + 3, 3 + workSecs[a.quest])
    end
    if trainAt and not trained then
      local spot, d = G.Nearest(geo, pos, trainAt)
      local secs = spot and d < math.huge and travelSecs(o, pos, spot, d) or math.huge
      if secs <= math.max(o.maxSecs, o.classMaxSecs) then
        local action = { kind = "train", spot = spot, npc = spot.id, name = spot.name }
        efforts[action] = o.trainSecs
        local levelXP = (st.level == char.level and char.xpMax) or R.XP_TO_LEVEL[st.level] or 0
        cands[#cands + 1] = { action = action, score = secs + back(action), secs = secs,
          adds = secs + (#work > 0 and (tour(spot, action) - tourNow) or 0), effort = o.trainSecs,
          worth = o.training.afford * o.trainShare * levelXP }
      end
    end
    best = R.Choose(cands, pos, o, point, gain)
    -- nothing left close by but quests the margin holds back: grind the next level
    if not here then
      local close = false
      for _, c in ipairs(cands) do
        if c.secs <= o.localSecs and c.action.spot.map == pos.map then close = true; break end
      end
      -- quests here a level away (byLevel): grind rather than leave the map, the way a
      -- hand-written guide stays (a level-7 dwarf left Dun Morogh for Elwynn Forest
      -- with three quests in Kharanos a level away); work elsewhere on the map first
      local leaving = not best or best.spot.map ~= pos.map
      if not close then
        local g = grindAction(ds, o, st, sim, pos, geo, pool, consider, shapes, best == nil, workSecs)
        if g and (not g.byLevel or leaving) then best = g end
      end
    end
    -- a pick-up or hand-in close to the way there is done in passing
    if best and not here then
      local direct = G.Distance(geo, pos, best.spot)
      local pick, pickD
      for _, t in ipairs(talks) do
        if t ~= best and t.spot.map == best.spot.map then
          local d1 = G.Distance(geo, pos, t.spot)
          if d1 < direct and d1 + G.Distance(geo, t.spot, best.spot) - direct <= o.onTheWay
            and (not pickD or d1 < pickD) then
            pick, pickD = t, d1
          end
        end
      end
      if pick then best = pick end
    end
    if here then best = here end
    if not best then break end
    -- the clock: the way there (a port it starts with goes on cooldown) and the work
    local dBest = G.Distance(geo, pos, best.spot)
    local tripSecs, via = travelSecs(o, pos, best.spot, dBest)
    if dBest == math.huge and o.travel then -- another continent: only by opts.travel
      local ok, t, v = pcall(o.travel, pos, best.spot, o.usable)
      if ok and t then tripSecs, via = t, v end
    end
    if via and portOf[via] then
      readyAt[via] = clock + (portOf[via].cd or 0)
      best.port = via
    end
    clock = clock + (tripSecs < math.huge and tripSecs or 0)
      + (efforts[best] or (best.kills and best.kills * o.killSeconds) or 0)
    local q = ds.quests[best.quest]
    if best.kind == "grind" then
      st.level, st.xp, sim.level = best.level, 0, best.level
    elseif best.kind == "train" then
      trained = true
    elseif best.kind == "accept" then
      sim.active[q.id] = { simulated = true }
      progress[q.id] = {}
      markFree(q)
    elseif best.kind == "do" then
      progress[q.id][best.index] = true
      -- everything else open close by is done in the same go
      local also = {}
      for qid in pairs(sim.active) do
        local oq = ds.quests[qid]
        local s = oq and consider(oq)
        if s and progress[qid] then
          for i in ipairs(oq.obj or {}) do
            local so = s.objs[i]
            if so and so.targets and not progress[qid][i] then
              local tgt, d = G.Nearest(geo, best.spot, so.targets)
              -- along: worked from best's spot, not its own area
              if d <= o.together then also[#also + 1] = { kind = "do", quest = qid, index = i, spot = tgt, along = true } end
            end
          end
        end
      end
      table.sort(also, function(x, y) if x.quest ~= y.quest then return x.quest < y.quest end return x.index < y.index end)
      best.also = also
      for _, a in ipairs(also) do progress[a.quest][a.index] = true end
    elseif best.kind == "turnin" then
      sim.active[q.id] = nil
      sim.completed[q.id] = true
      simLevel(st, R.QuestXP(q, st.level))
      sim.level = st.level
    end
    pos = { map = best.spot.map, x = best.spot.x, y = best.spot.y }
    best.level = st.level
    steps[#steps + 1] = best
    for _, a in ipairs(best.also or {}) do
      a.level = st.level
      a.spot = best.spot -- worked from the same place
      steps[#steps + 1] = a
    end
    best.also = nil
  end
  return steps
end

-- Why the route does or does not plan a quest for this character (one line).
function R.Why(ds, char, qid)
  local q = ds.quests[qid]
  if not q then return "not in the quest data" end
  local st, why = ns.Availability.Status(q, char)
  if st == "done" then return "already done" end
  if st == "wrong" then return "never for you: " .. tostring(why) end
  if not (q.sn or q.so) then
    if not (char.active and char.active[qid]) then return "starts from an item or inside a dungeon: plannable once in your log" end
  end
  local opens = R.Opens(ds, char)[qid] ~= nil
  local entry = char.active and char.active[qid]
  local s, reason = shape(ds, q, nil, nil, char.pos, opens, entry)
  if not s then return "cannot be planned: " .. tostring(reason) end
  if entry then
    for i in ipairs(q.obj or {}) do
      local so = s.objs[i]
      if so and (so.blocked or so.dungeon) then
        return ("in your log: objective %d is yours to do%s; then it is handed in"):format(i, so.dungeon and " in the dungeon" or "")
      end
    end
    return "plannable (in your log)"
  end
  if st == "locked" or st == "low" then return "plannable once possible: " .. tostring(why) end
  if st == "trivial" then return "plannable, but grey for you (no experience worth the trip)" end
  if q.inst or q.kind == "dungeon" or q.kind == "raid" then return "a dungeon quest: in a dungeon guide (Guides menu)" end
  for _, e in ipairs(q.earlier or {}) do
    local eq = ds.quests[e]
    local es = eq and ns.Availability.Status(eq, char)
    if es == "available" or es == "active" then
      return ("plannable after %s (%d), earlier in its chain, if that one is worth doing: taking this one first shuts it off"):format(eq.n, e)
    end
  end
  return "plannable" .. (st == "active" and " (in your log)" or "")
end

-- Quests in the log the route does not hand in: { { quest, map (where it is handed
-- in, nil when unknown), grey (no experience any more) } }, by quest id. The viewer
-- shows them so nothing in the log disappears from view.
function R.Backlog(ds, char, route)
  local planned = {}
  for _, st in ipairs(route or {}) do
    if st.kind == "turnin" then planned[st.quest] = true end
  end
  local out = {}
  for qid in pairs(char.active or {}) do
    local q = ds.quests[qid]
    if q and not planned[qid] then
      local ends = ns.Quests.TurnIns(ds, q)
      local spot = ends[1]
      out[#out + 1] = { quest = qid, map = spot and spot.map or nil,
        grey = q.l and q.l <= ns.Availability.GreyLevel(char.level or 1) or false }
    end
  end
  table.sort(out, function(a, b) return a.quest < b.quest end)
  return out
end

-- One-line description of a step.
function R.Describe(ds, step)
  if step.kind == "grind" then
    return ("Grind to level %d: %s (about %d kills)"):format(step.level, step.name or "mobs", step.kills or 0)
  end
  if step.kind == "train" then return "Train at " .. (step.name or "your class trainer") end
  local q = ds.quests[step.quest]
  local name = q and q.n or ("quest " .. step.quest)
  if step.kind == "accept" then return "Accept: " .. name end
  if step.kind == "turnin" then return "Turn in: " .. name end
  local o = q and q.obj and q.obj[step.index]
  local what = o and o.text or "objective"
  if o and o.qty and o.qty > 1 then what = what .. " x" .. o.qty end
  return name .. ": " .. what
end

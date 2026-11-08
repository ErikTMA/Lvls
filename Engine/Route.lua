-- Leveling route: an ordered list of accept / do / turn-in steps computed for THIS
-- character from the data, not a hand-written guide. Pure; positions through `geo`.
--
-- Method (first version: greedy simulation).
--   1. Pool: quests within ten levels of the character whose
--      giver, every objective and turn-in can be located. Each gets an efficiency:
--      experience / estimated time (giver -> objective areas -> turn-in, plus the
--      work: kills / drop chance).
--   2. Repeat: from the current position, every possible next action (accept an
--      available quest when the log has room, work an objective of an accepted
--      quest, hand in a finished one) costs travel + work time; the action with the
--      lowest cost / efficiency wins. The cost includes the walk from the action's
--      spot back to the nearest other open work (accepted quests' next targets and
--      the nearest quests that could be picked up), so the route does not leave a
--      quest hub while there is still work in it. Everything at the npc you stand
--      at is done before walking off, and objectives close to the one being worked
--      are worked at the same time (one step: kill these, collect that). Turn-ins add experience (reduced for quests
--      below the simulated level), level the simulation up, and complete the quest,
--      which unlocks its follow-ups through the normal prerequisite rules.
-- With opts.travel (Engine/Travel), long walks are priced by the fastest trip:
-- a known flight path makes a far quest hub cheap.
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
R.MAX_LEVEL = 60

R.DEFAULTS = {
  steps = 40,          -- route length
  logSize = 20,        -- quest log slots
  speed = 7,           -- yards per second on foot
  killSeconds = 15,    -- per kill, including the walk between mobs
  objectSeconds = 15,  -- per object used / looted
  maxSecs = 600,       -- travel seconds; farther actions are left for later
  travelAbove = 90,    -- walks longer than this many seconds ask opts.travel (flights, boats)
  maxAbove = 2,        -- quest level at most this far above the character (mobs too hard)
  here = 20,           -- yards: actions at the npc you stand at come first
  together = 250,      -- yards: open objectives this close are worked at the same time
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

-- Plannable shape of a quest: giver spots, per-objective target clusters, turn-in
-- spots. nil when any part cannot be located.
local function shape(ds, q)
  if not q.xp or q.xp <= 0 then return nil end
  local givers = ns.Quests.Givers(ds, q)
  local ends = ns.Quests.TurnIns(ds, q)
  if #givers == 0 or #ends == 0 then return nil end
  local objs = {}
  for i, o in ipairs(q.obj or {}) do
    if o.t == "faction" or o.t == "spell" then return nil end
    if o.from == "provided" then
      objs[i] = { free = true }
    else
      local spots = ns.Quests.ObjectiveSpots(ds, q, i)
      if #spots == 0 then return nil end
      local clusters = G.Group(spots, 5)
      objs[i] = { targets = clusters, spots = spots }
    end
  end
  return { givers = givers, ends = ends, objs = objs }
end

-- Travel seconds between two spots: walking, or opts.travel (Engine/Travel: flight
-- paths, boats, hearthstone) when the walk is long.
local function travelSecs(o, a, b, d)
  local walk = d / o.speed
  if o.travel and walk > o.travelAbove and walk < math.huge then
    local ok, t = pcall(o.travel, a, b)
    if ok and t and t < walk then return t end
  end
  return walk
end

local function nearestTarget(geo, from, targets)
  local best, d = G.Nearest(geo, from, targets)
  return best, d
end

local function simLevel(st, xpGain)
  st.xp = st.xp + xpGain
  while st.level < R.MAX_LEVEL do
    local need = (st.level == st.char.level and st.char.xpMax) or R.XP_TO_LEVEL[st.level]
    if not need or st.xp < need then break end
    st.xp = st.xp - need
    st.level = st.level + 1
  end
end

function R.Plan(ds, char, geo, opts)
  local o = {}
  for k, v in pairs(R.DEFAULTS) do o[k] = v end
  for k, v in pairs(opts or {}) do o[k] = v end
  local A = ns.Availability
  -- simulated character: same tables, completed / active copied
  local sim = { level = char.level, faction = char.faction, race = char.race, class = char.class,
    skills = char.skills, rep = char.rep, completed = {}, active = {} }
  for k, v in pairs(char.completed) do sim.completed[k] = v end
  for k, v in pairs(char.active or {}) do sim.active[k] = v end
  local st = { level = char.level, xp = char.xp or 0, char = char }
  local pos = char.pos
  if not pos then return {}, "position unknown" end

  -- pool and shapes
  local shapes, eff = {}, {}
  local function consider(q)
    if shapes[q.id] ~= nil then return shapes[q.id] end
    local s = shape(ds, q)
    shapes[q.id] = s or false
    if s then
      local g = s.givers[1]
      local t, here = 0, g
      for i in ipairs(q.obj or {}) do
        local ob = s.objs[i]
        if ob and not ob.free then
          local tgt, d = nearestTarget(geo, here, ob.targets)
          if d == math.huge then shapes[q.id] = false; return false end
          t = t + travelSecs(o, here, tgt, d) + workSeconds(q.obj[i], ob.spots, o)
          here = tgt
        end
      end
      local tin, d = G.Nearest(geo, here, s.ends)
      if d == math.huge then shapes[q.id] = false; return false end
      t = t + travelSecs(o, here, tin, d) + 10
      eff[q.id] = (q.xp or 0) / math.max(30, t)
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

  local steps = {}
  local pool = {}
  for qid, q in pairs(ds.quests) do
    if (q.sn or q.so) and not q.rep and not q.inst and q.kind ~= "dungeon" and q.kind ~= "raid"
      and q.kind ~= "pvp" and (not q.r or q.r <= char.level + 10) then
      pool[#pool + 1] = q
    end
  end
  table.sort(pool, function(a, b) return a.id < b.id end)

  local guard = 0
  while #steps < o.steps and guard < o.steps * 4 do
    guard = guard + 1
    local best, bestScore
    -- open work: the next target of every accepted quest, so an action that leads
    -- away from it pays for the walk back (greedy steps otherwise wander off)
    local pending = {}
    for qid in pairs(sim.active) do
      local q = ds.quests[qid]
      local s = q and consider(q)
      if s and progress[qid] then
        if allDone(q) then
          pending[#pending + 1] = { quest = qid, spot = (G.Nearest(geo, pos, s.ends)) }
        else
          for i in ipairs(q.obj or {}) do
            local so = s.objs[i]
            if so and not so.free and not progress[qid][i] then
              pending[#pending + 1] = { quest = qid, index = i, spot = (nearestTarget(geo, pos, so.targets)) }
            end
          end
        end
      end
    end
    -- quests that could be picked up count as open work too (the nearest few)
    local avail = {}
    if logCount() < o.logSize then
      for _, q in ipairs(pool) do
        if not sim.completed[q.id] and not sim.active[q.id] and (not q.l or q.l <= st.level + o.maxAbove)
          and A.Status(q, sim) == "available" and consider(q) then
          local spot, d = G.Nearest(geo, pos, shapes[q.id].givers)
          local secs = d < math.huge and travelSecs(o, pos, spot, d) or math.huge
          if secs <= o.maxSecs then avail[#avail + 1] = { quest = q.id, spot = spot, d = d, secs = secs } end
        end
      end
      table.sort(avail, function(x, y) if x.d ~= y.d then return x.d < y.d end return x.quest < y.quest end)
      for i = 1, math.min(#avail, 15) do pending[#pending + 1] = avail[i] end
    end
    local function back(action)
      local d = math.huge
      for _, p in ipairs(pending) do
        if p.spot and not (p.quest == action.quest and p.index == action.index) then
          local x = G.Distance(geo, action.spot, p.spot)
          if x < d then d = x end
        end
      end
      if d == math.huge then return 0 end
      return d / o.speed -- the walk back to open work
    end
    -- hand-ins and pick-ups at the npc you stand at always come first
    local here, hereScore
    local function offer(action, score, e)
      if action.kind ~= "do" and G.Distance(geo, pos, action.spot) <= o.here then
        if not hereScore or score < hereScore then here, hereScore = action, score end
        return
      end
      score = score + back(action) / e
      if not bestScore or score < bestScore then best, bestScore = action, score end
    end
    -- hand in / work accepted quests
    for qid in pairs(sim.active) do
      local q = ds.quests[qid]
      local s = q and consider(q)
      if s and progress[qid] then
        local e = eff[qid] or 1e-6
        if allDone(q) then
          local spot, d = G.Nearest(geo, pos, s.ends)
          local secs = d < math.huge and travelSecs(o, pos, spot, d) or math.huge
          if secs <= o.maxSecs then
            offer({ kind = "turnin", quest = qid, spot = spot }, (secs + 5) / e, e)
          end
        else
          for i, ob in ipairs(q.obj or {}) do
            if not progress[qid][i] then
              local so = s.objs[i]
              if so and so.free then
                progress[qid][i] = true
              elseif so then
                local tgt, d = nearestTarget(geo, pos, so.targets)
                local secs = d < math.huge and travelSecs(o, pos, tgt, d) or math.huge
                if secs <= o.maxSecs then
                  offer({ kind = "do", quest = qid, index = i, spot = tgt },
                    (secs + workSeconds(ob, so.spots, o)) / e, e)
                end
              end
            end
          end
        end
      end
    end
    -- accept
    for _, a in ipairs(avail) do
      offer({ kind = "accept", quest = a.quest, spot = a.spot }, (a.secs + 3) / eff[a.quest], eff[a.quest])
    end
    if here then best = here end
    if not best then break end
    local q = ds.quests[best.quest]
    if best.kind == "accept" then
      sim.active[q.id] = { simulated = true }
      progress[q.id] = {}
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
            if so and not so.free and not progress[qid][i] then
              local tgt, d = nearestTarget(geo, best.spot, so.targets)
              if d <= o.together then also[#also + 1] = { kind = "do", quest = qid, index = i, spot = tgt } end
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

-- One-line description of a step.
function R.Describe(ds, step)
  local q = ds.quests[step.quest]
  local name = q and q.n or ("quest " .. step.quest)
  if step.kind == "accept" then return "Accept: " .. name end
  if step.kind == "turnin" then return "Turn in: " .. name end
  local o = q and q.obj and q.obj[step.index]
  local what = o and o.text or "objective"
  if o and o.qty and o.qty > 1 then what = what .. " x" .. o.qty end
  return name .. ": " .. what
end

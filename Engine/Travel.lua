-- Travel: the fastest way from here to a spot, as legs ("Fly to Lakeshire", "Take
-- the boat to Auberdine", "Hearth to Goldshire", "Enter Jasperlode Mine", walk).
-- Pure; everything about the world comes in through ctx:
--
--   ctx.geo        Engine/Geo resolver (world positions, map sizes)
--   ctx.speed      yards per second on foot / mounted
--   ctx.fly        discovered flight points: { { id, name, spot, npc = {kind,id,name} }, ... }
--   ctx.flyTime    function(fromId, toId) -> measured seconds or nil
--   ctx.transit    links: { { a = spot, b = spot, title_ab, title_ba, secs, oneway }, ... }
--   ctx.hearth     { spot, name } when the hearthstone is ready, else nil
--   ctx.entrance   function(spot) -> { spot = entrance, name } when the spot is inside
--                  a cave / building whose way in is known, else nil
--   ctx.path       function(spot) -> { title, points = { spot, ... } } a recorded path
--                  that ends at the spot (up a hill, through a mine), else nil
--
-- Method: Dijkstra over start, goal, flight points, transit ends and the hearth
-- spot. Walking connects any two of them on the same continent (straight line);
-- flights connect discovered flight points on one continent (all of a faction's
-- points are linked there); transit links connect their two ends.
local _, ns = ...
local T = ns:NewModule("Travel")
local G = ns.Geo

T.FLY_SPEED = 25     -- yards per second, straight-line equivalent (routes bend)
T.FLY_OVERHEAD = 20  -- seconds: talk, take off, land
T.HEARTH_SECS = 15   -- cast and loading
T.TRANSIT_SECS = 150 -- waiting and riding when a link has no measured time
T.MIN_SAVING = 30    -- seconds a trip must save over walking to be suggested

local function continent(geo, spot)
  if not geo or not geo.world then return spot.map end
  local c = geo.world(spot.map, spot.x, spot.y)
  return c or spot.map
end

-- Fastest trip. Returns { legs = { { mode, from, to, title, secs } }, secs, walk }.
function T.Plan(from, to, ctx)
  local geo, speed = ctx.geo, ctx.speed or 7
  local nodes = {}
  local function add(n) nodes[#nodes + 1] = n; n.i = #nodes; n.cont = continent(geo, n.spot); return n end
  local start = add({ kind = "start", spot = from })
  local goal = add({ kind = "goal", spot = to })
  local flyNodes = {}
  for _, f in ipairs(ctx.fly or {}) do
    flyNodes[#flyNodes + 1] = add({ kind = "fly", fly = f, spot = f.spot })
  end
  local edges = {} -- [i] = { { j, secs, leg }, ... }
  local function edge(a, b, secs, leg)
    edges[a.i] = edges[a.i] or {}
    table.insert(edges[a.i], { b.i, secs, leg })
  end
  for _, l in ipairs(ctx.transit or {}) do
    local a, b = add({ kind = "transit", spot = l.a }), add({ kind = "transit", spot = l.b })
    local secs = l.secs or T.TRANSIT_SECS
    edge(a, b, secs, { mode = "transit", title = l.title_ab or "Take the boat" })
    if not l.oneway then edge(b, a, secs, { mode = "transit", title = l.title_ba or "Take the boat" }) end
  end
  if ctx.hearth then
    local h = add({ kind = "hearth", spot = ctx.hearth.spot })
    edge(start, h, T.HEARTH_SECS, { mode = "hearth", title = "Hearth to " .. (ctx.hearth.name or "your inn") })
  end
  for i = 1, #flyNodes do
    for j = 1, #flyNodes do
      local a, b = flyNodes[i], flyNodes[j]
      if i ~= j and a.cont == b.cont then
        local secs = ctx.flyTime and ctx.flyTime(a.fly.id, b.fly.id)
        if not secs then secs = G.Distance(geo, a.spot, b.spot) / T.FLY_SPEED + T.FLY_OVERHEAD end
        edge(a, b, secs, { mode = "fly", title = "Fly to " .. (b.fly.name or "?"), npc = a.fly.npc })
      end
    end
  end
  -- walking between everything on the same continent (never out of the goal)
  for _, a in ipairs(nodes) do
    if a ~= goal then
      for _, b in ipairs(nodes) do
        if a ~= b and b ~= start and a.cont == b.cont then
          local d = G.Distance(geo, a.spot, b.spot)
          if d < math.huge then edge(a, b, d / speed, { mode = "walk" }) end
        end
      end
    end
  end
  -- Dijkstra (few dozen nodes: a linear scan is enough)
  local dist, prev, prevLeg, done = {}, {}, {}, {}
  dist[start.i] = 0
  while true do
    local u, best
    for i = 1, #nodes do
      if not done[i] and dist[i] and (not best or dist[i] < best) then u, best = i, dist[i] end
    end
    if not u or u == goal.i then break end
    done[u] = true
    for _, e in ipairs(edges[u] or {}) do
      local v, w = e[1], e[2]
      local nd = best + w
      if not dist[v] or nd < dist[v] then dist[v], prev[v], prevLeg[v] = nd, u, e[3] end
    end
  end
  local walk = G.Distance(geo, from, to) / speed
  if not dist[goal.i] then return { legs = {}, secs = math.huge, walk = walk } end
  local legs = {}
  local v = goal.i
  while prev[v] do
    local u = prev[v]
    local leg = {}
    for k, val in pairs(prevLeg[v]) do leg[k] = val end
    leg.from, leg.to = nodes[u].spot, nodes[v].spot
    leg.secs = dist[v] - dist[u]
    table.insert(legs, 1, leg)
    v = u
  end
  local trip = { legs = legs, secs = dist[goal.i], walk = walk }
  -- a trip that saves too little is not worth the hassle: walk
  if #legs > 1 and walk - trip.secs < T.MIN_SAVING then
    trip = { legs = { { mode = "walk", from = from, to = to, secs = walk } }, secs = walk, walk = walk }
  end
  -- the last walk ends inside a cave whose entrance is known: go to the entrance first
  local last = trip.legs[#trip.legs]
  local inside = ctx.entrance and ctx.entrance(to)
  local here = ctx.entrance and ctx.entrance(from)
  if last and last.mode == "walk" and inside and not (here and here.name == inside.name) then
    local split = G.Distance(geo, last.from, inside.spot) / speed
    trip.legs[#trip.legs] = { mode = "walk", from = last.from, to = inside.spot, secs = split,
      title = "Enter " .. (inside.name or "the cave"), enter = true }
    trip.legs[#trip.legs + 1] = { mode = "walk", from = inside.spot, to = to,
      secs = G.Distance(geo, inside.spot, to) / speed }
  end
  -- a recorded path leads to the goal ("Run up the hill"): follow it from the point
  -- nearest to where you are
  last = trip.legs[#trip.legs]
  local path = ctx.path and ctx.path(to)
  if last and last.mode == "walk" and not last.enter and path and #path.points > 0 then
    local k, kd = nil, math.huge
    for i, pnt in ipairs(path.points) do
      local d = G.Distance(geo, last.from, pnt)
      if d < kd then k, kd = i, d end
    end
    local endD = G.Distance(geo, last.from, to)
    if k and endD > 30 and k < #path.points then
      local legs, at = {}, last.from
      for i = k + 1, #path.points do
        local pnt = path.points[i]
        legs[#legs + 1] = { mode = "walk", from = at, to = pnt, secs = G.Distance(geo, at, pnt) / speed,
          title = path.title or "Follow the path", follow = true }
        at = pnt
      end
      legs[#legs + 1] = { mode = "walk", from = at, to = to, secs = G.Distance(geo, at, to) / speed }
      trip.legs[#trip.legs] = nil
      for _, l in ipairs(legs) do trip.legs[#trip.legs + 1] = l end
    end
  end
  return trip
end

-- Seconds to get there (for the route's costs).
function T.Time(from, to, ctx)
  return T.Plan(from, to, ctx).secs
end

-- What the arrow and the viewer show for a trip: the legs that are not plain walks
-- become lines ("Fly to ...", "Enter ..."); the arrow points at the first leg's end
-- (the flight master, the boat, the cave entrance), or at the goal.
function T.Lines(trip)
  local out = {}
  for _, l in ipairs(trip.legs or {}) do
    if l.mode == "fly" then
      local who = l.npc and l.npc.name
      out[#out + 1] = { kind = "fly", text = (who and ("Talk to " .. who .. ", ") or "") .. l.title:gsub("^F", who and "f" or "F"),
        spot = l.from }
    elseif l.mode == "transit" or l.mode == "hearth" then
      out[#out + 1] = { kind = l.mode, text = l.title, spot = l.from }
    elseif l.enter then
      out[#out + 1] = { kind = "enter", text = l.title, spot = l.to }
    elseif l.follow and not (out[#out] and out[#out].kind == "path") then
      out[#out + 1] = { kind = "path", text = l.title, spot = l.to }
    end
  end
  return out
end

-- Where the arrow should point now: the end of the first leg that is a walk.
-- The title is the first travel line ("Talk to Dungar, fly to Lakeshire") so the
-- arrow says what to do where it points.
function T.NextSpot(trip)
  local l = trip and trip.legs and trip.legs[1]
  if not l then return nil end
  local line = T.Lines(trip)[1]
  local title = line and line.text or l.title
  if l.mode == "walk" then return l.to, title end
  return l.from, title
end

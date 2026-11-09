-- Nav: the way on foot from here to there, around walls, buildings and cliffs.
-- Pure. The graph comes from the client's own map files (a navmesh built
-- offline), shipped per continent in Data/forever/Nav<n>.lua as packed
-- strings (ns.NavData[continent]); positions are world yards (x north, y west), the
-- same as ns.Game.geo.world.
--
-- Nodes are the corners of walkable ways; an edge is a straight walkable line. Its
-- cost is its length times a multiplier that is above 1 where it runs close to a
-- wall, so the way keeps to the middle of streets. A* over that, from the nodes
-- near the start to the nodes near the goal (several of each: on two floors, or
-- either side of a wall, the nearest one is not always the right one).
local _, ns = ...
local N = ns:NewModule("Nav")

N.SNAP_YARDS = 60     -- a start or goal farther than this from the graph: no way
N.SNAP_SLACK = 25     -- also try nodes up to this much farther than the nearest
N.SNAP_MAX = 6        -- at most this many of them
N.TICK = 256          -- nodes between calls to the tick (a job yields there)

local CELL = 64
local OFFSET = 20000
local DIGITS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz+/"
local val = {}
for i = 1, #DIGITS do val[DIGITS:byte(i)] = i - 1 end
local byte, floor, sqrt = string.byte, math.floor, math.sqrt

local function cellKey(cx, cy) return (cx + 1024) * 2048 + (cy + 1024) end

-- A continent's graph with accessors over its strings (nothing decoded up front:
-- a table per node would cost more memory than the strings).
local graphs = {}
function N.Graph(cont)
  local g = graphs[cont]
  if g ~= nil then return g or nil end
  local d = ns.NavData and ns.NavData[cont]
  if not d or not d.nodes then graphs[cont] = false; return nil end
  local nodes, off, adj, w, aw = d.nodes, d.off, d.adj, d.w, d.aw or 3
  g = { n = d.n, cell = d.cell }
  function g.X(i)
    local p = (i - 1) * 8 + 1
    local a, b, c = byte(nodes, p, p + 2)
    return (val[a] * 64 + val[b]) * 64 + val[c] - OFFSET
  end
  function g.Y(i)
    local p = (i - 1) * 8 + 4
    local a, b, c = byte(nodes, p, p + 2)
    return (val[a] * 64 + val[b]) * 64 + val[c] - OFFSET
  end
  function g.Comp(i)
    local p = (i - 1) * 8 + 7
    local a, b = byte(nodes, p, p + 1)
    return val[a] * 64 + val[b]
  end
  -- neighbours of node i are adjacency entries First(i) .. First(i + 1) - 1
  function g.First(i)
    local p = (i - 1) * 4 + 1
    local a, b, c, e = byte(off, p, p + 3)
    return ((val[a] * 64 + val[b]) * 64 + val[c]) * 64 + val[e] + 1
  end
  if aw == 3 then
    function g.Adj(k)
      local p = (k - 1) * 3 + 1
      local a, b, c = byte(adj, p, p + 2)
      return (val[a] * 64 + val[b]) * 64 + val[c] + 1
    end
  else
    function g.Adj(k)
      local p = (k - 1) * 4 + 1
      local a, b, c, e = byte(adj, p, p + 3)
      return ((val[a] * 64 + val[b]) * 64 + val[c]) * 64 + val[e] + 1
    end
  end
  function g.Mult(k) return 1 + val[byte(w, k)] / 7 end
  graphs[cont] = g
  return g
end

-- Forget decoded graphs (tests swap ns.NavData).
function N.Reset() graphs = {} end

-- Nodes near (x, y): the nearest, and the others up to SNAP_SLACK yards farther,
-- nearest first, at most SNAP_MAX. Each { node, yards }. Only nodes of `comps`
-- (a set of components) when given.
function N.Near(g, x, y, comps)
  local found = {}
  local best = math.huge
  local cx, cy = floor(x / CELL), floor(y / CELL)
  local rings = math.ceil((N.SNAP_YARDS + N.SNAP_SLACK) / CELL) + 1
  for r = 0, rings do
    for dx = -r, r do
      for dy = -r, r do
        if math.max(math.abs(dx), math.abs(dy)) == r then
          local i = g.cell[cellKey(cx + dx, cy + dy)]
          while i and i <= g.n do
            local nx, ny = g.X(i), g.Y(i)
            if floor(nx / CELL) ~= cx + dx or floor(ny / CELL) ~= cy + dy then break end
            if not comps or comps[g.Comp(i)] then
              local ex, ey = nx - x, ny - y
              local d = sqrt(ex * ex + ey * ey)
              if d <= N.SNAP_YARDS + N.SNAP_SLACK then
                found[#found + 1] = { i, d }
                if d < best then best = d end
              end
            end
            i = i + 1
          end
        end
      end
    end
    -- everything within reach of the nearest is inside the rings searched so far
    if best <= N.SNAP_YARDS and r * CELL >= best + N.SNAP_SLACK then break end
  end
  if best > N.SNAP_YARDS then return {} end
  table.sort(found, function(a, b) return a[2] < b[2] end)
  local out = {}
  for _, f in ipairs(found) do
    if f[2] > best + N.SNAP_SLACK or #out >= N.SNAP_MAX then break end
    out[#out + 1] = f
  end
  return out
end

-- The way from (ax, ay) to (bx, by) on continent `cont`: { { x, y }, ... } from the
-- start to the goal (both included), and its length in yards. nil and why when
-- there is no graph, either end is off it, or no way connects them on foot.
-- tick() is called every N.TICK nodes (a job yields there).
function N.Route(cont, ax, ay, bx, by, tick)
  local g = N.Graph(cont)
  if not g then return nil, "no map data" end
  local goals = N.Near(g, bx, by)
  if #goals == 0 then return nil, "goal off the map data" end
  local comps = {}
  for _, t in ipairs(goals) do comps[g.Comp(t[1])] = true end
  local starts = N.Near(g, ax, ay, comps)
  if #starts == 0 then return nil, "no way on foot" end
  local X, Y, First, Adj, Mult = g.X, g.Y, g.First, g.Adj, g.Mult
  -- a goal node finishes the way with its own walk to the goal
  local finish, slack = {}, 0
  for _, t in ipairs(goals) do
    finish[t[1]] = t[2]
    if t[2] > slack then slack = t[2] end
  end
  local function h(i)
    local dx, dy = X(i) - bx, Y(i) - by
    local d = sqrt(dx * dx + dy * dy) - slack
    return d > 0 and d or 0
  end
  local cost, came, closed = {}, {}, {}
  local heap, hf, hn = {}, {}, 0
  local function push(i, f)
    hn = hn + 1
    heap[hn], hf[hn] = i, f
    local j = hn
    while j > 1 do
      local p = floor(j / 2)
      if hf[p] <= hf[j] then break end
      heap[p], heap[j], hf[p], hf[j] = heap[j], heap[p], hf[j], hf[p]
      j = p
    end
  end
  local function pop()
    local top, f = heap[1], hf[1]
    heap[1], hf[1] = heap[hn], hf[hn]
    heap[hn], hf[hn] = nil, nil
    hn = hn - 1
    local i = 1
    while true do
      local l, r, m = i * 2, i * 2 + 1, i
      if l <= hn and hf[l] < hf[m] then m = l end
      if r <= hn and hf[r] < hf[m] then m = r end
      if m == i then break end
      heap[i], heap[m], hf[i], hf[m] = heap[m], heap[i], hf[m], hf[i]
      i = m
    end
    return top, f
  end
  for _, s in ipairs(starts) do
    if not cost[s[1]] or s[2] < cost[s[1]] then
      cost[s[1]] = s[2]
      push(s[1], s[2] + h(s[1]))
    end
  end
  local best, bestNode = math.huge, nil
  local count = 0
  while hn > 0 do
    local u, f = pop()
    if f >= best then break end
    if not closed[u] then
      closed[u] = true
      count = count + 1
      if tick and count % N.TICK == 0 then tick() end
      local gu = cost[u]
      if finish[u] and gu + finish[u] < best then best, bestNode = gu + finish[u], u end
      local ux, uy = X(u), Y(u)
      for k = First(u), First(u + 1) - 1 do
        local v = Adj(k)
        if not closed[v] then
          local dx, dy = X(v) - ux, Y(v) - uy
          local nc = gu + sqrt(dx * dx + dy * dy) * Mult(k)
          if not cost[v] or nc < cost[v] then
            cost[v], came[v] = nc, u
            push(v, nc + h(v))
          end
        end
      end
    end
  end
  if not bestNode then return nil, "no way on foot" end
  local nodes, u = {}, bestNode
  while u do
    table.insert(nodes, 1, u)
    u = came[u]
  end
  local pts = { { x = ax, y = ay } }
  for _, i in ipairs(nodes) do pts[#pts + 1] = { x = X(i), y = Y(i) } end
  pts[#pts + 1] = { x = bx, y = by }
  local length = 0
  for i = 2, #pts do
    local dx, dy = pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y
    length = length + sqrt(dx * dx + dy * dy)
  end
  return pts, length, count
end

-- Yards from (px, py) to the segment a-b (points with x, y).
function N.SegmentDistance(px, py, a, b)
  local ax, ay = b.x - a.x, b.y - a.y
  local L = ax * ax + ay * ay
  local t = 0
  if L > 0 then
    t = ((px - a.x) * ax + (py - a.y) * ay) / L
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
  end
  local dx, dy = px - (a.x + t * ax), py - (a.y + t * ay)
  return sqrt(dx * dx + dy * dy)
end

-- Following a way: the index of the point to walk to now, given the last one (i).
-- A point within `reach` yards is reached; so is one close by (within N.PAST yards)
-- that you are already past: closer to the point after it than the point itself is
-- (a start that snapped behind you, a corner you cut). Only close by: around a
-- thin wall, the point after a far corner can be near you on the other side.
N.PAST = 20
function N.Advance(pts, i, px, py, reach)
  while i < #pts do
    local p, q = pts[i], pts[i + 1]
    local dx, dy = p.x - px, p.y - py
    local here = sqrt(dx * dx + dy * dy)
    local ex, ey = q.x - px, q.y - py
    local fx, fy = q.x - p.x, q.y - p.y
    if here <= reach or (here <= N.PAST and sqrt(ex * ex + ey * ey) < sqrt(fx * fx + fy * fy)) then
      i = i + 1
    else
      break
    end
  end
  return i
end

-- Yards left along the way: from (px, py) to point i, then on to the end.
function N.Remaining(pts, i, px, py)
  local p = pts[i]
  if not p then return 0 end
  local dx, dy = p.x - px, p.y - py
  local d = sqrt(dx * dx + dy * dy)
  for k = i + 1, #pts do
    local a, b = pts[k - 1], pts[k]
    local ex, ey = b.x - a.x, b.y - a.y
    d = d + sqrt(ex * ex + ey * ey)
  end
  return d
end

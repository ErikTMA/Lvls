-- Points, spots and distances. Pure: positions in the world come from a `geo`
-- resolver the Game adapter supplies (tests pass a fake):
--   geo.world(uiMap, x, y)  -> continent, wx, wy   (yards; x, y in map percent)
--   geo.size(uiMap)         -> width, height        (yards), optional
local _, ns = ...
local G = ns:NewModule("Geo")

function G.Unpack(p)
  return math.floor(p / 1000) / 10, (p % 1000) / 10
end

function G.Pack(x, y)
  return math.floor(x * 10 + 0.5) * 1000 + math.floor(y * 10 + 0.5)
end

-- Every spawn of an npc ("n") or object ("o") as { map, x, y }; only `onMap` when given.
function G.Spots(ds, kind, id, onMap)
  local rec = (kind == "o" and ds.objects or ds.npcs)[id]
  local out = {}
  if not rec or not rec.p then return out end
  for m, list in pairs(rec.p) do
    if not onMap or m == onMap then
      for _, p in ipairs(list) do
        local x, y = G.Unpack(p)
        out[#out + 1] = { map = m, x = x, y = y }
      end
    end
  end
  return out
end

-- Straight-line yards between two spots, or math.huge when they cannot be compared
-- (different continents, or no resolver for different maps).
function G.Distance(geo, a, b)
  if not a or not b then return math.huge end
  if geo and geo.world then
    local ca, ax, ay = geo.world(a.map, a.x, a.y)
    local cb, bx, by = geo.world(b.map, b.x, b.y)
    if ca and cb then
      if ca ~= cb then return math.huge end
      local dx, dy = ax - bx, ay - by
      return math.sqrt(dx * dx + dy * dy)
    end
  end
  if a.map ~= b.map then return math.huge end
  local w, h = 1000, 1000
  if geo and geo.size then
    local sw, sh = geo.size(a.map)
    if sw and sw > 0 and sh and sh > 0 then w, h = sw, sh end
  end
  local dx, dy = (a.x - b.x) / 100 * w, (a.y - b.y) / 100 * h
  return math.sqrt(dx * dx + dy * dy)
end

function G.Nearest(geo, from, spots)
  local best, bestD = nil, math.huge
  for _, s in ipairs(spots) do
    local d = G.Distance(geo, from, s)
    if d < bestD then best, bestD = s, d end
  end
  return best, bestD
end

-- Greedy grouping of spots on one map: every spot joins the first group whose
-- centre is within `radius` map percent. Returns groups { map, x, y, n } biggest
-- first, so an objective area can be named by its densest spot.
function G.Group(spots, radius)
  radius = radius or 6
  local r2 = radius * radius
  local clusters = {}
  for _, s in ipairs(spots) do
    local hit
    for _, c in ipairs(clusters) do
      if c.map == s.map then
        local dx, dy = c.x - s.x, c.y - s.y
        if dx * dx + dy * dy <= r2 then hit = c; break end
      end
    end
    if hit then
      hit.sx, hit.sy, hit.n = hit.sx + s.x, hit.sy + s.y, hit.n + 1
      hit.x, hit.y = hit.sx / hit.n, hit.sy / hit.n
    else
      clusters[#clusters + 1] = { map = s.map, x = s.x, y = s.y, sx = s.x, sy = s.y, n = 1 }
    end
  end
  table.sort(clusters, function(a, b)
    if a.n ~= b.n then return a.n > b.n end
    if a.map ~= b.map then return a.map < b.map end
    if a.x ~= b.x then return a.x < b.x end
    return a.y < b.y
  end)
  for _, c in ipairs(clusters) do c.sx, c.sy = nil, nil end
  return clusters
end

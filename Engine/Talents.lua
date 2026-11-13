-- Talent builds (pure). A build is the order points are spent in: { name, class,
-- spec = the tree it is built around (1-3), order = { nodeId, nodeId, ... } }, one
-- entry per point, so a talent with 5 ranks shows up 5 times. The order matters: a
-- talent in the same row can come first because it makes leveling easier.
-- The trees come from Data/forever/Talents.lua (the client's trait tables): a talent
-- can take a point when its gates are met (that many points spent in a set of
-- talents), the talents before it are full (all of them; `any`: one is enough) and
-- it has ranks left. The game decides in the end (Adapters/Talents asks it before
-- each point); this is what the editor and the learner plan with.
local _, ns = ...
local T = ns:NewModule("Talents")

T.FIRST_LEVEL = 10 -- the first point (TraitCurrencySource: one per level 10-60)

-- The class's trees: { tree, tabs = { { group, name, nodes } }, sets, byId = { [id] = { node, tab } } }.
function T.Tree(classId, data)
  data = data or ns.TalentData
  local c = data and data[classId]
  if not c then return nil end
  if not c.byId then
    c.byId = {}
    for ti, tab in ipairs(c.tabs) do
      for _, n in ipairs(tab.nodes) do c.byId[n.id] = { node = n, tab = ti } end
    end
  end
  return c
end

function T.MaxPoints(data) return (data or ns.TalentData or {}).points or 51 end

-- Points spent per tree: { a, b, c } from ranks = { [nodeId] = rank }.
function T.Points(tree, ranks)
  local out = {}
  for ti, tab in ipairs(tree.tabs) do
    local n = 0
    for _, node in ipairs(tab.nodes) do n = n + (ranks[node.id] or 0) end
    out[ti] = n
  end
  return out
end

local function spentIn(tree, set, ranks)
  local n = 0
  for _, id in ipairs(tree.sets[set] or {}) do n = n + (ranks[id] or 0) end
  return n
end

-- Can this talent take one more point now? true, or false and why ("Needs 10
-- points in Arms", "Needs Deep Wounds 3/3 first", "Already 5/5").
function T.CanAdd(tree, id, ranks)
  local e = tree.byId[id]
  if not e then return false, "Not a talent of this class" end
  local n = e.node
  if (ranks[id] or 0) >= n.m then return false, ("Already %d/%d"):format(n.m, n.m) end
  for _, g in ipairs(n.g or {}) do
    if spentIn(tree, g[2], ranks) < g[1] then
      return false, ("Needs %d points in %s"):format(g[1], tree.tabs[e.tab].name)
    end
  end
  local pre = n.p or {}
  if #pre > 0 then
    local full, missing = 0, nil
    for _, p in ipairs(pre) do
      local pe = tree.byId[p]
      if pe and (ranks[p] or 0) >= pe.node.m then full = full + 1
      elseif pe and not missing then missing = pe.node end
    end
    if (n.any and full == 0) or (not n.any and full < #pre) then
      local name = missing and ("%s %d/%d"):format(missing.n, missing.m, missing.m) or "the talent before it"
      return false, "Needs " .. name .. " first"
    end
  end
  return true
end

-- Walk a build's order from no points: { { id, rank, ok, why, point } } per entry, and
-- the ranks it ends with. An entry that cannot be taken (ok false) takes no point,
-- so what follows is judged without it.
function T.Simulate(tree, order, data)
  local ranks, steps, point = {}, {}, 0
  local max = T.MaxPoints(data)
  for i, id in ipairs(order or {}) do
    local ok, why = T.CanAdd(tree, id, ranks)
    if ok and point >= max then ok, why = false, ("More than %d points"):format(max) end
    if ok then
      point = point + 1
      ranks[id] = (ranks[id] or 0) + 1
    end
    steps[i] = { id = id, rank = ranks[id] or 0, ok = ok, why = why, point = ok and point or nil }
  end
  return steps, ranks
end

-- The first entry that cannot be taken: index, why. nil when the whole order works.
function T.FirstProblem(tree, order, data)
  for i, s in ipairs((T.Simulate(tree, order, data))) do
    if not s.ok then return i, s.why end
  end
  return nil
end

-- The level a build's point is learned at (point 1: level 10).
function T.Level(point) return T.FIRST_LEVEL + point - 1 end

-- The next point to spend: walk the order counting what it asks of each talent; the
-- first entry the character's ranks do not cover yet is next. Points spent outside
-- the build count for nothing here (they still count for gates). Returns the node id
-- and the entry's index, or nil when the build is done.
function T.Next(order, ranks)
  local need = {}
  for i, id in ipairs(order or {}) do
    need[id] = (need[id] or 0) + 1
    if (ranks[id] or 0) < need[id] then return id, i end
  end
  return nil
end

-- The ranks the build asks of each talent: { [nodeId] = n }.
function T.Wanted(order)
  local out = {}
  for _, id in ipairs(order or {}) do out[id] = (out[id] or 0) + 1 end
  return out
end

-- Editing. Each returns the new order (a copy), or nil and why when it would break
-- the build: a point can only go where the tree allows it at that moment.
local function copy(order)
  local out = {}
  for i, v in ipairs(order or {}) do out[i] = v end
  return out
end

-- One more point in this talent, at the end.
function T.Append(tree, order, id, data)
  local _, ranks = T.Simulate(tree, order, data)
  local ok, why = T.CanAdd(tree, id, ranks)
  if not ok then return nil, why end
  local points = 0
  for _, r in pairs(ranks) do points = points + r end
  if points >= T.MaxPoints(data) then return nil, ("All %d points are spent"):format(T.MaxPoints(data)) end
  local out = copy(order)
  out[#out + 1] = id
  return out
end

-- Swap entry i with its neighbour (dir -1: earlier, 1: later), when both still work.
function T.Move(tree, order, i, dir, data)
  local j = i + dir
  if not (order and order[i] and order[j]) then return nil, "Nothing to swap with" end
  local out = copy(order)
  out[i], out[j] = out[j], out[i]
  local before = T.FirstProblem(tree, order, data)
  local p, why = T.FirstProblem(tree, out, data)
  if p and (not before or p < before) then return nil, why end
  return out
end

-- Take out entry i. What came after it and needed it stays, marked as a problem
-- (T.Simulate) until it is fixed: the rest of the order is not thrown away.
function T.Remove(order, i)
  local out = copy(order)
  table.remove(out, i)
  return out
end

-- The last point in this talent (right-click on the tree): removes its last entry.
function T.RemoveLast(order, id)
  for i = #(order or {}), 1, -1 do
    if order[i] == id then return T.Remove(order, i), i end
  end
  return nil
end

-- An order that gives these ranks (the character's talents now), row by row so each
-- point is allowed where it stands: the start of a build made from what is spent.
function T.FromRanks(tree, ranks)
  local nodes = {}
  for ti, tab in ipairs(tree.tabs) do
    for _, n in ipairs(tab.nodes) do nodes[#nodes + 1] = { n = n, tab = ti } end
  end
  table.sort(nodes, function(a, b)
    if a.n.r ~= b.n.r then return a.n.r < b.n.r end
    if a.tab ~= b.tab then return a.tab < b.tab end
    return a.n.c < b.n.c
  end)
  local have, order = {}, {}
  local progress = true
  while progress do
    progress = false
    for _, e in ipairs(nodes) do
      local id = e.n.id
      while (have[id] or 0) < (ranks[id] or 0) and T.CanAdd(tree, id, have) do
        have[id] = (have[id] or 0) + 1
        order[#order + 1] = id
        progress = true
      end
    end
  end
  return order
end

-- Builds the character can use: its class's, built around that tree when spec is given.
function T.BuildsFor(builds, classId, spec)
  local out = {}
  for _, b in ipairs(builds or {}) do
    if b.class == classId and (not spec or b.spec == spec) then out[#out + 1] = b end
  end
  table.sort(out, function(a, b) return (a.name or ""):lower() < (b.name or ""):lower() end)
  return out
end

-- The tree to preselect when asking: the one with most points, else the class's
-- leveling tree (Gear.SPECS). Only ever a default: the player picks.
function T.Suggested(classToken, points)
  local i = ns.Gear.SpecFromPoints(points)
  if i then return i end
  local specs = ns.Gear.SPECS[classToken]
  return specs and specs.leveling or 1
end

-- Fewer points spent than before: the talents were reset (only a reset takes points
-- back; learning only adds).
function T.WasReset(before, now)
  return type(before) == "number" and type(now) == "number" and now < before
end

-- A name not taken yet among the class's builds: "Arms", "Arms 2", ...
function T.FreeName(builds, classId, base)
  local taken = {}
  for _, b in ipairs(builds or {}) do if b.class == classId then taken[(b.name or ""):lower()] = true end end
  if not taken[base:lower()] then return base end
  for k = 2, 99 do
    local n = ("%s %d"):format(base, k)
    if not taken[n:lower()] then return n end
  end
  return base
end

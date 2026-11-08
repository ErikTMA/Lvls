-- Quest helper queries: what to show on a map, what is near. Pure.
local _, ns = ...
local Q = ns:NewModule("Quests")
local G = ns.Geo

Q.OBJECTIVE_PIN_CAP = 60 -- spots per objective per map

local function addSpots(out, ds, kind, ids, onMap)
  for _, id in ipairs(ids or {}) do
    for _, s in ipairs(G.Spots(ds, kind, id, onMap)) do
      s.kind, s.id = kind, id
      out[#out + 1] = s
    end
  end
  return out
end

function Q.Givers(ds, q, onMap)
  return addSpots(addSpots({}, ds, "n", q.sn, onMap), ds, "o", q.so, onMap)
end

-- Givers of a quest on every map, built once per dataset and shared: read only.
-- (Nearby asks for all quests every time you move.)
local giverCache = setmetatable({}, { __mode = "k" })
function Q.SharedGivers(ds, q)
  local c = giverCache[ds]
  if not c then c = {}; giverCache[ds] = c end
  local g = c[q.id]
  if not g then g = Q.Givers(ds, q); c[q.id] = g end
  return g
end

function Q.TurnIns(ds, q, onMap)
  return addSpots(addSpots({}, ds, "n", q.en, onMap), ds, "o", q.eo, onMap)
end

-- The item that starts a quest without a giver ("Nibbled-On Book"): { id, n, src =
-- { { "n" | "o", id, pct }, ... }, spots } from the dataset (si), else the provider
-- (QuestieDB). nil when the quest has a giver or nothing is known. Cached per
-- dataset and provider.
local startCache = setmetatable({}, { __mode = "k" })
local function starts(ds)
  local p = ns.Prereqs.Provider()
  local c = startCache[ds]
  if not c or c.provider ~= (p or false) then
    c = { provider = p or false, quests = {} }
    startCache[ds] = c
  end
  return c, p
end

function Q.StartItem(ds, q)
  if q.sn or q.so then return nil end
  local c, p = starts(ds)
  local v = c.quests[q.id]
  if v ~= nil then return v or nil end
  local si, ext = q.si, nil
  if p and p.StartItem then
    local ok, r = pcall(p.StartItem, q.id)
    if ok then ext = r end
  end
  if not (si and si.id) and not (ext and ext.id) then c.quests[q.id] = false return nil end
  local out = { id = si and si.id or ext.id, n = si and si.n or ext and ext.n, src = {}, spots = {} }
  for _, s in ipairs(si and si.src or {}) do
    out.src[#out.src + 1] = s
    local kind = s[1] == "o" and "o" or "n"
    for _, sp in ipairs(G.Spots(ds, kind, s[2])) do
      sp.kind, sp.id, sp.pct = kind, s[2], s[3]
      out.spots[#out.spots + 1] = sp
    end
  end
  if #out.src == 0 and ext and ext.id == out.id then
    for _, n in ipairs(ext.npcs or {}) do out.src[#out.src + 1] = { "n", n, 0 } end
    for _, o in ipairs(ext.objects or {}) do out.src[#out.src + 1] = { "o", o, 0 } end
  end
  if #out.spots == 0 and ext and ext.id == out.id then
    for _, sp in ipairs(ext.spots or {}) do out.spots[#out.spots + 1] = sp end
  end
  c.quests[q.id] = out
  return out
end

-- Quests started by items: item id -> { questId, ... } and npc / object -> { questId, ... }
-- (who drops the item), over the quests without a giver.
local function startIndex(ds)
  local c = starts(ds)
  if c.byItem then return c end
  c.byItem, c.byDropper = {}, {}
  for qid, q in pairs(ds.quests) do
    if not q.sn and not q.so then
      local it = Q.StartItem(ds, q)
      if it then
        c.byItem[it.id] = c.byItem[it.id] or {}
        table.insert(c.byItem[it.id], qid)
        for _, s in ipairs(it.src) do
          local k = (s[1] == "o" and "o" or "n") .. s[2]
          c.byDropper[k] = c.byDropper[k] or {}
          table.insert(c.byDropper[k], qid)
        end
      end
    end
  end
  for _, t in ipairs({ c.byItem, c.byDropper }) do
    for _, l in pairs(t) do table.sort(l) end
  end
  return c
end

-- Quests you could start with an item in your bags now: { [questId] = itemId }
-- (char.bag = { [itemId] = true }; not done, not in the log, not wrong for you).
function Q.BagStarts(ds, char)
  local out = {}
  if not char.bag or not next(char.bag) then return out end
  local idx = startIndex(ds)
  for item in pairs(char.bag) do
    for _, qid in ipairs(idx.byItem[item] or {}) do
      local st = ns.Availability.Status(ds.quests[qid], char)
      if st == "available" or st == "trivial" then out[qid] = item end
    end
  end
  return out
end

-- Quests whose starting item this npc ("n") or object ("o") drops.
function Q.StartsDroppedBy(ds, kind, id)
  return startIndex(ds).byDropper[kind .. id] or {}
end

-- Waypoints for objectives the dataset has no source for (Data/forever/Waypoints.lua),
-- for the dataset they were made from: { {map, x, y}, ... } or nil.
function Q.Waypoints(ds, qid, i)
  local w = ns.ObjectiveWaypoints
  if not w or not (ds.meta and ds.meta.generated == w.dataset) then return nil end
  local flat = w[qid] and w[qid][i]
  if not flat then return nil end
  local out = {}
  for k = 1, #flat - 2, 3 do out[#out + 1] = { map = flat[k], x = flat[k + 1], y = flat[k + 2] } end
  return out
end

-- Spots of one objective: its sources from the dataset, else what the prerequisite
-- provider (QuestieDB) knows at runtime, else the shipped waypoints.
function Q.ObjectiveSpots(ds, q, i, onMap)
  local o = q.obj and q.obj[i]
  if not o then return {} end
  local out = {}
  for _, s in ipairs(o.src or {}) do
    local kind = s[1] == "o" and "o" or "n"
    for _, sp in ipairs(G.Spots(ds, kind, s[2], onMap)) do
      sp.kind, sp.id, sp.pct, sp.vendor = kind, s[2], s[3], s[1] == "v" or nil
      out[#out + 1] = sp
    end
  end
  if #out == 0 then
    local p = ns.Prereqs.Provider()
    if p and p.ObjectiveSpots then
      local ok, spots = pcall(p.ObjectiveSpots, q.id, i, o)
      if ok and spots then
        for _, sp in ipairs(spots) do
          if not onMap or sp.map == onMap then out[#out + 1] = sp end
        end
      end
    end
  end
  if #out == 0 then
    for _, sp in ipairs(Q.Waypoints(ds, q.id, i) or {}) do
      if not onMap or sp.map == onMap then sp.waypoint = true; out[#out + 1] = sp end
    end
  end
  return out
end

-- The quest log entry's objective that matches dataset objective i: by text
-- ("Tough Wolf Meat: 3/8" starts with "Tough Wolf Meat"), else by position.
function Q.LogObjective(entry, o, i)
  local list = entry and entry.objectives
  if not list then return nil end
  if o and o.text and o.text ~= "" then
    local want = o.text:lower()
    for _, lo in ipairs(list) do
      if lo.text and lo.text:lower():find(want, 1, true) then return lo end
    end
  end
  return list[i]
end

function Q.ObjectiveDone(entry, o, i)
  if entry and entry.complete then return true end
  local lo = Q.LogObjective(entry, o, i)
  return lo and lo.finished or false
end

local function showStatus(st, opts)
  if st == "available" then return true end
  if st == "low" then return opts.showLow end
  if st == "trivial" then return opts.showTrivial end
  return false
end

local function skipKind(q, opts)
  if (q.inst or q.kind == "dungeon" or q.kind == "raid") and not opts.showDungeon then return true end
  if q.rep and not opts.showRepeatable then return true end
  return false
end

-- Pins for one uiMap:
--   { type = "available" | "low" | "trivial", quest, kind, id, x, y }
--   { type = "turnin" (complete) | "progress" (not yet), quest, kind, id, x, y }
--   { type = "objective", quest, index, kind, id, x, y, pct }
function Q.MapPins(ds, char, uiMap, opts)
  opts = opts or {}
  local pins = {}
  local A = ns.Availability
  -- givers: walk the npcs / objects that start quests and have a spawn on this map
  for kind, starts in pairs(ds.starts) do
    local recs = kind == "o" and ds.objects or ds.npcs
    for id, qids in pairs(starts) do
      local rec = recs[id]
      local pts = rec and rec.p and rec.p[uiMap]
      if pts then
        for _, qid in ipairs(qids) do
          local q = ds.quests[qid]
          if not skipKind(q, opts) then
            local st = A.Status(q, char)
            if showStatus(st, opts) then
              for _, p in ipairs(pts) do
                local x, y = G.Unpack(p)
                pins[#pins + 1] = { type = st, quest = qid, kind = kind, id = id, x = x, y = y }
              end
            end
          end
        end
      end
    end
  end
  for qid, entry in pairs(char.active or {}) do
    local q = ds.quests[qid]
    if q then
      local t = entry.complete and "turnin" or "progress"
      for _, s in ipairs(Q.TurnIns(ds, q, uiMap)) do
        pins[#pins + 1] = { type = t, quest = qid, kind = s.kind, id = s.id, x = s.x, y = s.y }
      end
      if not entry.complete and opts.objectives ~= false then
        for i, o in ipairs(q.obj or {}) do
          if not Q.ObjectiveDone(entry, o, i) then
            local spots = Q.ObjectiveSpots(ds, q, i, uiMap)
            local step = math.max(1, math.ceil(#spots / Q.OBJECTIVE_PIN_CAP))
            for k = 1, #spots, step do
              local s = spots[k]
              pins[#pins + 1] = { type = "objective", quest = qid, index = i, kind = s.kind, id = s.id,
                x = s.x, y = s.y, pct = s.pct, vendor = s.vendor }
            end
          end
        end
      end
    end
  end
  return pins
end

-- Available quests sorted by the distance to their nearest giver from char.pos.
-- Returns { { quest, status, spot, dist }, ... } (at most opts.limit).
function Q.Nearby(ds, char, geo, opts)
  opts = opts or {}
  local out = {}
  local from = char.pos
  for qid, q in pairs(ds.quests) do
    if (q.sn or q.so) and not skipKind(q, opts) then
      local st = ns.Availability.Status(q, char)
      if showStatus(st, opts) then
        local spot, d = G.Nearest(geo, from, Q.SharedGivers(ds, q))
        if spot and (not opts.maxDist or d <= opts.maxDist) then
          out[#out + 1] = { quest = qid, status = st, spot = spot, dist = d }
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.dist ~= b.dist then return a.dist < b.dist end
    return a.quest < b.quest
  end)
  if opts.limit then
    for i = #out, opts.limit + 1, -1 do out[i] = nil end
  end
  return out
end

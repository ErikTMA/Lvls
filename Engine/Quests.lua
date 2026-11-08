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

function Q.TurnIns(ds, q, onMap)
  return addSpots(addSpots({}, ds, "n", q.en, onMap), ds, "o", q.eo, onMap)
end

-- Spots of one objective: its sources from the dataset, else what the prerequisite
-- provider (QuestieDB) knows at runtime.
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
        local spot, d = G.Nearest(geo, from, Q.Givers(ds, q))
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

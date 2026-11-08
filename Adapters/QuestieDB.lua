-- QuestieDB adapter: prerequisites, breadcrumbs, exclusive groups and objective
-- spawns read at runtime from the QuestieDB addon's public API (LibQuestieDB; see
-- its docs/api.md). Nothing of its data is copied into Lvls!.
--
-- API facts relied on (QuestieDB docs/api.md, contract 1):
--   LibQuestieDB.RequireContract(n) -> ok, message
--   QuestDB / NpcDB / ItemDB / ObjectDB = LibQuestieDB.Quest / .Npc / .Item / .Object
--   Entity.Exists(id); Entity.Get(id, fieldName) -> value
--   numbers read 0 when absent (test ~= 0), tables read nil when empty, every table
--   read is a fresh copy, unknown ids read nil.
--   spawns: { [areaId] = { {x, y[, phase]}, ... } } in Forever map percent; an
--   instance spawn is {-1, -1}.
local _, ns = ...
local QD = ns:NewModule("QuestieDB")

QD.CONTRACT = 1
local lib, cache, spotCache = nil, {}, {}

local function nz(v) if type(v) == "number" and v ~= 0 then return v end end
local function list(v)
  if type(v) ~= "table" then return nil end
  local out = {}
  for _, x in ipairs(v) do if type(x) == "number" then out[#out + 1] = x end end
  return #out > 0 and out or nil
end
local function pair(v)
  if type(v) == "table" and type(v[1]) == "number" and v[1] ~= 0 then return { v[1], v[2] } end
end

-- Connect when the addon is present and speaks our contract. Returns ok, reason.
function QD.Connect(G)
  G = G or _G
  local L = G.LibQuestieDB
  if type(L) ~= "table" or type(L.Quest) ~= "table" then
    return false, "QuestieDB not installed"
  end
  if type(L.RequireContract) == "function" then
    local ok, msg = L.RequireContract(QD.CONTRACT)
    if not ok then return false, tostring(msg or "QuestieDB contract mismatch") end
  end
  lib, cache, spotCache = L, {}, {}
  ns.Prereqs.SetProvider(QD)
  return true
end

function QD.Connected() return lib ~= nil end

function QD.Reset()
  lib, cache, spotCache = nil, {}, {}
  ns.Prereqs.SetProvider(nil)
end

local function get(entity, id, key)
  local ok, v = pcall(entity.Get, id, key)
  if ok then return v end
end

local function exists(entity, id)
  if type(entity.Exists) == "function" then
    local ok, v = pcall(entity.Exists, id)
    return ok and v
  end
  return get(entity, id, "name") ~= nil
end

-- Prerequisite info in the shape Engine/Prereqs expects; nil for an unknown quest.
function QD.Info(qid)
  if not lib then return nil end
  local c = cache[qid]
  if c ~= nil then return c or nil end
  local Q = lib.Quest
  if not exists(Q, qid) then cache[qid] = false; return nil end
  local info = {
    group = list(get(Q, qid, "preQuestGroup")),
    single = list(get(Q, qid, "preQuestSingle")),
    excl = list(get(Q, qid, "exclusiveTo")),
    breadcrumbFor = nz(get(Q, qid, "breadcrumbForQuestId")),
    maxLevel = nz(get(Q, qid, "requiredMaxLevel")),
    skill = pair(get(Q, qid, "requiredSkill")),
    minRep = pair(get(Q, qid, "requiredMinRep")),
    parent = nz(get(Q, qid, "parentQuest")),
    -- QuestieDB corrects Wowhead here (forever's "A Scribbled Letter" is a hunter
    -- quest, Wowhead says warrior): its masks win when it has them
    classes = nz(get(Q, qid, "requiredClasses")),
    races = nz(get(Q, qid, "requiredRaces")),
  }
  cache[qid] = info
  return info
end

-- spawns table -> { {map, x, y}, ... } through the dataset's area -> uiMap table
local function spawnSpots(spawns, out)
  local ds = ns.ActiveDataset and ns.ActiveDataset()
  local zones = ds and ds.zones or {}
  if type(spawns) ~= "table" then return out end
  for area, pts in pairs(spawns) do
    local m = zones[area]
    if m and type(pts) == "table" then
      for _, p in ipairs(pts) do
        local x, y = p[1], p[2]
        if type(x) == "number" and type(y) == "number" and x >= 0 and y >= 0 then
          out[#out + 1] = { map = m, x = x, y = y }
        end
      end
    end
  end
  return out
end

local function entitySpots(kind, id, out)
  local e = kind == "o" and lib.Object or lib.Npc
  local before = #out
  spawnSpots(get(e, id, "spawns"), out)
  for k = before + 1, #out do out[k].kind, out[k].id = kind, id end
  return out
end

local function pack(x, y) return math.floor(x * 10 + 0.5) * 1000 + math.floor(y * 10 + 0.5) end

-- An npc / object QuestieDB places, added to the dataset when the dataset has no
-- spot for it: true when it has one now.
local function adopt(ds, kind, id)
  local t = kind == "o" and ds.objects or ds.npcs
  local rec = t[id]
  if rec and rec.p and next(rec.p) then return true end
  local e = kind == "o" and lib.Object or lib.Npc
  local spots = spawnSpots(get(e, id, "spawns"), {})
  if #spots == 0 then return false end
  rec = rec or {}
  if not rec.n then
    local n = get(e, id, "name")
    rec.n = type(n) == "string" and n or nil
  end
  rec.p = {}
  for _, s in ipairs(spots) do
    rec.p[s.map] = rec.p[s.map] or {}
    table.insert(rec.p[s.map], pack(s.x, s.y))
  end
  t[id] = rec
  return true
end

-- QuestieDB's Forever data over the dataset's where they differ. The quest dump
-- carries Season of Discovery values for quests Forever changed: the paladin chain
-- "Return to Delgren" is level 25 / required 1 in the dump, 30 / 22 in Forever
-- (and QuestieDB). Also givers the dump lacks ("A Strange Artifact" starts at the
-- Strange Orb in Darkshore). Once per dataset; returns how many quests changed.
function QD.Patch(ds)
  if not lib or not ds or ds.questiedbPatched == lib then return 0 end
  ds.questiedbPatched = lib
  local Q, changed = lib.Quest, 0
  for qid, q in pairs(ds.quests) do
    if exists(Q, qid) then
      local touched = false
      local l, r = nz(get(Q, qid, "questLevel")), nz(get(Q, qid, "requiredLevel"))
      if l and l > 0 and l ~= q.l then q.l, touched = l, true end
      if r and r > 0 and r ~= q.r then q.r, touched = r, true end
      if not q.sn and not q.so then
        local sb = get(Q, qid, "startedBy")
        if type(sb) == "table" then
          local sn, so = {}, {}
          for _, n in ipairs(list(sb[1]) or {}) do if adopt(ds, "n", n) then sn[#sn + 1] = n end end
          for _, o in ipairs(list(sb[2]) or {}) do if adopt(ds, "o", o) then so[#so + 1] = o end end
          if #sn > 0 then q.sn, touched = sn, true end
          if #so > 0 then q.so, touched = so, true end
        end
      end
      if touched then changed = changed + 1 end
    end
  end
  return changed
end

-- The item that starts a quest (startedBy's third list) and where it drops:
-- { id, n, npcs, objects, spots } or nil. Forever's new quests are often only here
-- (Nibbled-On Book: dropped by Kobold Vermin, Workers and Laborers).
function QD.StartItem(qid)
  if not lib then return nil end
  local key = "si:" .. qid
  local c = spotCache[key]
  if c ~= nil then return c or nil end
  local sb = get(lib.Quest, qid, "startedBy")
  local items = type(sb) == "table" and list(sb[3])
  local item = items and items[1]
  if not item then spotCache[key] = false return nil end
  local I = lib.Item
  local out = { id = item, spots = {} }
  if I then
    local n = get(I, item, "name")
    out.n = type(n) == "string" and n or nil
    out.npcs = list(get(I, item, "npcDrops"))
    out.objects = list(get(I, item, "objectDrops"))
  end
  for _, n in ipairs(out.npcs or {}) do entitySpots("n", n, out.spots) end
  for _, o in ipairs(out.objects or {}) do entitySpots("o", o, out.spots) end
  spotCache[key] = out
  return out
end

-- Runtime fallback for an objective the dataset cannot locate.
function QD.ObjectiveSpots(qid, i, o)
  if not lib or not o then return nil end
  local key = qid .. ":" .. i
  if spotCache[key] then return spotCache[key] end
  local out = {}
  if o.t == "kill" and o.id then
    entitySpots("n", o.id, out)
  elseif o.t == "object" and o.id then
    entitySpots("o", o.id, out)
  elseif o.t == "item" and o.id and lib.Item then
    for _, n in ipairs(list(get(lib.Item, o.id, "npcDrops")) or {}) do entitySpots("n", n, out) end
    for _, b in ipairs(list(get(lib.Item, o.id, "objectDrops")) or {}) do entitySpots("o", b, out) end
    if #out == 0 then
      for _, v in ipairs(list(get(lib.Item, o.id, "vendors")) or {}) do entitySpots("n", v, out) end
      for _, s in ipairs(out) do s.vendor = true end
    end
  elseif o.t == "event" then
    local trig = get(lib.Quest, qid, "triggerEnd")
    if type(trig) == "table" then spawnSpots(trig[2], out) end
  end
  spotCache[key] = out
  return out
end

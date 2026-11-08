-- Class quest guides: the class quest chains of this character's class, which one
-- has just become possible (to ask about), and a chain's quests as a guide. Pure.
--
-- A class quest is one for one to three classes (QuestieDB's mask when it has one,
-- else the dataset's). Chains are the class quests linked to each other through
--   the series (prev / next), provider prerequisites (group, single) and
--   breadcrumbs, and, where the data has no link (the weapon you choose at the end
--   is often its own quest): a quest whose giver is the npc an earlier class quest
--   ends at, within LINK_LEVELS levels.
-- A chain is named after its last quest (usually the reward: "Heirloom Weapon").
local _, ns = ...
local CQ = ns:NewModule("ClassQuests")
local A, P = ns.Availability, ns.Prereqs

CQ.LINK_LEVELS = 5
CQ.ASK_MIN = 2 -- quests in reach before a chain is worth asking about
CQ.SLACK = 5    -- without a required level: this many levels below its level

-- The level a class quest can be taken from: its required level. Only when the data
-- has none (1, or missing: the dump without QuestieDB says 1 for Return to Delgren)
-- its level less SLACK.
function CQ.MinLevel(q)
  if q.r and q.r > 1 then return q.r end
  return math.max(1, (q.l or 1) - CQ.SLACK)
end

local function bits(m)
  local n = 0
  while m > 0 do
    if m % 2 == 1 then n = n + 1 end
    m = math.floor(m / 2)
  end
  return n
end

function CQ.Mask(q)
  local info = P.Info(q.id)
  return info and info.classes or q.classes
end

function CQ.IsClassQuest(q)
  local m = CQ.Mask(q)
  return type(m) == "number" and m > 0 and bits(m) <= 3
end

-- Class quest chains for this character: { id, name, quests = { ids by level },
-- open (not done), reach (open ones your level allows), available (one can be
-- picked up now), entry (the first of those), minLevel (of the open ones), raid,
-- after = { [id] = the class quest it follows, where only the npc links them } }
-- open chains only, by level. A chain grows in parts as you level (the druid's
-- bear, then aquatic, then cat form); it is named after the last quest in reach,
-- else its last quest.
function CQ.Chains(ds, char)
  local members = {}
  for id, q in pairs(ds.quests) do
    if CQ.IsClassQuest(q) and A.Status(q, char) ~= "wrong" then members[id] = q end
  end
  local parent = {}
  local function find(x)
    while parent[x] and parent[x] ~= x do x = parent[x] end
    return x
  end
  local function union(a, b)
    if not members[a] or not members[b] then return end
    local ra, rb = find(a), find(b)
    if ra ~= rb then
      if ra < rb then parent[rb] = ra else parent[ra] = rb end
    end
  end
  for id in pairs(members) do parent[id] = parent[id] or id end
  local after = {} -- id -> the class quest it follows (linked through the npc only)
  local linkedIn = {} -- ids the data links to an earlier quest
  local function before(a, b) -- a comes before b
    local la, lb = ds.quests[a].l or 0, ds.quests[b].l or 0
    if la ~= lb then return la < lb end
    return a < b
  end
  local enders = {} -- npc / object id -> class quests that end there
  for id, q in pairs(members) do
    for _, n in ipairs(q.en or {}) do enders["n" .. n] = enders["n" .. n] or {}; table.insert(enders["n" .. n], id) end
    for _, o in ipairs(q.eo or {}) do enders["o" .. o] = enders["o" .. o] or {}; table.insert(enders["o" .. o], id) end
  end
  for id, q in pairs(members) do
    if q.prev then union(id, q.prev) end
    if q.next then union(id, q.next) end
    local info = P.Info(id)
    local linked = q.prev and members[q.prev]
    if info then
      for _, p in ipairs(info.group or {}) do union(id, p); linked = linked or members[p] end
      for _, p in ipairs(info.single or {}) do union(id, p); linked = linked or members[p] end
      if info.breadcrumbFor then union(id, info.breadcrumbFor) end
    end
    linkedIn[id] = linked and true or nil
    if not linked then
      -- no link in the data: the class quest that ends where this one starts
      local function from(key)
        for _, other in ipairs(enders[key] or {}) do
          local oq = members[other]
          if other ~= id and math.abs((oq.l or 0) - (q.l or 0)) <= CQ.LINK_LEVELS and (oq.l or 0) <= (q.l or 0) then
            union(id, other)
            -- the npc offers it once the earlier one is handed in: the latest one before it
            if before(other, id) and (not after[id] or before(after[id], other)) then after[id] = other end
          end
        end
      end
      for _, n in ipairs(q.sn or {}) do from("n" .. n) end
      for _, o in ipairs(q.so or {}) do from("o" .. o) end
    end
  end
  local by = {}
  for id in pairs(members) do
    local r = find(id)
    by[r] = by[r] or {}
    table.insert(by[r], id)
  end
  local out = {}
  for root, ids in pairs(by) do
    table.sort(ids, before)
    local open, available, minLevel, entry, raid = 0, false, nil, nil, false
    local reach, links = {}, {}
    for i, id in ipairs(ids) do
      local q = ds.quests[id]
      if q.kind == "raid" then raid = true end
      -- nothing links it to an earlier quest: it follows the one before it in the chain
      if i > 1 and not linkedIn[id] and not after[id] then after[id] = ids[i - 1] end
      links[id] = after[id]
      if not char.completed[id] then
        open = open + 1
        local r = CQ.MinLevel(q)
        local inReach = r <= (char.level or 1)
        if inReach and A.Status(q, char) == "available" and not (after[id] and not char.completed[after[id]]) then
          available = true
          entry = entry or id
        end
        minLevel = math.min(minLevel or r, r)
        if inReach then reach[#reach + 1] = id end
      end
    end
    if open > 0 then
      local last = reach[#reach] or ids[#ids]
      out[#out + 1] = { id = root, quests = ids, open = open, reach = reach, available = available, entry = entry,
        minLevel = minLevel or 1, raid = raid, name = ds.quests[last].n, after = links }
    end
  end
  table.sort(out, function(a, b)
    if a.minLevel ~= b.minLevel then return a.minLevel < b.minLevel end
    return a.id < b.id
  end)
  return out
end

function CQ.Find(ds, char, id)
  for _, c in ipairs(CQ.Chains(ds, char)) do
    if c.id == id then return c end
  end
  return nil
end

-- The key a question is remembered by: the chain and the quest that opened it, so
-- a later part of the same chain is asked about again.
function CQ.AskKey(chain) return chain.id .. ":" .. tostring(chain.entry) end

-- The chain to ask about now: one can be picked up, at least ASK_MIN quests in
-- reach, not a raid's, not asked about before (asked = { [AskKey] = true }).
function CQ.ToAsk(ds, char, asked)
  for _, c in ipairs(CQ.Chains(ds, char)) do
    if c.available and #c.reach >= CQ.ASK_MIN and not c.raid and not (asked and asked[CQ.AskKey(c)]) then return c end
  end
  return nil
end

-- A chain as a guide: its quests in reach and what leads to them (Dungeons.Closure).
-- The parts for later levels are a later guide. focus: what the route may plan now
-- (a quest that follows another one only through its npc waits until that is done).
function CQ.Set(ds, char, chain)
  local g = ns.Dungeons.Closure(ds, char, chain.reach)
  g.chain = chain.id
  g.after = chain.after or {}
  g.focus = {}
  for id in pairs(g.set) do
    local prev = g.after[id]
    if not prev or char.completed[prev] or (char.active and char.active[id]) then g.focus[id] = true end
  end
  return g
end

local function npcName(ds, list)
  local n = list and list[1] and ds.npcs[list[1]]
  return n and n.n
end

local function giverName(ds, q)
  local n = npcName(ds, q.sn)
  if n then return " from " .. n end
  local o = q.so and q.so[1] and ds.objects[q.so[1]]
  return o and o.n and (" at the " .. o.n) or ""
end

-- What the route could not place yet, as a last step (nil when nothing): quests of
-- the guide neither done, in the log, nor planned, each with why and where.
function CQ.Step(ds, char, guide, name, planned)
  planned = planned or {}
  local lines, spot = {}, nil
  local after = guide.after or {}
  for _, id in ipairs(guide.order) do
    local q = ds.quests[id]
    if q and not char.completed[id] and not (char.active and char.active[id]) and not planned[id] then
      local where = giverName(ds, q)
      local text
      local prev = after[id] and ds.quests[after[id]]
      local st, why = A.Status(q, char)
      if CQ.MinLevel(q) > (char.level or 1) then
        text = ("From level %d: %s%s"):format(CQ.MinLevel(q), q.n, where)
      elseif prev and not char.completed[prev.id] then
        text = ("After %s: pick up %s%s"):format(prev.n, q.n, where)
      elseif st == "locked" or st == "low" then
        text = ("%s (%s first)"):format(q.n, why or "something else")
      elseif not (q.sn or q.so) then
        local ender = npcName(ds, q.en)
        text = ("%s starts from an item you find%s"):format(q.n, ender and (", for " .. ender) or "")
      else
        text = "Pick up " .. q.n .. where
        if not spot then spot = ns.Quests.Givers(ds, q)[1] end
      end
      lines[#lines + 1] = { kind = "accept", quest = id, text = text }
    end
  end
  if #lines == 0 then return nil end
  return { kind = "classrest", title = "Next in " .. (name or "the class quest"), spot = spot, lines = lines }
end

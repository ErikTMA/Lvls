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
-- Repeatable quests are no part of one (the shaman's "Earth Sapta": a lost sapta
-- again): nobody does them on the way, so they would keep a done chain open.
local _, ns = ...
local CQ = ns:NewModule("ClassQuests")
local A, P = ns.Availability, ns.Prereqs

-- Class names and colours (the client's class colours), by class id.
CQ.CLASSES = {
  [1] = { "Warrior", "C79C6E" }, [2] = { "Paladin", "F58CBA" }, [3] = { "Hunter", "ABD473" },
  [4] = { "Rogue", "FFF569" }, [5] = { "Priest", "FFFFFF" }, [7] = { "Shaman", "0070DE" },
  [8] = { "Mage", "69CCF0" }, [9] = { "Warlock", "9482C9" }, [11] = { "Druid", "FF7D0A" },
}

-- " [Paladin]" in the class colour after a class quest's name, "" for other quests.
function CQ.Tag(q, char)
  local c = char and CQ.CLASSES[char.class]
  if not c or not q or not CQ.IsClassQuest(q) then return "" end
  return (" |cff%s[%s]|r"):format(c[2], c[1])
end

CQ.LINK_LEVELS = 5
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

-- The chain graph of a faction / race / class, built once (Engine/GuideCache):
-- { list = { { id (lowest quest id, stable), quests = ids in order, after, raid } },
--   of = { [quest id] = chain } }. Members are the class quests that are for this
-- character at all (Availability.Fixed); a quest that becomes impossible later (an
-- exclusive one taken) stays in the graph and is skipped per call, so a chain keeps
-- its id and its links.
local function graph(ds, char)
  local members = {}
  for id, q in pairs(ds.quests) do
    local info = P.Info(id)
    if CQ.IsClassQuest(q) and not A.Fixed(q, char) and not q.rep and not (info and info.repeatable) then
      members[id] = q
    end
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
  local list, of = {}, {}
  for root, ids in pairs(by) do
    table.sort(ids, before)
    local links, raid = {}, false
    for i, id in ipairs(ids) do
      if ds.quests[id].kind == "raid" then raid = true end
      -- nothing links it to an earlier quest: it follows the one before it in the chain
      if i > 1 and not linkedIn[id] and not after[id] then after[id] = ids[i - 1] end
      links[id] = after[id]
    end
    local c = { id = root, quests = ids, after = links, raid = raid }
    list[#list + 1] = c
    for _, id in ipairs(ids) do of[id] = c end
  end
  table.sort(list, function(a, b) return a.id < b.id end)
  return { list = list, of = of }
end

function CQ.Graph(ds, char) return ns.GuideCache.Get(ds, char, "classChains", graph) end

-- Class quest chains for this character: { id, name, quests = { ids by level },
-- open (not done), reach (open ones your level allows), available (one can be
-- picked up now), entry (the first of those), minLevel (of the open ones), raid,
-- after = { [id] = the class quest it follows, where only the npc links them } }
-- open chains only, by level. A chain grows in parts as you level (the druid's
-- bear, then aquatic, then cat form); it is named after the last quest in reach,
-- else its last quest. The graph comes from the cache (CQ.Graph); this part is
-- what this character has done and can do. A quest that became impossible is left
-- out, and a quest that followed it follows the one before it instead.
function CQ.Chains(ds, char)
  local out = {}
  for _, g in ipairs(CQ.Graph(ds, char).list) do
    local status = {}
    local function st(id)
      local s = status[id]
      if not s then s = A.Status(ds.quests[id], char); status[id] = s end
      return s
    end
    local function follows(id)
      local p, guard = g.after[id], 0
      while p and st(p) == "wrong" and guard < 64 do p, guard = g.after[p], guard + 1 end
      return p
    end
    local ids, links, reach = {}, {}, {}
    local open, available, minLevel, entry = 0, false, nil, nil
    for _, id in ipairs(g.quests) do
      if st(id) ~= "wrong" then
        ids[#ids + 1] = id
        local prev = follows(id)
        links[id] = prev
        if not char.completed[id] then
          open = open + 1
          local q = ds.quests[id]
          local r = CQ.MinLevel(q)
          local inReach = r <= (char.level or 1)
          if inReach and st(id) == "available" and not (prev and not char.completed[prev]) then
            available = true
            entry = entry or id
          end
          minLevel = math.min(minLevel or r, r)
          if inReach then reach[#reach + 1] = id end
        end
      end
    end
    if open > 0 then
      local last = reach[#reach] or ids[#ids]
      out[#out + 1] = { id = g.id, quests = ids, open = open, reach = reach, available = available, entry = entry,
        minLevel = minLevel or 1, raid = g.raid, name = ds.quests[last].n, after = links }
    end
  end
  table.sort(out, function(a, b)
    if a.minLevel ~= b.minLevel then return a.minLevel < b.minLevel end
    return a.id < b.id
  end)
  return out
end

-- A chain by id. An id saved before chains were cached may be another member of
-- the chain than its lowest one: then the chain that quest is in.
function CQ.Find(ds, char, id)
  local chains = CQ.Chains(ds, char)
  for _, c in ipairs(chains) do
    if c.id == id then return c end
  end
  local g = id and CQ.Graph(ds, char).of[id]
  if g and g.id ~= id then
    for _, c in ipairs(chains) do
      if c.id == g.id then return c end
    end
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

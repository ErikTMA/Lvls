-- Leveling buffs (Data/forever/Buffs.lua): an item a quest
-- chain gives you whose use raises the experience you earn, like the Cozy Sleeping
-- Bag. Lvls! wants it for you: from the chain's level every step has a line to get
-- it (click: its guide), and once it is yours a line to use it while its buff is
-- missing (its item on the item bar). Right-click either line: Lvls! stops wanting
-- it (`ignore[item]` = "get" or "use"); /lvls unskip buffs takes them back. Pure.
--
-- The chain is the reward quest and what leads to it in the data: each quest's
-- `prev`, and every quest whose `next` it is (two starts, one per faction, lead to
-- the same quest). Quests that are not for you (the other faction's start) drop out.
--
-- From the client (Adapters/Buffs.lua), on the character:
--   char.buffs { [aura spell id] = { stacks, left = seconds } } (missing: not on you)
--   char.cooldowns { [item id] = seconds left } (missing: ready)
local _, ns = ...
local B = ns:NewModule("Buffs")
local A = ns.Availability

B.RENEW = 600 -- a buff with less than this left is to be used again
B.FOOD_RENEW = 60 -- and Well Fed (15 minutes) with less than this
B.FOOD = "food" -- the ignore key of the reminder to eat (ignore[B.FOOD] = "use")

-- Food whose Well Fed adds experience from kills (Data/forever/Buffs.lua BuffFood):
-- { boost, xp, lasts, auras, items = { [item] = required level } }, or nil.
function B.Food() return ns.BuffFood end

-- The food in your bags to eat for the boost: the one for the highest level you
-- may eat (the most stats), nil when none.
function B.FoodToEat(char)
  local f = B.Food()
  if not f or not char.bag then return nil end
  local best, bestLevel
  for item, lvl in pairs(f.items) do
    if char.bag[item] and lvl <= (char.level or 1) and (not best or lvl > bestLevel or (lvl == bestLevel and item < best)) then
      best, bestLevel = item, lvl
    end
  end
  return best
end

-- Well Fed with the boost on you: its seconds left (true when unknown), nil when not.
function B.WellFed(char)
  local f = B.Food()
  for _, a in ipairs(f and f.auras or {}) do
    local on = char.buffs and char.buffs[a]
    if on then return on.left or true end
  end
  return nil
end

function B.List() return ns.BuffData or {} end

function B.Find(item)
  for _, b in ipairs(B.List()) do if b.item == item then return b end end
  return nil
end

-- "+3% experience for 2 hours"
function B.Gain(b)
  local pct = (b.xp or 0) * (b.stacks or 1)
  local h = (b.lasts or 0) / 3600
  local lasts = h >= 1 and (h == math.floor(h) and ("%d hour%s"):format(h, h == 1 and "" or "s") or ("%.1f hours"):format(h))
    or ("%d minutes"):format(math.floor((b.lasts or 0) / 60))
  return ("+%d%% experience for %s"):format(pct, lasts)
end

-- "rest on it 3 minutes" for a rest buff, else "use it"
function B.How(b)
  if b.use == "rest" then
    local n = b.stacks or 1
    return ("rest on it %d minute%s"):format(n, n == 1 and "" or "s")
  end
  return "use it"
end

local leadsTo = setmetatable({}, { __mode = "k" })
local function nextIndex(ds)
  local idx = leadsTo[ds]
  if idx then return idx end
  idx = {}
  for id, q in pairs(ds.quests) do
    if q.next then idx[q.next] = idx[q.next] or {}; table.insert(idx[q.next], id) end
  end
  for _, l in pairs(idx) do table.sort(l) end
  leadsTo[ds] = idx
  return idx
end

-- The chain to a buff as a class quest chain (Engine/ClassQuests: Set and Step take
-- it): { id = the reward quest, name = the item, quests = ids first to last, after,
-- open, reach, minLevel, buff }. nil when the data has no reward quest for you.
function B.Chain(ds, char, b)
  local last = ds.quests[b.quest]
  if not last or A.Fixed(last, char) then return nil end
  local idx = nextIndex(ds)
  local depth, after, seen = {}, {}, {}
  local function walk(id, d)
    if seen[id] or d > 32 then return end
    local q = ds.quests[id]
    if not q then return end
    seen[id] = true
    if A.Fixed(q, char) then return end
    depth[id] = d
    local before = {}
    if q.prev then before[#before + 1] = q.prev end
    for _, p in ipairs(idx[id] or {}) do before[#before + 1] = p end
    for _, p in ipairs(before) do
      walk(p, d + 1)
      if depth[p] and not after[id] then after[id] = p end
    end
  end
  walk(b.quest, 0)
  local ids = {}
  for id in pairs(depth) do ids[#ids + 1] = id end
  table.sort(ids, function(x, y)
    if depth[x] ~= depth[y] then return depth[x] > depth[y] end
    return x < y
  end)
  local open, reach, minLevel = 0, {}, nil
  local level = char.level or 1
  for _, id in ipairs(ids) do
    if not char.completed[id] then
      open = open + 1
      local r = ns.ClassQuests.MinLevel(ds.quests[id])
      minLevel = math.min(minLevel or r, r)
      if r <= level then reach[#reach + 1] = id end
    end
  end
  return { id = b.quest, name = b.name, quests = ids, after = after, open = open, reach = reach,
    minLevel = minLevel or 1, buff = b }
end

local function owned(char, b)
  return (char.bag and char.bag[b.item]) or char.completed[b.quest]
end

-- What Lvls! wants you to do about each buff now, for the step lines:
-- { { kind = "get", buff, chain } | { kind = "use", buff }, ... }.
--   get: not yours, its chain open and in reach, not ignored
--   use: in your bags, its buff missing or running out (B.RENEW), the item ready
--   eat: food in your bags whose Well Fed adds experience (B.Food), not Well Fed
--        (or under B.FOOD_RENEW left), not ignored (ignore[B.FOOD]): { kind, item }
function B.Wanted(ds, char, ignore)
  ignore = ignore or {}
  local out = {}
  for _, b in ipairs(B.List()) do
    if not owned(char, b) then
      if not ignore[b.item] then
        local c = B.Chain(ds, char, b)
        if c and c.open > 0 and #c.reach > 0 then out[#out + 1] = { kind = "get", buff = b, chain = c } end
      end
    elseif char.bag and char.bag[b.item] and ignore[b.item] ~= "use" then
      local on = char.buffs and char.buffs[b.aura]
      local full = on and (on.stacks or 1) >= (b.stacks or 1)
      local fresh = on and (on.left == nil or on.left > B.RENEW)
      local ready = not (char.cooldowns and (char.cooldowns[b.item] or 0) > 0)
      -- a rest buff is built up a stack a minute: short of its stacks it wants more
      local good = fresh and (full or b.use ~= "rest")
      if ready and not good then
        out[#out + 1] = { kind = "use", buff = b }
      end
    end
  end
  local food = ignore[B.FOOD] ~= "use" and B.FoodToEat(char)
  if food then
    local left = B.WellFed(char)
    if not left or (left ~= true and left <= B.FOOD_RENEW) then
      out[#out + 1] = { kind = "eat", item = food, name = char.itemNames and char.itemNames[food] }
    end
  end
  return out
end

-- "+5% experience from kills for 15 minutes" (the food's boost)
function B.FoodGain()
  local f = B.Food()
  return ("+%d%% experience from kills for %d minutes"):format(f.xp, math.floor(f.lasts / 60))
end

-- A want as a step line (UI/Viewer adds it under the step's own lines).
function B.Line(w)
  if w.kind == "eat" then
    return { kind = "buff", want = "use", item = B.FOOD, use = w.item,
      text = ("Eat %s 10 seconds: %s"):format(w.name or "your food", B.FoodGain()) }
  end
  local b = w.buff
  if w.kind == "get" then
    return { kind = "buff", want = "get", item = b.item, chain = w.chain.id,
      text = ("Get the %s: %s (%d quest%s)"):format(b.name, B.Gain(b), w.chain.open, w.chain.open == 1 and "" or "s") }
  end
  return { kind = "buff", want = "use", item = b.item,
    text = ("%s: %s, %s"):format(b.name, B.How(b), B.Gain(b)) }
end

-- The items to use (Engine/UseItems' shape) for the item bar.
function B.Items(wanted)
  local out = {}
  for _, w in ipairs(wanted or {}) do
    if w.kind == "eat" then
      out[#out + 1] = { id = w.item, kind = "use", text = "Eat 10 seconds: " .. B.FoodGain() }
    elseif w.kind == "use" then
      out[#out + 1] = { id = w.buff.item, kind = "use", text = ("%s: %s"):format(B.How(w.buff):gsub("^%l", string.upper), B.Gain(w.buff)) }
    end
  end
  return out
end

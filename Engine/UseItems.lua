-- Items to use, for the item bar (UI/ItemBar.lua): what is in your bags that starts
-- a quest, the quest log's own item for a quest (the client's "special" item: a
-- torch to burn the tents, a rod to use on the crystal, a whistle at the place),
-- and items a quest gives you that can be used. Pure.
--
-- From the client (Adapters/Game.lua), on the character:
--   char.bag      { [itemId] = true }
--   char.bagInfo  { [itemId] = { starts = questId (a quest item whose quest you do
--                    not have), use = true (the item has a use) } }
--   char.active[questId].item = the quest log's item, .itemDone = shown also when
--                    the quest is complete
--
-- The order: what the current step needs first, then what starts a quest, then the
-- items of the quests in the order the route does them; quests the route does not
-- do (yet) last.
local _, ns = ...
local UI = ns:NewModule("UseItems")

UI.MAX = 8

local function provided(q)
  local out = {}
  for _, id in ipairs(q and q.provided or {}) do out[#out + 1] = id end
  for _, o in ipairs(q and q.obj or {}) do
    if o.from == "provided" and o.id then out[#out + 1] = o.id end
  end
  return out
end

-- The items you use for a quest in your log: { itemId, ... }
function UI.ForQuest(ds, char, qid)
  local a = char.active and char.active[qid]
  if not a then return {} end
  local out, seen = {}, {}
  local function add(id) if id and not seen[id] then seen[id] = true; out[#out + 1] = id end end
  if a.item and (not a.complete or a.itemDone) then add(a.item) end
  if not a.complete then
    local info = char.bagInfo or {}
    for _, id in ipairs(provided(ds.quests[qid])) do
      if char.bag and char.bag[id] and info[id] and info[id].use then add(id) end
    end
  end
  return out
end

-- quest id -> where it first comes in the steps from `index` on: step, then line
local function routeOrder(steps, index)
  local at, n = {}, 0
  for i = index or 1, #(steps or {}) do
    for _, l in ipairs(steps[i].lines or {}) do
      n = n + 1
      if l.quest and not at[l.quest] then at[l.quest] = n end
    end
  end
  return at
end

local function name(ds, qid)
  local q = ds.quests[qid]
  return q and q.n or ("quest " .. qid)
end

-- { { id = itemId, quest = questId, kind = "start" | "use", text }, ... }, at most
-- `max` (UI.MAX).
function UI.List(ds, char, steps, index, max)
  local out, seen = {}, {}
  local at = routeOrder(steps, index)
  local cur = steps and index and steps[index]
  local function add(id, qid, kind, rank)
    if not id or seen[id] then return end
    seen[id] = true
    out[#out + 1] = { id = id, quest = qid, kind = kind, rank = rank,
      text = (kind == "start" and "Starts: " or "For: ") .. name(ds, qid) }
  end
  -- the current step: a "Use X from your bags" step, its quests' items
  if cur then
    if cur.item and char.bag and char.bag[cur.item] then
      local l = cur.lines and cur.lines[1]
      add(cur.item, l and l.quest, cur.kind == "use" and "start" or "use", 0)
    end
    for _, l in ipairs(cur.lines or {}) do
      if l.quest and not l.done then
        for _, id in ipairs(UI.ForQuest(ds, char, l.quest)) do add(id, l.quest, "use", 0) end
      end
    end
  end
  local rest = {}
  -- items that start a quest: the dataset knows them, or the client says so
  local starts = {}
  for qid, item in pairs(ns.Quests.BagStarts(ds, char)) do starts[#starts + 1] = { qid, item } end
  for item, info in pairs(char.bagInfo or {}) do
    local qid = info.starts
    if qid and char.bag and char.bag[item] and not (char.active and char.active[qid])
      and not (char.completed and char.completed[qid]) then
      local q = ds.quests[qid]
      if not q or ns.Availability.Status(q, char) ~= "wrong" then starts[#starts + 1] = { qid, item } end
    end
  end
  for _, s in ipairs(starts) do
    rest[#rest + 1] = { id = s[2], quest = s[1], kind = "start", rank = 1, at = at[s[1]] or math.huge }
  end
  -- the quests in your log
  for qid in pairs(char.active or {}) do
    for _, id in ipairs(UI.ForQuest(ds, char, qid)) do
      rest[#rest + 1] = { id = id, quest = qid, kind = "use", rank = 2, at = at[qid] or math.huge }
    end
  end
  table.sort(rest, function(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    if a.at ~= b.at then return a.at < b.at end
    if a.quest ~= b.quest then return a.quest < b.quest end
    return a.id < b.id
  end)
  for _, r in ipairs(rest) do add(r.id, r.quest, r.kind, r.rank) end
  max = max or UI.MAX
  while #out > max do out[#out] = nil end
  return out
end

-- A key that changes when the list does (the bar is rebuilt only then: it cannot
-- be changed in combat, so it should not change for nothing).
function UI.Key(list)
  local parts = {}
  for i, it in ipairs(list) do parts[i] = it.id .. ":" .. (it.quest or 0) end
  return table.concat(parts, ",")
end

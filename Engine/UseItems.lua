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
-- Only the current step's items: a quest's item shows while the step is doing that
-- quest, a start item on its "use it" step.
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

local function name(ds, qid)
  local q = ds.quests[qid]
  return q and q.n or ("quest " .. qid)
end

-- { { id = itemId, quest = questId, kind = "start" | "use", text }, ... }, at most
-- `max` (UI.MAX). Only the current step's: an item shows while you do its quest.
function UI.List(ds, char, steps, index, max)
  local out, seen = {}, {}
  local cur = steps and index and steps[index]
  local function add(id, qid, kind)
    if not id or seen[id] then return end
    seen[id] = true
    out[#out + 1] = { id = id, quest = qid, kind = kind,
      text = (kind == "start" and "Starts: " or "For: ") .. (qid and name(ds, qid) or "this step") }
  end
  if not cur then return out end
  -- a "Use X from your bags" step
  if cur.item and char.bag and char.bag[cur.item] then
    local l = cur.lines and cur.lines[1]
    add(cur.item, l and l.quest, cur.kind == "use" and "start" or "use")
  end
  for _, l in ipairs(cur.lines or {}) do
    -- "Use Odd Tome from your bags" on this step
    if l.item and l.kind == "accept" and not l.done and char.bag and char.bag[l.item] then
      add(l.item, l.quest, "start")
    end
    if l.quest and not l.done then
      for _, id in ipairs(UI.ForQuest(ds, char, l.quest)) do add(id, l.quest, "use") end
    end
  end
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

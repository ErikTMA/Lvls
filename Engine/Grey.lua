-- Grey quests in your log: no longer worth experience, they only take up slots.
-- The viewer's trash can abandons them all; with the setting on, Lvls! offers to
-- abandon the ones that are far away (UI/Abandon.lua). Pure.
--
-- How far a quest is: the travel time to where you would go next for it. Finished:
-- its hand-in. Not finished: its objectives not done yet (none known: the hand-in).
-- The nearest of those counts, so a quest you stand next to is never "far".
local _, ns = ...
local G = ns:NewModule("Grey")

G.MAX_SPOTS = 12 -- the nearest spots of a quest (straight line) that are timed

-- Is this log entry grey for you? The dataset's level, else the log's.
function G.IsGrey(ds, char, qid, entry)
  local q = ds.quests[qid]
  local lv = (q and q.l) or (entry and entry.level)
  return type(lv) == "number" and lv > 0 and lv <= ns.Availability.GreyLevel(char.level or 1)
end

-- The grey quests in the log, by id.
function G.List(ds, char)
  local out = {}
  for qid, entry in pairs(char.active or {}) do
    if G.IsGrey(ds, char, qid, entry) then out[#out + 1] = qid end
  end
  table.sort(out)
  return out
end

-- Where you go next for a quest in the log (see the top).
function G.Spots(ds, char, qid)
  local q = ds.quests[qid]
  if not q then return {} end
  local entry = char.active and char.active[qid]
  local out = {}
  if not (entry and entry.complete) then
    for i in ipairs(q.obj or {}) do
      if not ns.Quests.ObjectiveDone(entry, q.obj[i], i) then
        for _, sp in ipairs(ns.Quests.ObjectiveSpots(ds, q, i)) do out[#out + 1] = sp end
      end
    end
  end
  if #out == 0 then out = ns.Quests.TurnIns(ds, q) end
  return out
end

-- Seconds from where you stand to the nearest of them (math.huge: no way there,
-- another continent on foot); nil when that is not known (no position, no spot).
-- travel(from, to) -> seconds; nil: walking (speed, yards/s).
function G.Seconds(ds, char, qid, geo, travel, speed)
  local from = char.pos
  if not from then return nil end
  local D = ns.Geo.Distance
  local near = {}
  for _, sp in ipairs(G.Spots(ds, char, qid)) do near[#near + 1] = { sp = sp, d = D(geo, from, sp) } end
  if #near == 0 then return nil end
  table.sort(near, function(a, b) return a.d < b.d end)
  local best = math.huge
  for i = 1, math.min(#near, G.MAX_SPOTS) do
    local n = near[i]
    local secs = travel and travel(from, n.sp) or n.d / (speed or 7)
    if secs and secs < best then best = secs end
  end
  return best
end

-- The grey quests at least `secs` away, nearest first ({ quest, secs }). One whose
-- distance is not known is left alone: it may be next to you.
function G.Far(ds, char, secs, geo, travel, speed)
  local out = {}
  for _, qid in ipairs(G.List(ds, char)) do
    local s = G.Seconds(ds, char, qid, geo, travel, speed)
    if s and s >= secs then out[#out + 1] = { quest = qid, secs = s } end
  end
  table.sort(out, function(a, b) return a.secs < b.secs end)
  return out
end

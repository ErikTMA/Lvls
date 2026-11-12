-- Notes: a word on where an npc or object stands that the map cannot show ("At the
-- top of the tower", "On the top floor of the inn"), as in a hand-written guide.
-- Pure.
--
-- Map positions have no height, and nothing in the data says which floor a
-- quest giver is on, so a note is written by a person: the shipped ones
-- (Data/forever/Travel.lua, notes = { n = { [npcId] = text }, o = { [objectId] = text } })
-- and your own (/lvls note <text>, kept in LvlsDB.notes the same way). Yours win.
--
-- Comment notes: what the players' comments on Wowhead's pages say the map does not
-- (upstairs in the inn, hidden behind the tent, the cave's way in, patrols, respawns),
-- one sentence each, best voted first (Data/forever/Comments.lua). They
-- come after a written note: on the step's npc / object, on its quests and on what
-- their open objectives name (the mob, the object, the item).
local _, ns = ...
local N = ns:NewModule("Notes")

N.MAX = 80 -- characters: a note is one line in the viewer and under the arrow

local function own() return ns.db and ns.db.notes end
local function shipped() return ns.TravelShipped and ns.TravelShipped.notes end

-- The note on npc ("n") / object ("o") `id`, or nil.
function N.Get(kind, id)
  if (kind ~= "n" and kind ~= "o") or not id then return nil end
  local mine, ours = own(), shipped()
  return (mine and mine[kind] and mine[kind][id]) or (ours and ours[kind] and ours[kind][id]) or nil
end

N.STEP_MAX = 3    -- note lines on a step in the viewer
N.ARROW_MAX = 100 -- characters of a comment note under the arrow (one line, no wrap)
-- tags that say where a thing is, not what happens there: these go under the arrow
N.PLACE = { floor = true, inside = true, hidden = true }

-- The comment notes on npc "n" / object "o" / quest "q" / item "i" `id`: { { text,
-- v (votes), tags = "floor inside" }, ... } best voted first, or an empty list.
local NONE = {}
function N.Comments(kind, id)
  local c = ns.CommentNotes
  return (id and c and c[kind] and c[kind][id]) or NONE
end

-- Has comment note `c` one of the tags in `set`?
function N.Tagged(c, set)
  for t in (c.tags or ""):gmatch("%S+") do
    if set[t] then return true end
  end
  return false
end

-- The written note on what stands at a step's spot ({ kind, id }), or nil.
function N.ForSpot(spot)
  return spot and N.Get(spot.kind, spot.id) or nil
end

-- The line under the arrow at a spot: the written note, else the best voted comment
-- note on where it stands (floor, inside, hidden) short enough for one line.
function N.ForArrow(spot)
  local note = N.ForSpot(spot)
  if note or not spot or (spot.kind ~= "n" and spot.kind ~= "o") then return note end
  for _, c in ipairs(N.Comments(spot.kind, spot.id)) do
    if N.Tagged(c, N.PLACE) and #c.text <= N.ARROW_MAX then return c.text end
  end
  return nil
end

-- The first map position a note gives ("at about 76,75", "79.21, 69.03", a range
-- "53-56, 58-59" is its middle): x, y in 0..100, or nil. Numbers of three digits
-- ("1,000 gold") or past 100 are not a position.
local function num(p)
  return tonumber(p:match("^%d%d?$") or p:match("^%d%d?%.%d+$") or "")
end
local function part(p)
  p = p:gsub("%.+$", "")
  local lo, hi = p:match("^([%d%.]+)%-([%d%.]+)$")
  local v
  if lo then
    lo, hi = num(lo), num(hi)
    v = lo and hi and (lo + hi) / 2
  else
    v = num(p)
  end
  return v and v <= 100 and v or nil
end
function N.Coord(text)
  for a, b in tostring(text or ""):gmatch("(%d[%d%.%-]*)%s*,%s*(%d[%d%.%-]*)") do
    local x, y = part(a), part(b)
    if x and y then return x, y end
  end
  return nil
end

-- What a step line names: the entities whose comment notes belong to it.
local OBJ_KIND = { kill = "n", object = "o", item = "i" }
local function named(ds, l, out)
  local q = l.quest and ds and ds.quests and ds.quests[l.quest]
  if l.quest then out[#out + 1] = { "q", l.quest } end
  local o = q and l.index and q.obj and q.obj[l.index]
  if o and OBJ_KIND[o.t] then out[#out + 1] = { OBJ_KIND[o.t], o.id } end
  if l.starter then out[#out + 1] = { "i", l.starter } end
  if l.item then out[#out + 1] = { "i", l.item } end
end

-- The note lines of a step: the written note on its spot first, then the best voted
-- comment notes on its spot, its quests and their open objectives (lines done or
-- only "also here" are not this step's work), at most N.STEP_MAX, none twice.
function N.ForStep(ds, st)
  local out, seen = {}, {}
  if not st then return out end
  local written = N.ForSpot(st.spot)
  if written then out[1] = written; seen[written] = true end
  local about = {}
  if st.spot and (st.spot.kind == "n" or st.spot.kind == "o") then about[1] = { st.spot.kind, st.spot.id } end
  for _, l in ipairs(st.lines or NONE) do
    if not l.done and not l.also then named(ds, l, about) end
  end
  local cand, from = {}, {}
  for _, a in ipairs(about) do
    local key = a[1] .. a[2]
    if not from[key] then
      from[key] = true
      for _, c in ipairs(N.Comments(a[1], a[2])) do cand[#cand + 1] = c end
    end
  end
  table.sort(cand, function(a, b) return a.v > b.v end)
  for _, c in ipairs(cand) do
    if #out >= N.STEP_MAX then break end
    if not seen[c.text] then seen[c.text] = true; out[#out + 1] = c.text end
  end
  return out
end

-- Tidy a note as typed: one line, trimmed, at most N.MAX characters; nil when empty.
function N.Clean(text)
  text = tostring(text or ""):gsub("[\r\n|]+", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
  if text == "" then return nil end
  if #text > N.MAX then text = text:sub(1, N.MAX) end
  return text
end

-- Write your own note on npc / object `id` (text nil or empty: remove yours, the
-- shipped one shows again). The note kept, or nil.
function N.Set(db, kind, id, text)
  if (kind ~= "n" and kind ~= "o") or not id or not db then return nil end
  text = N.Clean(text)
  db.notes = db.notes or {}
  db.notes[kind] = db.notes[kind] or {}
  db.notes[kind][id] = text
  return text
end

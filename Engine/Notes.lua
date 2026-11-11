-- Notes: a word on where an npc or object stands that the map cannot show ("At the
-- top of the tower", "On the top floor of the inn"), as in a hand-written guide.
-- Pure.
--
-- Map positions have no height, and nothing in the data says which floor a
-- quest giver is on, so a note is written by a person: the shipped ones
-- (Data/forever/Travel.lua, notes = { n = { [npcId] = text }, o = { [objectId] = text } })
-- and your own (/lvls note <text>, kept in LvlsDB.notes the same way). Yours win.
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

-- The note on what stands at a step's spot ({ kind, id }), or nil.
function N.ForSpot(spot)
  return spot and N.Get(spot.kind, spot.id) or nil
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

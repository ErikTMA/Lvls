-- Group sync, pure part: what a group member's state looks like on the wire, and
-- which quests you are missing compared to them (with everything needed before
-- them). The messages themselves: Adapters/GroupSync.lua.
--
-- State: level, faction, class, race, the quests in the log and the completed ones.
-- Completed quests go as a bitset over the dataset's quest ids in ascending order
-- (6000 quests: about 1000 characters), so both sides need the same dataset: its
-- fingerprint goes along and a mismatch is refused.
--
-- Missing (for you, compared to a member): quests they completed or have in their
-- log that you have neither done nor have, can still do (not wrong for you), are at
-- most ABOVE levels above you, are not repeatable, and are not grey for you unless
-- they have it in their log (then you need it to do it together). The catch-up
-- guide: those and everything leading to them (Dungeons.Closure).
local _, ns = ...
local S = ns:NewModule("Sync")

S.PROTOCOL = 1
S.ABOVE = 3
S.ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local DEC = {}
for i = 1, #S.ALPHABET do DEC[S.ALPHABET:sub(i, i)] = i - 1 end

-- Sorted quest ids of a dataset, cached.
local idsCache = setmetatable({}, { __mode = "k" })
function S.Ids(ds)
  local ids = idsCache[ds]
  if ids then return ids end
  ids = {}
  for id in pairs(ds.quests) do ids[#ids + 1] = id end
  table.sort(ids)
  idsCache[ds] = ids
  return ids
end

-- Which dataset: quest count and generation time (both sides must match).
function S.Fingerprint(ds)
  return #S.Ids(ds) .. "@" .. tostring(ds.meta and ds.meta.generated or "?")
end

-- completed set -> string, 6 quests per character
function S.Encode(ds, set)
  local ids, out = S.Ids(ds), {}
  for i = 1, #ids, 6 do
    local v = 0
    for b = 0, 5 do
      local id = ids[i + b]
      if id and set[id] then v = v + 2 ^ b end
    end
    out[#out + 1] = S.ALPHABET:sub(v + 1, v + 1)
  end
  return table.concat(out)
end

function S.Decode(ds, str)
  local ids, set = S.Ids(ds), {}
  for c = 1, #str do
    local v = DEC[str:sub(c, c)]
    if not v then return nil end
    local base = (c - 1) * 6
    for b = 0, 5 do
      if v % 2 == 1 then
        local id = ids[base + b + 1]
        if id then set[id] = true end
      end
      v = math.floor(v / 2)
    end
  end
  return set
end

-- One member's state as one string (sent in chunks): fields separated by ";".
function S.State(ds, char)
  local active = {}
  for id in pairs(char.active or {}) do active[#active + 1] = id end
  table.sort(active)
  return table.concat({ S.PROTOCOL, S.Fingerprint(ds), char.level or 1, char.faction or "?", char.class or 0,
    char.race or 0, table.concat(active, ","), S.Encode(ds, char.completed or {}) }, ";")
end

-- The other way; nil and a reason when it cannot be used.
function S.ParseState(ds, str)
  local f = {}
  for part in (str .. ";"):gmatch("([^;]*);") do f[#f + 1] = part end
  if tonumber(f[1]) ~= S.PROTOCOL then return nil, "protocol" end
  if f[2] ~= S.Fingerprint(ds) then return nil, "dataset" end
  local active = {}
  for id in (f[7] or ""):gmatch("%d+") do active[tonumber(id)] = true end
  local completed = S.Decode(ds, f[8] or "")
  if not completed then return nil, "data" end
  return { level = tonumber(f[3]) or 1, faction = f[4], class = tonumber(f[5]), race = tonumber(f[6]),
    active = active, completed = completed }
end

-- Quests you could catch up on, compared to one member (sorted ids).
function S.Missing(ds, me, peer)
  local A = ns.Availability
  local out, seen = {}, {}
  local grey = A.GreyLevel(me.level or 1)
  local function consider(id, inLog)
    if seen[id] then return end
    seen[id] = true
    local q = ds.quests[id]
    if not q or q.rep or me.completed[id] or (me.active and me.active[id]) then return end
    if q.l and q.l > (me.level or 1) + S.ABOVE then return end
    if not inLog and q.l and q.l <= grey then return end
    local st = A.Status(q, me)
    if st == "wrong" or st == "done" or st == "active" then return end
    out[#out + 1] = id
  end
  for id in pairs(peer.active or {}) do consider(id, true) end
  for id in pairs(peer.completed or {}) do consider(id, false) end
  table.sort(out)
  return out
end

-- The catch-up guide for you: what you are missing compared to the member, and
-- everything needed before it.
function S.Set(ds, me, peer)
  local g = ns.Dungeons.Closure(ds, me, S.Missing(ds, me, peer))
  g.sync = true
  return g
end

-- A step as a line of text for the members who follow (title, spot, lines).
function S.StepText(st)
  if not st then return "" end
  local lines = {}
  for i, l in ipairs(st.lines or {}) do
    if i > 4 then break end
    lines[#lines + 1] = (l.done and "+" or "-") .. (l.text or ""):gsub("[|~]", "")
  end
  local sp = st.spot
  return table.concat({ (st.title or ""):gsub("[|~]", ""), sp and sp.map or "", sp and ("%.1f"):format(sp.x) or "",
    sp and ("%.1f"):format(sp.y) or "", table.concat(lines, "~") }, "|")
end

function S.ParseStep(text)
  local title, map, x, y, lines = text:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.*)$")
  if not title then return nil end
  local st = { kind = "follow", title = title, lines = {} }
  if tonumber(map) then st.spot = { map = tonumber(map), x = tonumber(x) or 0, y = tonumber(y) or 0 } end
  for l in (lines .. "~"):gmatch("([^~]*)~") do
    if l ~= "" then st.lines[#st.lines + 1] = { kind = "follow", text = l:sub(2), done = l:sub(1, 1) == "+" } end
  end
  return st
end

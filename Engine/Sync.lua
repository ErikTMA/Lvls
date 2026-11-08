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

-- Is quest id one you could catch up on, compared to a member? (see S.Missing)
local function eligible(ds, me, peer, id, grey)
  local inLog = peer.active and peer.active[id]
  if not inLog and not (peer.completed and peer.completed[id]) then return false end
  local q = ds.quests[id]
  if not q or q.rep or me.completed[id] or (me.active and me.active[id]) then return false end
  if q.l and q.l > (me.level or 1) + S.ABOVE then return false end
  if not inLog and q.l and q.l <= grey then return false end
  local st = ns.Availability.Status(q, me)
  return st ~= "wrong" and st ~= "done" and st ~= "active"
end

-- Quests you could catch up on, compared to one member (sorted ids).
function S.Missing(ds, me, peer)
  local out, seen = {}, {}
  local grey = ns.Availability.GreyLevel(me.level or 1)
  local function consider(id)
    if seen[id] then return end
    seen[id] = true
    if eligible(ds, me, peer, id, grey) then out[#out + 1] = id end
  end
  for id in pairs(peer.active or {}) do consider(id) end
  for id in pairs(peer.completed or {}) do consider(id) end
  table.sort(out)
  return out
end

-- quest id -> quests that its being done or taken makes impossible (provider
-- `excl`, and breadcrumbs that lead to it), cached (Engine/GuideCache)
local function buildExcludes(ds, char)
  local by = {}
  local function add(id, other)
    by[id] = by[id] or {}
    table.insert(by[id], other)
  end
  for id in pairs(ds.quests) do
    local info = ns.Prereqs.Info(id)
    if info then
      for _, e in ipairs(info.excl or {}) do add(e, id) end
      if info.breadcrumbFor then add(info.breadcrumbFor, id) end
    end
  end
  return by
end

-- Per member: what you are missing compared to them and the catch-up guide, kept
-- and updated from what changed (their new state, your hand-ins), not rebuilt.
-- Rebuilt only when something every quest depends on changed: the dataset, the
-- provider, your level, faction, race, class or skills.
local layers = {}
S.stats = { full = 0, updates = 0, closures = 0 }

function S.Forget(name)
  if name then layers[name] = nil else layers = {} end
end

local function copy(t)
  local c = {}
  for k, v in pairs(t or {}) do c[k] = v end
  return c
end

local function skillsSig(me)
  local parts = {}
  for k, v in pairs(me.skills or {}) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end
  table.sort(parts)
  return table.concat(parts, ",")
end

-- ids in a or b whose presence differs between them, into out
local function diff(a, b, out)
  a, b = a or {}, b or {}
  for id in pairs(a) do if not b[id] then out[id] = true end end
  for id in pairs(b) do if not a[id] then out[id] = true end end
end

local function sorted(set)
  local out = {}
  for id in pairs(set) do out[#out + 1] = id end
  table.sort(out)
  return out
end

local function closure(ds, me, missing)
  S.stats.closures = S.stats.closures + 1
  local g = ns.Dungeons.Closure(ds, me, sorted(missing))
  g.sync = true
  return g
end

-- The catch-up guide for you: what you are missing compared to the member, and
-- everything needed before it. With the member's name the result is kept and
-- updated on the next call; without it, worked out from scratch.
function S.Set(ds, me, peer, name)
  if not name then
    local g = ns.Dungeons.Closure(ds, me, S.Missing(ds, me, peer))
    g.sync = true
    return g
  end
  local sig = table.concat({ tostring(ds), ns.Prereqs.generation, me.level or 1, tostring(me.faction),
    tostring(me.race), tostring(me.class), skillsSig(me) }, ";")
  local L = layers[name]
  if not L or L.sig ~= sig then
    S.stats.full = S.stats.full + 1
    local missing = {}
    for _, id in ipairs(S.Missing(ds, me, peer)) do missing[id] = true end
    L = { sig = sig, peer = peer, completed = copy(me.completed), active = copy(me.active), missing = missing }
    L.g = closure(ds, me, missing)
    layers[name] = L
    return L.g
  end
  local mine, theirs = {}, {}
  diff(L.completed, me.completed, mine)
  diff(L.active, me.active, mine)
  if peer ~= L.peer then
    diff(L.peer.completed, peer.completed, theirs)
    diff(L.peer.active, peer.active, theirs)
  end
  if not next(mine) and not next(theirs) then
    L.peer = peer
    return L.g
  end
  S.stats.updates = S.stats.updates + 1
  -- what to look at again: what changed, and what your change made impossible
  local excludes = ns.GuideCache.Get(ds, me, "excludes", buildExcludes)
  local look = {}
  for id in pairs(theirs) do look[id] = true end
  for id in pairs(mine) do
    look[id] = true
    for _, other in ipairs(excludes[id] or {}) do look[other] = true end
  end
  local grey = ns.Availability.GreyLevel(me.level or 1)
  local changed = false
  for id in pairs(look) do
    local now = eligible(ds, me, peer, id, grey) or nil
    if now ~= L.missing[id] then
      L.missing[id] = now
      changed = true
    end
  end
  L.peer, L.completed, L.active = peer, copy(me.completed), copy(me.active)
  -- what leads up to the missing quests depends on what you have done
  if changed or next(mine) then L.g = closure(ds, me, L.missing) end
  return L.g
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

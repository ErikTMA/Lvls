-- Gather: what players see in the game, kept to share (/lvls share) so the shipped
-- data can be fixed from many players' play, the way Questie gathers its database.
-- Pure: Adapters/Gather.lua feeds it from the game's events.
--
-- Kept in LvlsDB.gather (every character of the install adds to it):
--   id            a random id for the install (no name, realm or account): the
--                 upload service keeps the newest snapshot per id
--   n / o [id]    where an npc / object was met: { [cell] = times }, cell =
--                 map * 1e6 + x10 * 1000 + y10 (the dataset's 0.1 % packing)
--   qs / qe [q]   who starts / ends a quest: { ["n123"|"o45"] = times }
--   qo [q][i]     what moved objective i on: { ["n123"|"o45"] = times }
--   ql [q]        the quest as the log has it: { lv = level, t = title }
--   sk            quests skipped in the route: { { q, map, x, y, at }, ... }
-- Each is capped (G.CELLS a thing, G.IDS things, G.SKIPS skips) so a long-played
-- install stays a string you can paste.
local _, ns = ...
local G = ns:NewModule("Gather")

G.VERSION = 1
G.CELLS = 12      -- places kept per npc / object (the most seen stay)
G.IDS = 20000     -- npcs, objects and quests kept per table
G.SKIPS = 300
G.PREFIX = "LVLS1:"
G.URL = "https://eriktma.github.io/Lvls/share/"

local floor = math.floor

local function count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

-- a fresh id: 16 letters and digits
function G.NewId(rand)
  rand = rand or math.random
  local d = "abcdefghijklmnopqrstuvwxyz0123456789"
  local out = {}
  for i = 1, 16 do
    local k = rand(1, #d)
    out[i] = d:sub(k, k)
  end
  return table.concat(out)
end

-- LvlsDB.gather, made when missing
function G.Init(db, rand)
  local g = db.gather
  if type(g) ~= "table" or g.v ~= G.VERSION then
    g = { v = G.VERSION }
    db.gather = g
  end
  if type(g.id) ~= "string" then g.id = G.NewId(rand) end
  for _, k in ipairs({ "n", "o", "qs", "qe", "qo", "ql" }) do
    if type(g[k]) ~= "table" then g[k] = {} end
  end
  if type(g.sk) ~= "table" then g.sk = {} end
  g.counts = g.counts or {}
  return g
end

-- the entry for `key` in table `t` of g, nil when the table is full
local function entry(g, name, key)
  local t = g[name]
  local e = t[key]
  if e then return e end
  local c = g.counts[name] or count(t)
  if c >= G.IDS then g.counts[name] = c; return nil end
  e = {}
  t[key] = e
  g.counts[name] = c + 1
  return e
end

function G.Cell(spot)
  local x, y = floor(spot.x * 10 + 0.5), floor(spot.y * 10 + 0.5)
  if x < 0 or x > 1000 or y < 0 or y > 1000 then return nil end
  return spot.map * 1000000 + x * 1000 + y
end

function G.Uncell(cell)
  local map = floor(cell / 1000000)
  local rest = cell - map * 1000000
  return { map = map, x = floor(rest / 1000) / 10, y = (rest % 1000) / 10 }
end

-- An npc ("n") or object ("o") met at `spot` (where you stood: next to it).
function G.Seen(g, kind, id, spot)
  if (kind ~= "n" and kind ~= "o") or type(id) ~= "number" or not spot or not spot.map then return end
  local cell = G.Cell(spot)
  if not cell then return end
  local e = entry(g, kind, id)
  if not e then return end
  if e[cell] then e[cell] = e[cell] + 1; return end
  local n, least, leastKey = 0, nil, nil
  for k, v in pairs(e) do
    n = n + 1
    if not least or v < least then least, leastKey = v, k end
  end
  if n >= G.CELLS then
    if least > 1 then return end -- the places seen often stay
    e[leastKey] = nil
  end
  e[cell] = 1
end

local function bump(e, key) e[key] = (e[key] or 0) + 1 end

-- who started / ended quest q
function G.Start(g, q, kind, id)
  if type(q) ~= "number" or type(id) ~= "number" then return end
  local e = entry(g, "qs", q)
  if e then bump(e, kind .. id) end
end

function G.End(g, q, kind, id)
  if type(q) ~= "number" or type(id) ~= "number" then return end
  local e = entry(g, "qe", q)
  if e then bump(e, kind .. id) end
end

-- objective i of quest q moved on, by npc / object `id`
function G.Progress(g, q, i, kind, id)
  if type(q) ~= "number" or type(i) ~= "number" or type(id) ~= "number" then return end
  local e = entry(g, "qo", q)
  if not e then return end
  e[i] = e[i] or {}
  bump(e[i], kind .. id)
end

-- the quest as the log shows it
function G.Quest(g, q, level, title)
  if type(q) ~= "number" then return end
  local e = entry(g, "ql", q)
  if not e then return end
  if type(level) == "number" then e.lv = level end
  if type(title) == "string" then e.t = title end
end

-- quest q skipped in the route, where you stood
function G.Skip(g, q, spot, at)
  if type(q) ~= "number" then return end
  if #g.sk >= G.SKIPS then table.remove(g.sk, 1) end
  local s = { q = q, at = at }
  if spot and spot.map then s.map, s.x, s.y = spot.map, floor(spot.x * 10 + 0.5) / 10, floor(spot.y * 10 + 0.5) / 10 end
  g.sk[#g.sk + 1] = s
end

-- Objectives that moved on between two reads of the log: { { q, i }, ... }.
-- before / after: { [q] = { [i] = have } }; a quest new in `after` moved nothing.
function G.Moved(before, after)
  local out = {}
  for q, objs in pairs(after or {}) do
    local was = before and before[q]
    if was then
      for i, have in pairs(objs) do
        if type(have) == "number" and type(was[i]) == "number" and have > was[i] then
          out[#out + 1] = { q = q, i = i }
        end
      end
    end
  end
  table.sort(out, function(a, b) if a.q ~= b.q then return a.q < b.q end return a.i < b.i end)
  return out
end

-- --- the share string ----------------------------------------------------------------

local function isArray(t)
  local n = #t
  if n == 0 then return next(t) == nil and "empty" or false end
  local c = 0
  for k in pairs(t) do
    if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then return false end
    c = c + 1
  end
  return c == n
end

local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
local function str(s)
  return '"' .. s:gsub('[%c"\\]', function(c) return ESC[c] or ("\\u%04x"):format(c:byte()) end) .. '"'
end

local function num(v)
  if v ~= v or v == math.huge or v == -math.huge then return "null" end
  if v % 1 == 0 and v > -1e15 and v < 1e15 then return ("%d"):format(v) end
  local s = ("%.4f"):format(v):gsub("0+$", ""):gsub("%.$", "")
  return s
end

-- JSON of plain data (tables, strings, numbers, booleans); keys sorted, so one state
-- gives one string. A table with keys 1..n is an array; any other is an object with
-- its keys as strings. Functions and the like are left out.
function G.Json(v, depth)
  depth = depth or 0
  local t = type(v)
  if t == "string" then return str(v) end
  if t == "number" then return num(v) end
  if t == "boolean" then return v and "true" or "false" end
  if t ~= "table" or depth > 20 then return "null" end
  local arr = isArray(v)
  if arr == "empty" then return "{}" end
  local parts = {}
  if arr then
    for i = 1, #v do parts[i] = G.Json(v[i], depth + 1) end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  local keys = {}
  for k, val in pairs(v) do
    local kt, vt = type(k), type(val)
    if (kt == "string" or kt == "number") and (vt == "table" or vt == "string" or vt == "number" or vt == "boolean") then
      keys[#keys + 1] = k
    end
  end
  table.sort(keys, function(a, b)
    if type(a) == type(b) then return a < b end
    return type(a) == "number"
  end)
  for i, k in ipairs(keys) do
    parts[i] = str(type(k) == "number" and num(k) or k) .. ":" .. G.Json(v[k], depth + 1)
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

-- What a share holds: the gathered data, what Lvls! learned while you played
-- (entrances, boats ridden, recorded paths, notes) and the context to read it with.
--   meta: { addon, flavor, build, faction }
function G.Payload(db, meta)
  local g = db.gather or {}
  local p = { v = G.VERSION, id = g.id, n = g.n, o = g.o, qs = g.qs, qe = g.qe, qo = g.qo, ql = g.ql, sk = g.sk }
  for k, v in pairs(meta or {}) do p[k] = v end
  p.learned = {
    entrances = db.entrances, dungeonEntrances = db.dungeonEntrances, transit = db.transit,
    recordings = db.recordings, notes = db.notes,
  }
  return p
end

-- The string to paste: G.PREFIX .. printable(deflate(JSON)). nil when LibDeflate is missing.
function G.Encode(payload, lib)
  lib = lib or ns.LibDeflate
  if not lib then return nil end
  local json = G.Json(payload)
  return G.PREFIX .. lib:EncodeForPrint(lib:CompressDeflate(json, { level = 9 })), #json
end

-- The JSON back from a share string (the service does the same), or nil.
function G.Decode(s, lib)
  lib = lib or ns.LibDeflate
  if not lib or type(s) ~= "string" or s:sub(1, #G.PREFIX) ~= G.PREFIX then return nil end
  local raw = lib:DecodeForPrint(s:sub(#G.PREFIX + 1))
  return raw and lib:DecompressDeflate(raw)
end

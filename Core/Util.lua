local _, ns = ...
local U = ns:NewModule("Util")

U.INF = math.huge

-- A value an addon may use, or nil. Some APIs return secret values (forever
-- 1.60.1: GetUnitSpeed while unit stats are restricted, in combat; UnitName,
-- UnitClass, UnitRace when identity is restricted; UnitHealth / UnitHealthMax;
-- GetWidth of a region anchored to a secret one). A secret must not be compared,
-- used in arithmetic or as a table key (issecretvalue tells).
function U.plain(v)
  if v ~= nil and type(issecretvalue) == "function" and issecretvalue(v) then return nil end
  return v
end

function U.round(x) return math.floor(x + 0.5) end

function U.clamp(x, lo, hi)
  if x < lo then return lo end
  if x > hi then return hi end
  return x
end

function U.copy(t, seen)
  if type(t) ~= "table" then return t end
  seen = seen or {}
  if seen[t] then return seen[t] end
  local c = {}
  seen[t] = c
  for k, v in pairs(t) do c[U.copy(k, seen)] = U.copy(v, seen) end
  return c
end

function U.sortedKeys(t, cmp)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, cmp)
  return keys
end

function U.count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

function U.set(list)
  local s = {}
  for _, v in ipairs(list or {}) do s[v] = true end
  return s
end

-- Bit `n` (1-based) of a mask held in a Lua number. Pure arithmetic: masks can
-- exceed 32 bits (QuestieDB's Skyborne races use bits 32/33), so no bit library.
function U.hasBit(mask, n)
  if not mask or not n or n < 1 or n > 52 then return false end
  return math.floor(mask / 2 ^ (n - 1)) % 2 == 1
end

-- Copper -> "1g 23s 45c". nil -> "?".
function U.money(copper)
  if copper == nil then return "?" end
  copper = math.floor(math.abs(copper) + 0.5)
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  local parts = {}
  if g > 0 then parts[#parts + 1] = g .. "g" end
  if s > 0 or g > 0 then parts[#parts + 1] = s .. "s" end
  parts[#parts + 1] = c .. "c"
  return table.concat(parts, " ")
end

-- Yards -> "120 yd" / "1.4 km"-free, game-style short distance.
function U.yards(y)
  if not y or y == U.INF then return "?" end
  if y < 1000 then return ("%d yd"):format(U.round(y)) end
  return ("%.1fk yd"):format(y / 1000)
end

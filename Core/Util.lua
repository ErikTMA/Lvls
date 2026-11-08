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

-- Work in slices: a long job (the route plan) runs in a coroutine and calls
-- U.Yield() in its loops; it gives the frame back when its slice is used up and
-- goes on the next frame (U.Job). Outside a job, U.Yield does nothing, so the same
-- code runs straight through in tests and wherever it is called directly.
-- Lua 5.1 (WoW): a coroutine cannot yield across pcall or a C call (table.sort's
-- comparator, a metamethod): U.Yield only in a job's own loop bodies.
U.SLICE_MS = 8
local sliceStart, sliceCount = nil, 0
local function nowMs()
  if debugprofilestop then return debugprofilestop() end
  return os.clock() * 1000
end
U.nowMs = nowMs

function U.Yield()
  if not sliceStart then return end
  sliceCount = sliceCount + 1
  if sliceCount < 16 then return end
  sliceCount = 0
  if nowMs() - sliceStart >= U.SLICE_MS then coroutine.yield() end
end

-- A job: fn(...) in a coroutine, one slice per Step(). Step() -> "running", or
-- "done", results..., or "error", message.
function U.Job(fn, ...)
  local args, n = { ... }, select("#", ...)
  local co = coroutine.create(function() return fn(unpack(args, 1, n)) end)
  local job = { slices = 0 }
  function job.Step(ms)
    if coroutine.status(co) == "dead" then return "dead" end
    local saved = U.SLICE_MS
    U.SLICE_MS = ms or saved
    sliceStart, sliceCount = nowMs(), 0
    job.slices = job.slices + 1
    local res = { coroutine.resume(co) }
    sliceStart = nil
    U.SLICE_MS = saved
    if not res[1] then return "error", res[2] end
    if coroutine.status(co) == "dead" then return "done", unpack(res, 2, table.maxn(res)) end
    return "running"
  end
  return job
end

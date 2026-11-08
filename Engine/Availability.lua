-- Is a quest available to this character? Pure.
--
-- char = { level, faction = "Alliance" | "Horde", race = raceId, class = classId,
--          completed = { [questId] = true }, active = { [questId] = log entry },
--          skills = { [skillId] = rank } | nil (unknown) }
--
-- Status (first rule that applies):
--   "done"      completed
--   "active"    in the quest log
--   "wrong"     never for this character (faction, race, class, profession)
--   "locked"    a prerequisite is missing (reason says which)
--   "low"       required level not reached yet
--   "trivial"   grey: no longer worth experience
--   "available" can be picked up now
local _, ns = ...
local A = ns:NewModule("Availability")
local U = ns.Util

local SIDE = { Alliance = "A", Horde = "H" }

-- Classic "grey" level: a quest at or below it gives (almost) no experience.
function A.GreyLevel(level)
  if level <= 5 then return 0 end
  if level <= 39 then return level - 5 - math.floor(level / 10) end
  if level <= 59 then return level - 1 - math.floor(level / 5) end
  return level - 9
end

-- Ids above 26 (forever's Skyborne races) are not in Wowhead's masks: skip the
-- race test for them rather than guess a bit position.
local function raceOk(mask, race)
  if not mask or not race or race > 26 then return true end
  return U.hasBit(mask, race)
end

local function classOk(mask, class)
  if not mask or not class then return true end
  return U.hasBit(mask, class)
end

function A.Status(q, char)
  local id = q.id
  if char.completed[id] then return "done" end
  if char.active and char.active[id] then return "active" end
  if q.side and SIDE[char.faction] and q.side ~= SIDE[char.faction] then return "wrong", "faction" end
  local info = ns.Prereqs.Info(id)
  if not raceOk(info and info.races or q.races, char.race) then return "wrong", "race" end
  if not classOk(info and info.classes or q.classes, char.class) then return "wrong", "class" end
  if q.prof and char.skills then
    local have = char.skills[q.prof[1]]
    if not have then return "wrong", "profession" end
    if q.prof[2] and have < q.prof[2] then return "locked", "profession skill " .. q.prof[2] end
  end
  local ok, reason, kind = ns.Prereqs.Check(q, char)
  if not ok then return kind or "locked", reason end
  if q.r and char.level < q.r then return "low", "level " .. q.r end
  if q.l and q.l <= A.GreyLevel(char.level) then return "trivial" end
  return "available"
end

-- Display colour of a quest level for this character, like the quest log's.
function A.Difficulty(qlevel, level)
  if not qlevel then return "normal" end
  local d = qlevel - level
  if d >= 5 then return "impossible" end
  if d >= 3 then return "hard" end
  if d >= -2 then return "normal" end
  if qlevel > A.GreyLevel(level) then return "easy" end
  return "trivial"
end

A.COLORS = {
  impossible = { 1, 0.1, 0.1 }, hard = { 1, 0.5, 0.25 }, normal = { 1, 0.82, 0 },
  easy = { 0.25, 0.75, 0.25 }, trivial = { 0.5, 0.5, 0.5 },
}

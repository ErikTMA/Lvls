-- What guides are built from and does not change while you play, built once and
-- kept: class quest chain graphs (Engine/ClassQuests), the breadcrumb index and each
-- dungeon's quests (Engine/Dungeons), which quests another one excludes
-- (Engine/Sync). Pure.
--
-- The key: the dataset, the prerequisite provider (Prereqs.generation, so QuestieDB
-- connecting or going away rebuilds) and the character's faction, race and class.
-- Nothing a character does changes it: what is done, in the log, the level, and
-- quests becoming impossible (an exclusive one taken) are worked out per call on top
-- of it. Group sync does not change it either: a member's state is a layer of its
-- own (Engine/Sync).
--
-- Datasets do not change once registered. Tests that edit one in place call Reset.
local _, ns = ...
local GC = ns:NewModule("GuideCache")

GC.builds = {} -- part -> times built (tests and /dump)

local cur

local function key(ds, char)
  return ds, ns.Prereqs.generation, char and char.faction, char and char.race, char and char.class
end

-- The part `name`, built by build(ds, char) when the key changed or it is missing.
function GC.Get(ds, char, name, build)
  local d, gen, faction, race, class = key(ds, char)
  if not cur or cur.ds ~= d or cur.gen ~= gen or cur.faction ~= faction or cur.race ~= race or cur.class ~= class then
    cur = { ds = d, gen = gen, faction = faction, race = race, class = class, parts = {} }
  end
  local v = cur.parts[name]
  if v == nil then
    v = build(ds, char)
    cur.parts[name] = v
    GC.builds[name] = (GC.builds[name] or 0) + 1
  end
  return v
end

function GC.Reset() cur = nil end

-- Quest prerequisites. Wowhead has none for forever; they come from a provider (the
-- QuestieDB adapter reads LibQuestieDB at runtime). Pure: the provider is injected.
--
-- provider.Info(questId) -> nil when the provider does not know the quest, else
--   { group = {ids} (all of), single = {ids} (any one of), excl = {ids},
--     breadcrumbFor = id, maxLevel = n, skill = {skillId, value},
--     minRep = {factionId, value}, parent = id,
--     classes / races = masks that replace the dataset's (QuestieDB corrects Wowhead) }
-- Without provider data the quest's predecessor in Wowhead's linear series must be
-- completed (a weaker rule: the series also lists optional breadcrumbs).
local _, ns = ...
local P = ns:NewModule("Prereqs")

local provider

-- Counts every SetProvider, so caches built from provider data (Engine/GuideCache)
-- know when it changed, even to the same table again.
P.generation = 0
function P.SetProvider(p) provider = p; P.generation = P.generation + 1 end
function P.Provider() return provider end

function P.Info(qid)
  if not provider or not provider.Info then return nil end
  local ok, info = pcall(provider.Info, qid)
  if ok then return info end
  return nil
end

local function done(char, id) return char.completed[id] end
local function active(char, id) return char.active and char.active[id] end

-- ok (bool), reason (string when not ok), kind: "wrong" when it can never become
-- available to this character (exclusive quest taken, breadcrumb obsolete, too high,
-- profession missing), "locked" when a prerequisite can still be done
function P.Check(q, char)
  local info = P.Info(q.id)
  if info then
    if info.group and #info.group > 0 then
      for _, id in ipairs(info.group) do
        if not done(char, id) then return false, "needs " .. id, "locked" end
      end
    end
    if info.single and #info.single > 0 then
      local any = false
      for _, id in ipairs(info.single) do
        if done(char, id) then any = true; break end
      end
      if not any then return false, "needs one of " .. table.concat(info.single, ","), "locked" end
    end
    for _, id in ipairs(info.excl or {}) do
      if done(char, id) or active(char, id) then return false, "excluded by " .. id, "wrong" end
    end
    if info.breadcrumbFor and (done(char, info.breadcrumbFor) or active(char, info.breadcrumbFor)) then
      return false, "breadcrumb no longer needed", "wrong"
    end
    if info.maxLevel and info.maxLevel > 0 and char.level and char.level > info.maxLevel then
      return false, "above level " .. info.maxLevel, "wrong"
    end
    if info.skill and info.skill[1] and char.skills then
      local have = char.skills[info.skill[1]]
      if not have then return false, "needs skill " .. info.skill[1], "wrong" end
      if have < (info.skill[2] or 1) then return false, "needs skill " .. info.skill[1] .. " " .. info.skill[2], "locked" end
    end
    if info.minRep and info.minRep[1] and char.rep then
      local have = char.rep(info.minRep[1])
      if have and have < info.minRep[2] then return false, "needs reputation", "locked" end
    end
    if info.parent and info.parent > 0 and not active(char, info.parent) then
      return false, "needs " .. info.parent .. " active", "locked"
    end
    return true
  end
  if q.prevAny then
    local any = false
    for _, id in ipairs(q.prevAny) do if done(char, id) then any = true; break end end
    if not any then return false, "series: needs one of " .. table.concat(q.prevAny, ","), "locked" end
  elseif q.prev and not q.prevLoop and not done(char, q.prev) then
    return false, "series: needs " .. q.prev, "locked"
  end
  return true
end

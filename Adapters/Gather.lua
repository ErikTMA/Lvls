-- Feeds Engine/Gather from the game: where you meet npcs and objects, who starts and
-- ends quests, what moved an objective on, skipped quests.
--
-- forever 1.60.1 (wow-ui-source branch forever): no combat log for addons, and
-- UnitGUID can be secret (ns.Util.plain turns that into nil: then nothing is kept).
--   npc / object you talk to: UnitGUID("npc") at GOSSIP_SHOW, QUEST_GREETING,
--     QUEST_DETAIL, QUEST_PROGRESS, QUEST_COMPLETE, MERCHANT_SHOW, TAXIMAP_OPENED,
--     TRAINER_SHOW; where you stand then is next to it
--   quest giver / ender: the npc of the last QUEST_DETAIL / QUEST_COMPLETE for that
--     quest (GetQuestID()), kept when QUEST_ACCEPTED / QUEST_TURNED_IN follows
--   what you loot: GetLootSourceInfo(slot) (the corpse's or object's GUID) where the
--     client has it, else your dead target; one source only (an area loot of several
--     corpses says nothing about where each stood)
--   objectives: C_QuestLog.GetQuestObjectives read at QUEST_LOG_UPDATE; one that
--     went up within RECENT seconds of a loot (item and object objectives) or of your
--     target dying (UNIT_HEALTH on the target; monster objectives) is credited to it
-- Off with the gather setting; nothing leaves the game but by /lvls share.
local _, ns = ...
local GA = ns:NewModule("GatherLog")

GA.RECENT = 4

local TALK = { GOSSIP_SHOW = true, QUEST_GREETING = true, QUEST_DETAIL = true, QUEST_PROGRESS = true,
  QUEST_COMPLETE = true, MERCHANT_SHOW = true, TAXIMAP_OPENED = true, TRAINER_SHOW = true }

local function now() return GetTime and GetTime() or 0 end

local function on()
  return ns.db and ns.db.settings and ns.db.settings.gather and ns.db.gather
end

local function npc(unit)
  if ns.Auto then return ns.Auto.Npc(unit) end
end

local function guidKind(guid)
  guid = ns.Util.plain(guid)
  if type(guid) ~= "string" then return nil end
  local what, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
  if what == "Creature" or what == "Vehicle" then return "n", tonumber(id) end
  if what == "GameObject" then return "o", tonumber(id) end
end

local pendingStart, pendingEnd = {}, {} -- [quest] = { kind, id }
local lastLoot, lastKill               -- { kind, id, at }
local objectives                       -- { [q] = { [i] = have } } at the last read

function GA.Talk(event)
  local g = on()
  if not g or not TALK[event] then return end
  local kind, id = npc("npc")
  if not kind then return end
  local spot = ns.Game.Position()
  if spot then ns.Gather.Seen(g, kind, id, spot) end
  local q = type(GetQuestID) == "function" and GetQuestID() or nil
  if type(q) == "number" and q > 0 then
    if event == "QUEST_DETAIL" then pendingStart[q] = { kind, id } end
    if event == "QUEST_COMPLETE" or event == "QUEST_PROGRESS" then pendingEnd[q] = { kind, id } end
  end
end

function GA.Accepted(q)
  local g = on()
  local p = pendingStart[q]
  pendingStart[q] = nil
  if not g or type(q) ~= "number" then return end
  if p then ns.Gather.Start(g, q, p[1], p[2]) end
  local entry = ns.Game.QuestLog()[q]
  if entry then ns.Gather.Quest(g, q, entry.level, entry.title) end
end

function GA.TurnedIn(q)
  local g = on()
  local p = pendingEnd[q]
  pendingEnd[q] = nil
  if g and p then ns.Gather.End(g, q, p[1], p[2]) end
end

-- the single source of what is being looted, or nil
function GA.LootSource()
  if type(GetNumLootItems) ~= "function" then return nil end
  local found
  if type(GetLootSourceInfo) == "function" then
    for slot = 1, GetNumLootItems() or 0 do
      local ok, guid = pcall(GetLootSourceInfo, slot)
      local kind, id
      if ok then kind, id = guidKind(guid) end
      if kind then
        if found and (found[1] ~= kind or found[2] ~= id) then return nil end -- several
        found = { kind, id }
      end
    end
  end
  if not found and UnitExists and UnitExists("target") and UnitIsDead and UnitIsDead("target") then
    local kind, id = npc("target")
    if kind then found = { kind, id } end
  end
  return found
end

function GA.Looted()
  local g = on()
  if not g then return end
  local src = GA.LootSource()
  if not src then return end
  lastLoot = { src[1], src[2], now() }
  local spot = ns.Game.Position()
  if spot then ns.Gather.Seen(g, src[1], src[2], spot) end
end

-- your target died (checked as objectives move: no combat log)
local function deadTarget()
  if not (UnitExists and UnitExists("target") and UnitIsDead and UnitIsDead("target")) then return nil end
  local kind, id = npc("target")
  if kind == "n" then return { kind, id, now() } end
end

local function readObjectives()
  local out, types = {}, {}
  for q, e in pairs(ns.Game.QuestLog()) do
    out[q], types[q] = {}, {}
    for i, o in ipairs(e.objectives or {}) do
      out[q][i] = ns.Util.plain(o.have)
      types[q][i] = o.type
    end
  end
  return out, types
end

function GA.LogChanged()
  local g = on()
  if not g then objectives = nil; return end
  local after, types = readObjectives()
  local moved = ns.Gather.Moved(objectives, after)
  objectives = after
  if #moved == 0 then return end
  local t = now()
  local kill = deadTarget() or lastKill
  if kill then lastKill = kill end
  for _, m in ipairs(moved) do
    local ty = types[m.q] and types[m.q][m.i]
    local src
    if (ty == "item" or ty == "object") and lastLoot and t - lastLoot[3] <= GA.RECENT then src = lastLoot
    elseif ty == "monster" and kill and t - kill[3] <= GA.RECENT then src = kill end
    if src then ns.Gather.Progress(g, m.q, m.i, src[1], src[2]) end
  end
end

-- a quest skipped in the route (Core/Init ns.SetSkip)
function GA.Skipped(q)
  local g = on()
  if g then ns.Gather.Skip(g, q, ns.Game.Position(), time and time() or nil) end
end

-- The share string for this install (/lvls share), and the JSON's size.
function GA.Share()
  local db = ns.db
  if not db then return nil end
  ns.Gather.Init(db)
  local version
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  if get then
    local ok, v = pcall(get, ns.name or "Lvls", "Version")
    if ok and type(v) == "string" then version = v end
  end
  local meta = { addon = version, flavor = ns.Game.Flavor and ns.Game.Flavor() or nil,
    faction = ns.char and ns.char.faction or nil }
  if GetBuildInfo then
    local _, build = GetBuildInfo()
    meta.build = ns.Util.plain(build)
  end
  return ns.Gather.Encode(ns.Gather.Payload(db, meta))
end

local HANDLERS = {
  QUEST_ACCEPTED = function(q) GA.Accepted(q) end,
  QUEST_TURNED_IN = function(q) GA.TurnedIn(q) end,
  LOOT_OPENED = function() GA.Looted() end,
  QUEST_LOG_UPDATE = function() GA.LogChanged() end,
  UNIT_HEALTH = function(unit)
    -- your target dying (it is often cleared or changed before the log moves on)
    if unit ~= "target" or not on() then return end
    local k = deadTarget()
    if k then lastKill = k end
  end,
}

if CreateFrame then
  local f = CreateFrame("Frame")
  for e in pairs(TALK) do f:RegisterEvent(e) end
  for e in pairs(HANDLERS) do f:RegisterEvent(e) end
  f:SetScript("OnEvent", function(_, event, ...)
    local ok, err
    if TALK[event] then ok, err = pcall(GA.Talk, event) else ok, err = pcall(HANDLERS[event], ...) end
    if not ok and ns.Log then ns.Log("debug", "gather " .. event .. ": " .. tostring(err)) end
  end)
end

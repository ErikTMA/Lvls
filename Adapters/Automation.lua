-- Automation: accept and hand in quests, pick the reward, put on upgrades. Every
-- part has its own setting; holding Shift while talking to an npc pauses it.
-- Client calls (forever 1.60.1; wow-ui-source branch forever, QuestFrame.lua,
-- GossipFrameShared.lua, GameDialogDefs.lua):
--   QUEST_DETAIL: AcceptQuest() (QuestGetAutoAccept(): AcknowledgeAutoAcceptQuest())
--   QUEST_ACCEPT_CONFIRM(name, questTitle, questID): ConfirmAcceptQuest()
--   GOSSIP_SHOW: C_GossipInfo.GetActiveQuests / GetAvailableQuests -> { questID,
--     isComplete, isTrivial, isIgnored }, SelectActiveQuest(questID) / SelectAvailableQuest(questID)
--   QUEST_GREETING: GetNumActiveQuests, GetActiveTitle(i) -> title, isComplete,
--     SelectActiveQuest(i); GetNumAvailableQuests, GetAvailableQuestInfo(i) ->
--     isTrivial, frequency, isRepeatable, isLegendary, questID; SelectAvailableQuest(i)
--   QUEST_PROGRESS: IsQuestCompletable(), CompleteQuest()
--   QUEST_COMPLETE: GetNumQuestChoices(), GetQuestItemLink("choice", i),
--     GetQuestItemInfo("choice", i) -> name, texture, count, quality, isUsable, itemID,
--     GetQuestMoneyToGet(), GetQuestReward(choice)
--   EQUIP_BIND_CONFIRM(slot, itemLocation): EquipPendingItem(slot)
local _, ns = ...
local A = ns:NewModule("Auto")
local GA, Gear = ns.GearData, ns.Gear

local function has(t, k) return type(t) == "table" and type(t[k]) == "function" end
local function set(k) return ns.db and ns.db.settings[k] end
local function paused() return type(IsShiftKeyDown) == "function" and IsShiftKeyDown() end
local function skipped(qid) return qid and ns.cdb and ns.cdb.skip and ns.cdb.skip[qid] end

-- quests --------------------------------------------------------------------

-- Is the quest one the plan tells you to pick up now or later (an open "Accept" /
-- "Pick up" line: the leveling route, a dungeon or class guide, a catch-up)? Only
-- those are accepted automatically; anything else is yours to decide.
function A.Planned(qid)
  if not qid then return false end
  for _, st in ipairs(ns.steps or {}) do
    for _, l in ipairs(st.lines or {}) do
      if l.kind == "accept" and l.quest == qid and not l.done then return true end
    end
  end
  return false
end

function A.OnDetail()
  if not set("autoAccept") or paused() then return end
  local qid = type(GetQuestID) == "function" and GetQuestID() or nil
  if skipped(qid) or not A.Planned(qid) then return end
  -- a quest that flags you for PvP keeps its confirmation: yours to accept
  if type(QuestFlagsPVP) == "function" and QuestFlagsPVP() then return end
  if type(QuestGetAutoAccept) == "function" and QuestGetAutoAccept() then
    if type(AcknowledgeAutoAcceptQuest) == "function" then AcknowledgeAutoAcceptQuest() end
    return
  end
  AcceptQuest()
end

-- a group member shares an escort quest: QUEST_ACCEPT_CONFIRM(name, questTitle, questID)
function A.OnAcceptConfirm(_, _, qid)
  if not set("autoAccept") or paused() or not A.Planned(qid) then return end
  ConfirmAcceptQuest()
  if type(StaticPopup_Hide) == "function" then StaticPopup_Hide("QUEST_ACCEPT") end
end

local function wanted(qid, trivial, ignored)
  if skipped(qid) or ignored or not A.Planned(qid) then return false end
  return not trivial or set("showTrivial")
end

function A.OnGossip()
  if paused() or not C_GossipInfo then return end
  if set("autoDeliver") and has(C_GossipInfo, "GetActiveQuests") then
    for _, q in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
      if q.isComplete then C_GossipInfo.SelectActiveQuest(q.questID) return end
    end
  end
  if set("autoAccept") and has(C_GossipInfo, "GetAvailableQuests") then
    for _, q in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
      if wanted(q.questID, q.isTrivial, q.isIgnored) then C_GossipInfo.SelectAvailableQuest(q.questID) return end
    end
  end
end

function A.OnGreeting()
  if paused() then return end
  if set("autoDeliver") then
    for i = 1, GetNumActiveQuests() or 0 do
      local _, complete = GetActiveTitle(i)
      if complete then SelectActiveQuest(i) return end
    end
  end
  if set("autoAccept") then
    for i = 1, GetNumAvailableQuests() or 0 do
      local trivial, _, _, _, qid = GetAvailableQuestInfo(i)
      if wanted(qid, trivial, false) then SelectAvailableQuest(i) return end
    end
  end
end

function A.OnProgress()
  if set("autoDeliver") and not paused() and IsQuestCompletable() then CompleteQuest() end
end

local function money(c)
  c = math.floor(c or 0)
  local g, s = math.floor(c / 10000), math.floor(c / 100) % 100
  if g > 0 then return ("%dg %ds"):format(g, s) end
  if s > 0 then return ("%ds %dc"):format(s, c % 100) end
  return c .. "c"
end

-- The reward choices as Gear.ChooseReward wants them; nil while an item is not
-- loaded yet.
function A.RewardChoices(n)
  local score = GA.Scorer()
  local equipped = GA.Equipped(score)
  local out = {}
  for i = 1, n do
    local link = GetQuestItemLink("choice", i)
    local _, _, count, _, isUsable = GetQuestItemInfo("choice", i)
    local info = GA.Info(link)
    if not info then return nil end
    local delta = GA.Delta(info.link, score, equipped)
    out[i] = { link = info.link, usable = isUsable ~= false and GA.Usable(info), delta = delta,
      sell = (info.sell or 0) * math.max(1, count or 1) }
  end
  return out
end

A.RETRIES = 10
function A.OnComplete(try)
  if not set("autoDeliver") or paused() then return end
  if type(GetQuestMoneyToGet) == "function" and (GetQuestMoneyToGet() or 0) > 0 then return end
  local n = GetNumQuestChoices() or 0
  if n <= 1 then GetQuestReward(n) return end
  if not set("autoReward") and not set("rewardGold") then return end
  local choices = A.RewardChoices(n)
  if not choices then
    try = (try or 0) + 1
    if try <= A.RETRIES and C_Timer then C_Timer.After(0.2, function() A.OnComplete(try) end) end
    return
  end
  local i, why = Gear.ChooseReward(choices, { upgrades = set("autoReward"), gold = set("rewardGold") })
  if not i then
    ns.Log("info", "no reward is an upgrade: choose one yourself")
    return
  end
  local c = choices[i]
  ns.Log("info", why == "upgrade" and ("took %s, an upgrade"):format(c.link)
    or ("took %s (sells for %s): no usable upgrade among the rewards"):format(c.link, money(c.sell)))
  GetQuestReward(i)
end

-- equipping ------------------------------------------------------------------

A.seen = {}        -- bag item GUIDs already judged
A.pending = nil    -- { link, at } an equip we started that may ask to bind
A.waitCombat = false

function A.Baseline()
  A.seen = {}
  for _, it in ipairs(GA.BagItems()) do A.seen[it.guid] = true end
end

-- Judge new bag items once each; put on the first upgrade allowed. Items you
-- cannot use yet (level) stay unjudged until you can.
function A.ScanBags()
  if not set("autoEquip") then return end
  if type(InCombatLockdown) == "function" and InCombatLockdown() then A.waitCombat = true return end
  A.waitCombat = false
  local score = GA.Scorer()
  local equipped
  for _, it in ipairs(GA.BagItems()) do
    if not A.seen[it.guid] then
      local info = GA.Info(it.link)
      if info then
        if not Gear.SLOTS[info.equipLoc] then
          A.seen[it.guid] = true
        elseif (info.minLevel or 0) > (UnitLevel("player") or 1) then
          -- later
        elseif not GA.Usable(info) then
          A.seen[it.guid] = true
        else
          equipped = equipped or GA.Equipped(score)
          local delta, slot = GA.Delta(it.link, score, equipped)
          if delta ~= nil then
            A.seen[it.guid] = true
            if delta > 0 then
              local binds = info.bindType == 2 and not it.bound
              local ok, why = Gear.MayEquip({ quality = info.quality, bindsOnEquip = binds },
                { equip = true, bind = set("autoEquipBind"), maxQuality = set("equipMaxQuality") })
              if ok then
                if binds then A.pending = { link = it.link, at = GetTime() } end
                GA.Equip(it.link, slot)
                ns.Log("info", ("equipped %s, an upgrade"):format(it.link))
                return
              elseif why == "binds" or why == "quality" then
                ns.Log("info", ("%s is an upgrade but binds when equipped: put it on yourself"):format(it.link))
              end
            end
          end
        end
      end
    end
  end
end

function A.OnBindConfirm(slot)
  local p = A.pending
  A.pending = nil
  if not p or not set("autoEquipBind") or GetTime() - p.at > 5 then return end
  EquipPendingItem(slot)
  if type(StaticPopup_Hide) == "function" then StaticPopup_Hide("EQUIP_BIND") end
end

local HANDLERS = {
  QUEST_DETAIL = function() A.OnDetail() end,
  QUEST_ACCEPT_CONFIRM = function(...) A.OnAcceptConfirm(...) end,
  GOSSIP_SHOW = function() A.OnGossip() end,
  QUEST_GREETING = function() A.OnGreeting() end,
  QUEST_PROGRESS = function() A.OnProgress() end,
  QUEST_COMPLETE = function() A.OnComplete() end,
  EQUIP_BIND_CONFIRM = function(slot) A.OnBindConfirm(slot) end,
  BAG_UPDATE_DELAYED = function() A.ScanBags() end,
  PLAYER_LEVEL_UP = function() A.ScanBags() end,
  PLAYER_REGEN_ENABLED = function() if A.waitCombat then A.ScanBags() end end,
  PLAYER_LOGIN = function() A.Baseline() end,
}

if CreateFrame then
  local f = CreateFrame("Frame")
  for e in pairs(HANDLERS) do f:RegisterEvent(e) end
  f:SetScript("OnEvent", function(_, event, ...)
    local ok, err = pcall(HANDLERS[event], ...)
    if not ok then ns.Log("error", event .. ": " .. tostring(err)) end
  end)
end

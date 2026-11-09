-- Training, game side: what a class trainer teaches (read while its window is
-- open, kept in LvlsCharDB.trainer), the spellbook and the action bars, for
-- Engine/Training. APIs (forever 1.60.1, wow-ui-source branch forever, feature
-- detected):
--   TRAINER_SHOW / TRAINER_UPDATE / TRAINER_CLOSED; C_Trainer.GetTrainerType()
--     (Enum.TrainerType: General 0, Tradeskills 2, Pet 3), IsTradeskillTrainer()
--   GetNumTrainerServices(), GetTrainerServiceInfo(i) -> name, serviceType
--     ("available" | "unavailable" | "used" | "header"), texture, reqLevel, subText
--     ("Rank 4"), GetTrainerServiceCost(i) -> copper
--   Get/SetTrainerServiceTypeFilter(type[, on]): the list holds only the types
--     shown, so all three are shown while it is read and put back afterwards
--   C_SpellBook.GetNumSpellBookSkillLines / GetSpellBookSkillLineInfo(i) ->
--     { itemIndexOffset, numSpellBookItems, shouldHide }, GetSpellBookItemInfo(slot,
--     Enum.SpellBookSpellBank.Player) -> { itemType (Enum.SpellBookItemType: Spell 1,
--     FutureSpell 2), name, isPassive }, GetSpellBookItemLevelLearned(slot, bank)
--   C_ActionBar.HasAction(slot), C_ActionBar.GetSpell(slot) -> spellID,
--     C_Spell.GetSpellName(spellID); GetMoney()
local _, ns = ...
local TA = ns:NewModule("TrainingData")

local function has(t, k) return type(t) == "table" and type(t[k]) == "function" end
local plain = function(v) return ns.Util.plain(v) end

TA.BAR_SLOTS = 180
local TYPES = { "available", "unavailable", "used" }

-- A class trainer's window is open (not a profession or pet trainer).
function TA.IsClassTrainer()
  if has(_G, "IsTradeskillTrainer") and IsTradeskillTrainer() then return false end
  if has(C_Trainer, "GetTrainerType") and Enum and Enum.TrainerType then
    local t = C_Trainer.GetTrainerType()
    if t == Enum.TrainerType.Tradeskills or t == Enum.TrainerType.Pet then return false end
  end
  return true
end

-- The open trainer's list, every type of service, or nil.
local reading = false
function TA.ReadTrainer()
  if not (has(_G, "GetNumTrainerServices") and has(_G, "GetTrainerServiceInfo")) then return nil end
  reading = true
  local filters = {}
  local canFilter = has(_G, "GetTrainerServiceTypeFilter") and has(_G, "SetTrainerServiceTypeFilter")
  if canFilter then
    for _, t in ipairs(TYPES) do
      filters[t] = GetTrainerServiceTypeFilter(t) and true or false
      if not filters[t] then pcall(SetTrainerServiceTypeFilter, t, true) end
    end
  end
  local list = {}
  local ok = pcall(function()
    for i = 1, GetNumTrainerServices() or 0 do
      local name, kind, _, level, sub = GetTrainerServiceInfo(i)
      name, kind, level, sub = plain(name), plain(kind), plain(level), plain(sub)
      if type(name) == "string" and kind ~= "header" then
        local cost = has(_G, "GetTrainerServiceCost") and plain((GetTrainerServiceCost(i))) or nil
        list[#list + 1] = { n = name, r = type(sub) == "string" and sub or "", l = tonumber(level) or 0,
          c = tonumber(cost) or 0, s = kind }
      end
    end
  end)
  if canFilter then
    for _, t in ipairs(TYPES) do
      if not filters[t] then pcall(SetTrainerServiceTypeFilter, t, false) end
    end
  end
  reading = false
  if not ok or #list == 0 then return nil end
  return list
end

-- Spells in the spellbook: known = { [name] = true }, future = { { n, l }, ... }.
function TA.Spellbook()
  local known, future = {}, {}
  local SB = C_SpellBook
  if not (has(SB, "GetNumSpellBookSkillLines") and has(SB, "GetSpellBookSkillLineInfo") and has(SB, "GetSpellBookItemInfo")) then
    return known, future
  end
  local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
  local SPELL = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell or 1
  local FUTURE = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.FutureSpell or 2
  pcall(function()
    for line = 1, SB.GetNumSpellBookSkillLines() or 0 do
      local li = SB.GetSpellBookSkillLineInfo(line)
      if li and not li.shouldHide then
        for slot = (li.itemIndexOffset or 0) + 1, (li.itemIndexOffset or 0) + (li.numSpellBookItems or 0) do
          local it = SB.GetSpellBookItemInfo(slot, bank)
          local name = it and plain(it.name)
          if type(name) == "string" then
            if it.itemType == SPELL then
              known[name] = true
            elseif it.itemType == FUTURE then
              local l = has(SB, "GetSpellBookItemLevelLearned") and plain(SB.GetSpellBookItemLevelLearned(slot, bank))
              future[#future + 1] = { n = name, l = tonumber(l) or 0 }
            end
          end
        end
      end
    end
  end)
  return known, future
end

-- Spells on the action bars: { [name] = true }.
function TA.Bars()
  local out = {}
  local AB = C_ActionBar
  local name = has(C_Spell, "GetSpellName") and C_Spell.GetSpellName
  if not name then return out end
  for slot = 1, TA.BAR_SLOTS do
    local ok, id = pcall(function()
      if has(AB, "HasAction") and not AB.HasAction(slot) then return nil end
      if has(AB, "GetSpell") then return AB.GetSpell(slot) end
      if has(_G, "GetActionInfo") then
        local kind, sid = GetActionInfo(slot)
        if kind == "spell" then return sid end
      end
    end)
    id = ok and plain(id)
    if type(id) == "number" and id > 0 then
      local okn, n = pcall(name, id)
      n = okn and plain(n)
      if type(n) == "string" then out[n] = true end
    end
  end
  return out
end

-- What Engine/Training reads, cached until the spells, the bars or a trainer change.
local cache
function TA.Seen()
  if cache then return cache end
  local t = ns.cdb and ns.cdb.trainer
  local known, future = TA.Spellbook()
  cache = { list = t and t.list, at = t and t.at, known = known, future = future, bars = TA.Bars() }
  return cache
end
function TA.Invalidate() cache = nil end

function TA.Money()
  return has(_G, "GetMoney") and tonumber(plain(GetMoney())) or nil
end

-- The summary for this character (Engine/Training.Summary), or nil.
function TA.Summary(level)
  return ns.Training.Summary(TA.Seen(), level, TA.Money())
end

-- A class trainer's window: keep what it teaches.
function TA.OnTrainer()
  if reading or not ns.cdb or not TA.IsClassTrainer() then return end
  local list = TA.ReadTrainer()
  if not list then return end
  -- time: a train step planned before this visit is done (Engine/Steps)
  ns.cdb.trainer = { list = list, at = (UnitLevel and plain(UnitLevel("player"))) or 0,
    time = type(time) == "function" and time() or 0 }
  TA.Invalidate()
  ns.Events.Fire("LVLS_STATE", "TRAINER_UPDATE")
end

if CreateFrame then
  local f = CreateFrame("Frame")
  for _, e in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE", "SPELLS_CHANGED", "ACTIONBAR_SLOT_CHANGED",
    "LEARNED_SPELL_IN_SKILL_LINE", "PLAYER_LEVEL_UP" }) do
    pcall(f.RegisterEvent, f, e)
  end
  f:SetScript("OnEvent", function(_, event)
    if event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then
      TA.OnTrainer()
    else
      TA.Invalidate()
    end
  end)
end

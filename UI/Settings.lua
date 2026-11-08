-- The Lvls! page in the game's Settings (Options -> AddOns -> Lvls!), and the
-- matching /lvls commands. Values live in LvlsDB.settings (account) and
-- LvlsCharDB.spec (this character's spec override).
-- API (wow-ui-source branch forever, Blizzard_Settings_Shared):
--   Settings.RegisterVerticalLayoutCategory(name) -> category, layout
--   Settings.RegisterProxySetting(category, variable, varType, name, default, get, set)
--   Settings.CreateCheckbox(category, setting, tooltip)
--   Settings.CreateDropdown(category, setting, optionsFn, tooltip), optionsFn ->
--     Settings.CreateControlTextContainer():Add(value, label) ... :GetData()
--   CreateSettingsListSectionHeaderInitializer(name), layout:AddInitializer(init)
--   Settings.RegisterAddOnCategory(category), Settings.OpenToCategory(category:GetID())
local _, ns = ...
local S = ns:NewModule("Settings")

S.QUALITIES = { { 1, "Common (white)" }, { 2, "Uncommon (green)" }, { 3, "Rare (blue)" }, { 4, "Epic (purple)" } }
S.WEIGHTS = { { "auto", "Pawn when it has a scale for my spec, else Lvls" }, { "pawn", "Pawn" }, { "lvls", "Lvls' own weights" } }

-- Everything on the page, in order. key: LvlsDB.settings key; refresh: re-plan.
S.ITEMS = {
  { header = "Quests" },
  { key = "autoAccept", name = "Accept the quests the guide picks", tip = "Accept a quest when an npc offers it and the plan (route, guide, catch-up) tells you to pick it up. Other quests are left to you. Hold Shift to pause." },
  { key = "autoDeliver", name = "Hand in quests", tip = "Hand in finished quests when you talk to the npc." },
  { key = "autoReward", name = "Choose the best reward", tip = "Take the reward that is the biggest upgrade you can use, judged for your class and spec." },
  { key = "rewardGold", name = "Otherwise the most gold", tip = "When no reward is a usable upgrade, take the one that sells for most." },
  { header = "Gear" },
  { key = "autoEquip", name = "Put on upgrades (out of combat)", tip = "Equip new items in your bags that are upgrades for your spec." },
  { key = "autoEquipBind", name = "Also items that bind when equipped", tip = "Equip upgrades that bind when you put them on, up to the quality below. Better ones stay in your bags to sell or decide." },
  { key = "equipMaxQuality", name = "Highest quality to bind", choices = S.QUALITIES, number = true },
  { key = "gearWeights", name = "Stat weights", choices = S.WEIGHTS, tip = "Which weights judge gear. Your spec always comes from your talents (most points spent) or the choice below, never from Pawn." },
  { spec = true, name = "Spec", tip = "Detected: the talent tree with most points; below level 10 the class's leveling weights." },
  { header = "Learning" },
  { key = "learnFights", name = "Learn from my fights", tip = "Record how long fights take, how much health they cost and the rest after them (solo only). Lvls! plans quests you can handle from it. /lvls fights shows what it learned." },
  { key = "suggestGrind", name = "Suggest grinding a level", tip = "When the only quests left close by are ones your fights say are too hard, kill easy mobs nearby until the next level instead of leaving." },
  { header = "Group" },
  { key = "groupSync", name = "Share quest progress with my group", tip = "Group members who run Lvls! exchange which quests they have done, to catch up with each other." },
  { key = "askSync", name = "Ask to catch up / to help", tip = "When a member has done quests you have not, ask whether to catch up; when one wants to catch up with you, ask whether to follow their route." },
  { header = "Route and map" },
  { guide = true, name = "Guide", tip = "A dungeon: every quest for it and the chains leading to them, ending at its entrance. A class quest chain: its quests in reach. Also in the viewer's Guides menu and /lvls guide." },
  { key = "classQuests", name = "Class quests in the route", tip = "The leveling route takes your class quests (spells, forms, pets, weapons) as they become possible, in their order, marked with your class. The Guides menu does a whole chain at once.", refresh = true },
  { key = "zoneFirst", name = "Finish the zone first", refresh = true },
  { key = "arrow", name = "Arrow" },
  { key = "worldMap", name = "Quest pins on the world map" },
  { key = "minimap", name = "Quest pins on the minimap" },
  { key = "objectives", name = "Objective areas" },
  { key = "showLow", name = "Show quests you are too low for" },
  { key = "showTrivial", name = "Show grey quests" },
  { key = "showDungeon", name = "Show dungeon quests" },
  { key = "showRepeatable", name = "Show repeatable quests" },
}

function S.Get(key) return ns.db.settings[key] end
function S.Set(key, value)
  ns.db.settings[key] = value
  if ns.Invalidate then ns.Invalidate() end
  for _, it in ipairs(S.ITEMS) do
    if it.key == key and it.refresh and ns.Refresh then ns.Refresh(true) return end
  end
  if ns.Refresh and ns.char then ns.Refresh() end
end

-- this character's spec choices: 0 = detect, then the class's trees
function S.SpecChoices()
  local token = ns.GearData.Class()
  local out = { { 0, "Detect from talents" } }
  for i, sp in ipairs(ns.Gear.SPECS[token] or {}) do out[#out + 1] = { i, sp.name } end
  return out
end

function S.Register()
  if S.category or not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
  local category, layout = Settings.RegisterVerticalLayoutCategory("Lvls!")
  local Var = Settings.VarType or {}
  for _, it in ipairs(S.ITEMS) do
    if it.header then
      if layout and CreateSettingsListSectionHeaderInitializer then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(it.header))
      end
    else
      local get, setv, default, kind, choices
      if it.guide then
        -- one number: a dungeon's area, a class quest chain's id negated, 0 none
        get = function()
          if not ns.cdb then return 0 end
          return ns.cdb.guide or (ns.cdb.classGuide and -ns.cdb.classGuide) or 0
        end
        setv = function(v)
          if v and v < 0 then ns.SetClassGuide(-v) else ns.SetGuide(v ~= 0 and v or nil) end
        end
        default, kind = 0, Var.Number
        choices = function()
          local out = { { 0, "None: the leveling route" } }
          for _, it2 in ipairs(ns.Viewer.GuideItems()) do out[#out + 1] = { it2.area, it2.text } end
          for _, it2 in ipairs(ns.Viewer.ClassItems()) do
            if it2.ready then out[#out + 1] = { -it2.chain, "Class: " .. it2.text } end
          end
          return out
        end
      elseif it.spec then
        get = function() return ns.cdb and ns.cdb.spec or 0 end
        setv = function(v) if ns.cdb then ns.cdb.spec = v end end
        default, kind, choices = 0, Var.Number, S.SpecChoices
      else
        get = function() return S.Get(it.key) end
        setv = function(v) S.Set(it.key, v) end
        default = ns.DEFAULT_SETTINGS[it.key]
        if it.choices then
          kind = it.number and Var.Number or Var.String
          choices = function() return it.choices end
        else
          kind = Var.Boolean
        end
      end
      local setting = Settings.RegisterProxySetting(category, "LVLS_" .. (it.key or (it.guide and "guide") or "spec"):upper(), kind,
        it.name, default, get, setv)
      if choices then
        Settings.CreateDropdown(category, setting, function()
          local c = Settings.CreateControlTextContainer()
          for _, o in ipairs(choices()) do c:Add(o[1], o[2]) end
          return c:GetData()
        end, it.tip)
      else
        Settings.CreateCheckbox(category, setting, it.tip)
      end
    end
  end
  Settings.RegisterAddOnCategory(category)
  S.category = category
end

function S.Open()
  if S.category and Settings.OpenToCategory then
    Settings.OpenToCategory(S.category:GetID())
    return true
  end
  return false
end

ns.Events.On("LVLS_LOADED", function() S.Register() end)

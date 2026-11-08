-- Gear: which quest reward to take and whether an item is an upgrade. Pure; the
-- game side (stats, equipped items, talents, Pawn) is Adapters/Gear.lua.
--
-- Spec: the talent tree with the most points spent (forever has classic talent
-- trees). No points yet (below level 10) means the class's leveling weights; a
-- spec chosen in the settings always wins. Pawn is never asked which spec you
-- are: several of its scales can be active at once.
--
-- Weights: Lvls' own per class / spec below (a rough leveling guide: primary stat
-- first, weapon damage for melee, spell power for casters), or a Pawn scale for
-- the same class and spec when Pawn is installed and the setting allows it.
local _, ns = ...
local G = ns:NewModule("Gear")

-- C_Item.GetItemStats keys -> short names used in the weights
G.STAT = {
  ITEM_MOD_STRENGTH_SHORT = "Str", ITEM_MOD_AGILITY_SHORT = "Agi", ITEM_MOD_STAMINA_SHORT = "Sta",
  ITEM_MOD_INTELLECT_SHORT = "Int", ITEM_MOD_SPIRIT_SHORT = "Spi", RESISTANCE0_NAME = "Armor",
  ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "Dps", ITEM_MOD_ATTACK_POWER_SHORT = "AP",
  ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "RAP", ITEM_MOD_SPELL_POWER_SHORT = "SP",
  ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "SP", ITEM_MOD_SPELL_HEALING_DONE_SHORT = "Heal",
  ITEM_MOD_CRIT_RATING_SHORT = "Crit", ITEM_MOD_CRIT_MELEE_RATING_SHORT = "Crit",
  ITEM_MOD_CRIT_RANGED_RATING_SHORT = "Crit", ITEM_MOD_CRIT_SPELL_RATING_SHORT = "Crit",
  ITEM_MOD_HIT_RATING_SHORT = "Hit", ITEM_MOD_HIT_MELEE_RATING_SHORT = "Hit",
  ITEM_MOD_HIT_RANGED_RATING_SHORT = "Hit", ITEM_MOD_HIT_SPELL_RATING_SHORT = "Hit",
  ITEM_MOD_HASTE_RATING_SHORT = "Haste", ITEM_MOD_MANA_REGENERATION_SHORT = "Mp5",
  ITEM_MOD_POWER_REGEN0_SHORT = "Mp5", ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "Def",
  ITEM_MOD_DODGE_RATING_SHORT = "Dodge", ITEM_MOD_PARRY_RATING_SHORT = "Parry",
  ITEM_MOD_BLOCK_RATING_SHORT = "Block", ITEM_MOD_BLOCK_VALUE_SHORT = "BlockValue",
  ITEM_MOD_MASTERY_RATING_SHORT = "Mastery", ITEM_MOD_VERSATILITY = "Vers",
}

local MELEE_STR = { Str = 1, Agi = 0.6, Sta = 0.35, AP = 0.45, Crit = 0.8, Hit = 0.9, Haste = 0.6,
  Mastery = 0.5, Vers = 0.5, Armor = 0.01, Dps = 3 }
local MELEE_AGI = { Agi = 1, Str = 0.5, Sta = 0.35, AP = 0.45, Crit = 0.8, Hit = 1, Haste = 0.7,
  Mastery = 0.5, Vers = 0.5, Armor = 0.005, Dps = 3 }
local TANK = { Sta = 1, Str = 0.5, Agi = 0.5, Armor = 0.05, Def = 0.9, Dodge = 0.8, Parry = 0.7,
  Block = 0.5, BlockValue = 0.3, Hit = 0.3, Vers = 0.5, Dps = 1 }
local HEALER = { Int = 1, Spi = 0.6, Heal = 0.8, SP = 0.8, Mp5 = 1, Sta = 0.3, Crit = 0.4,
  Haste = 0.5, Mastery = 0.4, Vers = 0.4, Armor = 0.002, Dps = 0.05 }
local CASTER = { Int = 0.8, SP = 1, Crit = 0.7, Hit = 1, Haste = 0.7, Spi = 0.3, Sta = 0.35, Mp5 = 0.3,
  Mastery = 0.5, Vers = 0.5, Armor = 0.002, Dps = 0.05 }
local function with(base, over)
  local t = {}
  for k, v in pairs(base) do t[k] = v end
  for k, v in pairs(over or {}) do t[k] = v end
  return t
end

-- Talent trees in the client's order; `leveling` is the tree whose weights apply
-- before any points are spent.
G.SPECS = {
  WARRIOR = { leveling = 1, { name = "Arms", w = MELEE_STR }, { name = "Fury", w = with(MELEE_STR, { Dps = 3.2 }) },
    { name = "Protection", w = TANK } },
  PALADIN = { leveling = 3, { name = "Holy", w = with(HEALER, { Spi = 0.3 }) },
    { name = "Protection", w = with(TANK, { Int = 0.3, SP = 0.4 }) }, { name = "Retribution", w = with(MELEE_STR, { Int = 0.2 }) } },
  HUNTER = { leveling = 1, { name = "Beast Mastery", w = with(MELEE_AGI, { Str = 0, RAP = 0.45, Int = 0.3, Dps = 2 }) },
    { name = "Marksmanship", w = with(MELEE_AGI, { Str = 0, RAP = 0.5, Int = 0.3, Dps = 2.2 }) },
    { name = "Survival", w = with(MELEE_AGI, { Str = 0, RAP = 0.45, Int = 0.3, Dps = 2 }) } },
  ROGUE = { leveling = 2, { name = "Assassination", w = MELEE_AGI }, { name = "Combat", w = with(MELEE_AGI, { Dps = 3.3 }) },
    { name = "Subtlety", w = MELEE_AGI } },
  PRIEST = { leveling = 3, { name = "Discipline", w = HEALER }, { name = "Holy", w = with(HEALER, { Spi = 0.8 }) },
    { name = "Shadow", w = with(CASTER, { Spi = 0.5 }) } },
  SHAMAN = { leveling = 2, { name = "Elemental", w = with(CASTER, { Mp5 = 0.6 }) },
    { name = "Enhancement", w = with(MELEE_STR, { Agi = 0.8, Int = 0.2 }) }, { name = "Restoration", w = HEALER } },
  MAGE = { leveling = 3, { name = "Arcane", w = with(CASTER, { Int = 1 }) }, { name = "Fire", w = CASTER }, { name = "Frost", w = CASTER } },
  WARLOCK = { leveling = 1, { name = "Affliction", w = with(CASTER, { Int = 0.6, Sta = 0.6 }) },
    { name = "Demonology", w = with(CASTER, { Int = 0.6, Sta = 0.7 }) }, { name = "Destruction", w = with(CASTER, { Int = 0.6, Sta = 0.5 }) } },
  DRUID = { leveling = 2, { name = "Balance", w = with(CASTER, { Spi = 0.4 }) },
    { name = "Feral", w = with(MELEE_AGI, { Str = 0.8, Sta = 0.6, Armor = 0.03, Dodge = 0.5, Dps = 0.3 }) },
    { name = "Restoration", w = with(HEALER, { Spi = 0.8 }) } },
}
G.FALLBACK = { Str = 0.5, Agi = 0.5, Int = 0.5, Sta = 0.5, Armor = 0.01, Dps = 1, SP = 0.5, AP = 0.3 }

-- The tree with the most points spent; nil when none has any (or a tie for the
-- most, which only happens with no points or an even split).
function G.SpecFromPoints(points)
  local best, bestN, tie = nil, 0, false
  for i, n in ipairs(points or {}) do
    if n > bestN then best, bestN, tie = i, n, false
    elseif n == bestN and n > 0 then tie = true end
  end
  if tie then return nil end
  return best
end

-- Spec in use: the override (1..3) when set, else the talents, else leveling.
-- Returns index, name, source ("override" | "talents" | "leveling").
function G.Spec(class, points, override)
  local specs = G.SPECS[class]
  if not specs then return nil, nil, "unknown" end
  if override and specs[override] then return override, specs[override].name, "override" end
  local i = G.SpecFromPoints(points)
  if i and specs[i] then return i, specs[i].name, "talents" end
  local l = specs.leveling
  return l, specs[l].name, "leveling"
end

function G.Weights(class, spec)
  local specs = G.SPECS[class]
  return specs and spec and specs[spec] and specs[spec].w or G.FALLBACK
end

-- Short-name stats from an API stat table.
function G.ShortStats(api)
  local out = {}
  for k, v in pairs(api or {}) do
    local s = G.STAT[k]
    if s and type(v) == "number" then out[s] = (out[s] or 0) + v end
  end
  return out
end

function G.Score(stats, weights)
  local t = 0
  for k, v in pairs(stats or {}) do t = t + v * (weights[k] or 0) end
  return t
end

-- inventory type -> the slots it can go in (inventory slot ids)
G.SLOTS = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 },
  INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
  INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
  INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 },
  INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 },
  INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 },
  INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

-- How much better `item` ({ equipLoc, score, link }) is than what is worn, and
-- the slot it goes in. equipped[slot] = { equipLoc, score, link } or nil (empty).
-- ctx.dualWield: one-handers may go in the off hand. Returns delta, slot; nil when
-- it cannot replace anything (not gear, an off hand next to a two-hander, the
-- very item already worn).
function G.Upgrade(item, equipped, ctx)
  local slots = item and G.SLOTS[item.equipLoc]
  if not slots then return nil end
  local function score(s) return equipped[s] and equipped[s].score or 0 end
  for _, s in ipairs(slots) do
    if equipped[s] and item.link and equipped[s].link == item.link and #slots > 1 then return nil end
  end
  local main = equipped[16]
  local twoHanded = main and main.equipLoc == "INVTYPE_2HWEAPON"
  if item.equipLoc == "INVTYPE_2HWEAPON" then
    return item.score - score(16) - score(17), 16
  end
  if item.equipLoc == "INVTYPE_WEAPON" then
    if twoHanded then return item.score - score(16), 16 end
    if not (ctx and ctx.dualWield) then return item.score - score(16), 16 end
    local s = score(16) <= score(17) and 16 or 17
    return item.score - score(s), s
  end
  if item.equipLoc == "INVTYPE_WEAPONMAINHAND" then return item.score - score(16), 16 end
  if slots[1] == 17 then
    if twoHanded then return nil end -- would take the two-hander off
    return item.score - score(17), 17
  end
  if #slots == 2 then
    local s = score(slots[1]) <= score(slots[2]) and slots[1] or slots[2]
    return item.score - score(s), s
  end
  return item.score - score(slots[1]), slots[1]
end

-- Which quest reward to take. choices[i] = { usable, delta (nil: not gear),
-- sell (copper for the whole stack) }. opts.upgrades: take the best usable upgrade;
-- opts.gold: otherwise the one that sells for most. Returns index and why
-- ("upgrade" | "gold"), or nil.
function G.ChooseReward(choices, opts)
  local best, bestDelta
  if opts.upgrades then
    for i, c in ipairs(choices) do
      if c.usable and c.delta and c.delta > 0 and (not bestDelta or c.delta > bestDelta) then best, bestDelta = i, c.delta end
    end
    if best then return best, "upgrade" end
  end
  if opts.gold then
    local most
    for i, c in ipairs(choices) do
      if (c.sell or 0) > 0 and (not most or c.sell > most) then best, most = i, c.sell end
    end
    if best then return best, "gold" end
  end
  return nil
end

-- May an upgrade be equipped automatically? item = { quality, bindsOnEquip (not
-- yet bound and binds when worn) }. opts = { equip, bind, maxQuality }: items that
-- would bind need opts.bind and a quality at most maxQuality (a blue that drops
-- can be kept to sell).
function G.MayEquip(item, opts)
  if not opts.equip then return false, "off" end
  if item.bindsOnEquip then
    if not opts.bind then return false, "binds" end
    if (item.quality or 0) > (opts.maxQuality or 2) then return false, "quality" end
  end
  return true
end

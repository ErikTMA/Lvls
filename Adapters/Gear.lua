-- Gear, game side: talents -> spec, item stats, what is worn, Pawn, equipping.
-- APIs (forever 1.60.1, Interface 16001; wow-ui-source branch forever):
--   C_SpecializationInfo.GetNumSpecializationsForClassID(classID) -> count
--   C_SpecializationInfo.GetSpecializationInfo(i) -> specId, name, description,
--     icon, role, primaryStat, pointsSpent, ...      (points per talent tree)
--   GetTalentTabInfo(i) -> ..., pointsSpent (5th)    (deprecation fallback)
--   C_Item.GetItemInfo(link) -> name, link, quality, level, minLevel, type,
--     subType, stackCount, equipLoc, texture, sellPrice, classID, subclassID, bindType
--   C_Item.GetItemStats(link) -> { ITEM_MOD_..._SHORT = n, RESISTANCE0_NAME = armor }
--   C_PlayerInfo.CanUseItem(itemID), CanDualWield(), GetInventoryItemLink("player", slot)
--   C_Container.GetContainerNumSlots / GetContainerItemLink, ItemLocation, C_Item.IsBound,
--   C_Item.GetItemGUID, C_Item.EquipItemByName(link, slot), EquipPendingItem(slot)
-- Pawn (third party, feature detected): PawnGetAllScalesEx() -> { { Name,
--   LocalizedName, IsVisible }, ... }, PawnGetItemData(link) -> item,
--   PawnGetSingleValueFromItem(item, scaleName) -> value. The scale is the one
--   picked on the Gear page (LvlsCharDB.pawnScale), never guessed; the spec always
--   comes from the talents (or the setting).
local _, ns = ...
local GA = ns:NewModule("GearData")
local Gear = ns.Gear

local function has(t, k) return type(t) == "table" and type(t[k]) == "function" end

function GA.Class()
  local _, token, id = UnitClass("player")
  token, id = ns.Util.plain(token), ns.Util.plain(id)
  -- secret: the class read before
  token, id = token or GA.lastToken, id or GA.lastId
  GA.lastToken, GA.lastId = token, id
  return token, id
end

-- Points spent per talent tree: from the trait tree (Adapters/Talents) when the game
-- has one, else the old per-spec API (forever has one spec per class there).
function GA.Points()
  local traits = ns.TalentsData and ns.TalentsData.Points()
  if traits then return traits end
  local _, classID = GA.Class()
  local n = 3
  if has(C_SpecializationInfo, "GetNumSpecializationsForClassID") and classID then
    n = C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or n
  end
  local points = {}
  for i = 1, n do
    local spent
    if has(C_SpecializationInfo, "GetSpecializationInfo") then
      spent = select(7, C_SpecializationInfo.GetSpecializationInfo(i))
    elseif type(GetTalentTabInfo) == "function" then
      spent = select(5, GetTalentTabInfo(i))
    end
    points[i] = tonumber(spent) or 0
  end
  return points
end

-- class token, spec index, spec name, source ("override" | "talents" | "leveling").
-- The spec picked for the talent build counts as the setting unless the Gear page's
-- spec is set.
function GA.Spec()
  local token = GA.Class()
  local override = ns.cdb and ns.cdb.spec
  if override == 0 then override = nil end
  if not override and ns.cdb and type(ns.cdb.talents) == "table" and not ns.cdb.talents.off then
    override = ns.cdb.talents.spec
  end
  local i, name, source = Gear.Spec(token, GA.Points(), override)
  return token, i, name, source
end

local function pawnReady()
  return has(_G, "PawnGetAllScalesEx") and has(_G, "PawnGetItemData") and has(_G, "PawnGetSingleValueFromItem")
end

-- Pawn's scales for the Stat weights dropdown: { { name, label }, ... }, the ones
-- shown in Pawn first; empty without Pawn.
function GA.PawnScales()
  if not pawnReady() then return {} end
  local ok, scales = pcall(PawnGetAllScalesEx)
  if not ok or type(scales) ~= "table" then return {} end
  local shown, hidden = {}, {}
  for _, s in ipairs(scales) do
    if type(s.Name) == "string" and s.Name ~= "" then
      local label = type(s.LocalizedName) == "string" and s.LocalizedName ~= "" and s.LocalizedName or s.Name
      if s.IsVisible then shown[#shown + 1] = { s.Name, label }
      else hidden[#hidden + 1] = { s.Name, label .. " (hidden in Pawn)" } end
    end
  end
  for _, o in ipairs(hidden) do shown[#shown + 1] = o end
  return shown
end

-- The Pawn scale this character picked, when Pawn still has it; else nil and why.
function GA.PawnScale()
  local pick = ns.cdb and ns.cdb.pawnScale
  if type(pick) ~= "string" or pick == "" then return nil end
  if not pawnReady() then return nil, "Pawn not installed" end
  for _, o in ipairs(GA.PawnScales()) do
    if o[1] == pick then return pick end
  end
  return nil, ("Pawn has no scale %s"):format(pick)
end

-- The scorer in use: function(link) -> score or nil (item data not loaded yet),
-- and a label for /lvls gear.
local warned = {}
function GA.Scorer()
  local token, spec, specName, source = GA.Spec()
  local scale, why = GA.PawnScale()
  if scale then
    return function(link)
      local ok, item = pcall(PawnGetItemData, link)
      if not ok or not item then return nil end
      local ok2, v = pcall(PawnGetSingleValueFromItem, item, scale)
      return ok2 and tonumber(v) or nil
    end, ("Pawn scale %s"):format(scale)
  end
  if why and not warned[why] then
    warned[why] = true
    ns.Log("warn", why .. ": using Lvls' own weights")
  end
  local w = Gear.Weights(token, spec)
  return function(link)
    if not has(C_Item, "GetItemStats") then return nil end
    local stats = C_Item.GetItemStats(link)
    if not stats then return nil end
    return Gear.Score(Gear.ShortStats(stats), w)
  end, ("Lvls weights (%s, %s)"):format(specName or "?", source)
end

-- Item facts or nil while the client has not loaded the item.
function GA.Info(link)
  if not link or not has(C_Item, "GetItemInfo") then return nil end
  local name, l, quality, _, minLevel, _, _, _, equipLoc, _, sellPrice, _, _, bindType = C_Item.GetItemInfo(link)
  if not name then return nil end
  local id = tonumber(tostring(l or link):match("item:(%d+)"))
  return { link = l or link, id = id, quality = quality, minLevel = minLevel or 0, equipLoc = equipLoc,
    sell = sellPrice or 0, bindType = bindType }
end

function GA.Usable(info)
  if not info then return false end
  if info.id and has(C_PlayerInfo, "CanUseItem") then return C_PlayerInfo.CanUseItem(info.id) and true or false end
  return (info.minLevel or 0) <= (UnitLevel("player") or 1)
end

function GA.Equipped(score)
  local out = {}
  for slot = 1, 18 do
    local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
    if link then
      local info = GA.Info(link)
      out[slot] = { link = link, equipLoc = info and info.equipLoc, score = score(link) or 0 }
    end
  end
  return out
end

-- How much better than what is worn; delta, slot (nil: not gear / not comparable).
function GA.Delta(link, score, equipped)
  local info = GA.Info(link)
  if not info or not Gear.SLOTS[info.equipLoc] then return nil end
  local s = score(link)
  if not s then return nil end
  equipped = equipped or GA.Equipped(score)
  local dual = type(CanDualWield) == "function" and CanDualWield() or false
  return Gear.Upgrade({ equipLoc = info.equipLoc, score = s, link = info.link }, equipped, { dualWield = dual })
end

-- Bag items: { bag, slot, link, guid, bound }
function GA.BagItems()
  local out = {}
  if not has(C_Container, "GetContainerNumSlots") then return out end
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
      local link = C_Container.GetContainerItemLink(bag, slot)
      if link then
        local loc = ItemLocation and ItemLocation.CreateFromBagAndSlot and ItemLocation:CreateFromBagAndSlot(bag, slot)
        local guid = loc and has(C_Item, "GetItemGUID") and C_Item.GetItemGUID(loc) or (bag .. ":" .. slot .. ":" .. link)
        local bound = loc and has(C_Item, "IsBound") and C_Item.IsBound(loc) or false
        out[#out + 1] = { bag = bag, slot = slot, link = link, guid = guid, bound = bound }
      end
    end
  end
  return out
end

function GA.Equip(link, slot)
  if has(C_Item, "EquipItemByName") then C_Item.EquipItemByName(link, slot) return true end
  if type(EquipItemByName) == "function" then EquipItemByName(link, slot) return true end
  return false
end

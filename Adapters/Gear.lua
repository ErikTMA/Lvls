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
--   PawnGetSingleValueFromItem(item, scaleName) -> value. Pawn only gives weights:
--   the spec always comes from the talents (or the setting).
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

-- Points spent per talent tree.
function GA.Points()
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

-- class token, spec index, spec name, source ("override" | "talents" | "leveling")
function GA.Spec()
  local token = GA.Class()
  local override = ns.cdb and ns.cdb.spec
  if override == 0 then override = nil end
  local i, name, source = Gear.Spec(token, GA.Points(), override)
  return token, i, name, source
end

-- Pawn scale for this class and spec: its name ends in ":<CLASS><n>" (Pawn's own
-- scales, e.g. "Classic":WARRIOR2) or its shown name names the spec.
function GA.PawnScale(token, spec, specName)
  if not (has(_G, "PawnGetAllScalesEx") and has(_G, "PawnGetItemData") and has(_G, "PawnGetSingleValueFromItem")) then
    return nil, "Pawn not installed"
  end
  if not token then return nil, "class not known yet" end
  local ok, scales = pcall(PawnGetAllScalesEx)
  if not ok or type(scales) ~= "table" then return nil, "Pawn scales unreadable" end
  local suffix = ":" .. token .. tostring(spec)
  local found
  for _, s in ipairs(scales) do
    local name = type(s.Name) == "string" and s.Name or ""
    local shown = type(s.LocalizedName) == "string" and s.LocalizedName:lower() or ""
    if name:upper():sub(-#suffix) == suffix:upper()
      or (specName and shown:find(specName:lower(), 1, true) and shown:find(token:lower(), 1, true)) then
      if s.IsVisible then return s.Name end
      found = found or s.Name
    end
  end
  if found then return nil, ("Pawn's scale %s is hidden; show it in Pawn to use it"):format(found) end
  return nil, "Pawn has no scale for " .. (specName or "this spec")
end

-- The scorer in use: function(link) -> score or nil (item data not loaded yet),
-- and a label for /lvls gear.
local warned = {}
function GA.Scorer()
  local token, spec, specName, source = GA.Spec()
  local mode = ns.db and ns.db.settings.gearWeights or "auto"
  if mode ~= "lvls" then
    local scale, why = GA.PawnScale(token, spec, specName)
    if scale then
      return function(link)
        local ok, item = pcall(PawnGetItemData, link)
        if not ok or not item then return nil end
        local ok2, v = pcall(PawnGetSingleValueFromItem, item, scale)
        return ok2 and tonumber(v) or nil
      end, ("Pawn scale %s (%s, %s)"):format(scale, specName or "?", source)
    end
    if mode == "pawn" and not warned[why] then
      warned[why] = true
      ns.Log("warn", why .. ": using Lvls' own weights")
    end
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

-- World map: quest givers, turn-ins and objective areas as map canvas pins.
-- Blizzard_MapCanvas (forever): a data provider (MapCanvasDataProviderMixin) added
-- to WorldMapFrame acquires pins by XML template (UI/MapPins.xml) on every map change.
local _, ns = ...
local MP = ns:NewModule("MapPins")

local TEMPLATE = "LvlsMapPinTemplate"

-- Filled with MapCanvasPinMixin's methods once the map canvas is loaded; the XML
-- template names this global, resolved when the first pin is created.
LvlsMapPinMixin = LvlsMapPinMixin or {}
local PinMixin = LvlsMapPinMixin

function PinMixin:OnLoad()
  if self.UseFrameLevelType then self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI") end
  if self.SetScalingLimits then self:SetScalingLimits(1, 1.0, 1.2) end
end

function PinMixin:OnAcquired(pin)
  self.pin = pin
  local size = ns.Style.Apply(self.Icon, pin)
  self:SetSize(size, size)
  self:SetPosition(pin.x / 100, pin.y / 100)
end

function PinMixin:OnMouseEnter()
  if not GameTooltip or not self.pin then return end
  local ds = ns.ActiveDataset()
  if not ds or not ns.char then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  for i, l in ipairs(ns.Style.TooltipLines(ds, ns.char, self.pin)) do
    if i == 1 then GameTooltip:SetText(l[1], l[2], l[3], l[4]) else GameTooltip:AddLine(l[1], l[2], l[3], l[4]) end
  end
  GameTooltip:Show()
end

function PinMixin:OnMouseLeave()
  if GameTooltip then GameTooltip:Hide() end
end

function PinMixin:OnClick(button)
  if button == "LeftButton" and self.pin then
    local ds = ns.ActiveDataset()
    local q = ds and ds.quests[self.pin.quest]
    ns.Game.Waypoint({ map = self:GetMap():GetMapID(), x = self.pin.x, y = self.pin.y }, q and q.n)
  end
end

local Provider = {}

function Provider:RemoveAllData()
  self:GetMap():RemoveAllPinsByTemplate(TEMPLATE)
end

function Provider:RefreshAllData()
  self:RemoveAllData()
  if not ns.db or not ns.db.settings.worldMap then return end
  local ds, char = ns.ActiveDataset(), ns.char
  local map = self:GetMap():GetMapID()
  if not ds or not char or not map then return end
  for _, pin in ipairs(MP.Pins(ds, char, map)) do
    self:GetMap():AcquirePin(TEMPLATE, pin)
  end
end

function MP.Pins(ds, char, map)
  local s = ns.db and ns.db.settings or {}
  return ns.Quests.MapPins(ds, char, map, {
    showLow = s.showLow, showTrivial = s.showTrivial, showDungeon = s.showDungeon,
    showRepeatable = s.showRepeatable, objectives = s.objectives,
  })
end

function MP.Attach()
  if MP.provider or not WorldMapFrame or not WorldMapFrame.AddDataProvider
    or not MapCanvasDataProviderMixin or not MapCanvasPinMixin then
    return MP.provider ~= nil
  end
  for k, v in pairs(MapCanvasPinMixin) do
    if PinMixin[k] == nil then PinMixin[k] = v end
  end
  local p = CreateFromMixins and CreateFromMixins(MapCanvasDataProviderMixin) or {}
  for k, v in pairs(Provider) do p[k] = v end
  WorldMapFrame:AddDataProvider(p)
  MP.provider = p
  return true
end

function MP.Refresh()
  if MP.provider and MP.provider.GetMap and MP.provider:GetMap() then MP.provider:RefreshAllData() end
end

ns.Events.On("LVLS_LOADED", function() MP.Attach() end)
ns.Events.On("LVLS_PINS", function() MP.Refresh() end)

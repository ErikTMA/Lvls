-- The minimap button: left-click opens the settings, right-click hides or shows the
-- guide (UI/Viewer.lua V.Show: the step viewer, Lvls!'s arrow and route lines).
-- Drag it round the edge of the minimap; where is saved as an angle
-- (LvlsDB.positions.minimapButton, degrees, 0 = east, counter-clockwise).
-- API (wow-ui-source branch forever): Button:RegisterForClicks / RegisterForDrag,
-- GetCursorPosition, Frame:GetEffectiveScale, Minimap:GetCenter.
local _, ns = ...
local MB = ns:NewModule("MinimapButton")

MB.ANGLE = 210   -- the default spot: lower left
MB.SIZE = 26
local button

local function angle()
  local p = ns.db and ns.db.positions and ns.db.positions.minimapButton
  return type(p) == "number" and p or MB.ANGLE
end

-- Offset from the minimap centre for an angle (degrees) and a radius. Pure.
function MB.Offset(deg, radius)
  local r = math.rad(deg)
  return math.cos(r) * radius, math.sin(r) * radius
end

-- The angle (degrees, 0..360) of a point seen from the centre. Pure.
function MB.Angle(cx, cy, x, y)
  return math.deg(math.atan2(y - cy, x - cx)) % 360
end

local function place()
  if not button then return end
  local radius = (ns.Util.plain(Minimap:GetWidth()) or 140) / 2 + 5
  local x, y = MB.Offset(angle(), radius)
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function tooltip(self)
  if not GameTooltip then return end
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:SetText(ns.displayName or "Lvls!")
  GameTooltip:AddLine("Left-click: settings", 1, 1, 1)
  GameTooltip:AddLine(ns.Viewer.Shown() and "Right-click: hide the guide" or "Right-click: show the guide", 1, 1, 1)
  GameTooltip:AddLine("Drag: move the button", 0.7, 0.7, 0.7)
  GameTooltip:Show()
end

function MB.Click(btn)
  if btn == "RightButton" then
    ns.Viewer.Show(not ns.Viewer.Shown())
  elseif ns.Slash then
    ns.Slash("settings")
  end
end

local function create()
  local b = CreateFrame("Button", "LvlsMinimapButton", Minimap)
  b:SetSize(MB.SIZE, MB.SIZE)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  -- its own round badge (Media/MinimapIcon: drawn for this size; the painted logo
  -- blurs into a squiggle here), no border of the client's round it
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetTexture("Interface\\AddOns\\Lvls\\Media\\MinimapIcon")
  b.icon:SetAllPoints(b)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetTexture("Interface\\AddOns\\Lvls\\Media\\MinimapIcon")
  hl:SetAllPoints(b)
  hl:SetBlendMode("ADD")
  hl:SetAlpha(0.35)
  b:SetScript("OnClick", function(self, btn)
    MB.Click(btn)
    if GameTooltip and GameTooltip:IsOwned(self) then tooltip(self) end
  end)
  b:SetScript("OnEnter", tooltip)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local cx, cy = Minimap:GetCenter()
      local x, y = GetCursorPosition()
      local s = Minimap:GetEffectiveScale()
      if not cx or not x or not s then return end
      ns.db.positions = ns.db.positions or {}
      ns.db.positions.minimapButton = MB.Angle(cx, cy, x / s, y / s)
      place()
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  return b
end

-- Shown or not by its setting.
function MB.Apply()
  if not CreateFrame or not Minimap or not ns.db then return end
  local on = ns.db.settings.minimapButton
  if not on then
    if button then button:Hide() end
    return
  end
  if not button then button = create(); MB.button = button end
  place()
  button:Show()
end

ns.Events.On("LVLS_LOADED", function() MB.Apply() end)
ns.Events.On("LVLS_UPDATED", function() MB.Apply() end)

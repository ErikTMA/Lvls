-- The flight master's map: the flight point the trip flies to is ringed (green,
-- pulsing, "Fly here") and the way there drawn, as when you point at it.
--
-- Both flight maps the client has (wow-ui-source branch forever):
--   TaxiFrame (Blizzard_UIPanels_Game/Shared/TaxiFrame.lua): buttons TaxiButton<i>,
--     i = 1..NumTaxiNodes(), TaxiNodeName(i), TaxiNodeGetType(i) ("REACHABLE", ...);
--     TaxiNodeOnButtonEnter(button) draws the route to a node, TaxiNodeOnButtonLeave
--     hides the tooltip and keeps the route.
--   FlightMapFrame (Blizzard_FlightMap, loaded on demand): pins
--     "FlightMap_FlightPointPinTemplate" with taxiNodeData { nodeID, name, state };
--     its flight path provider's HighlightRouteToPin(pin) draws the route.
local _, ns = ...
local FM = ns:NewModule("FlightMap")

local GREEN = { 0.2, 1, 0.3 }

local function short(name) return (tostring(name or ""):gsub(",.*$", "")) end

-- Where the trip flies first: { node = id, name } or nil. Pure.
function FM.Target(trip)
  for _, l in ipairs(trip and trip.legs or {}) do
    if l.mode == "fly" and (l.node or l.nodeName) then return { node = l.node, name = l.nodeName } end
  end
end

-- The TaxiFrame slot of the target, a node you can fly to. Pure.
function FM.Slot(target, n, nameOf, typeOf)
  if not target or not target.name then return nil end
  for i = 1, n do
    if short(nameOf(i)) == target.name and typeOf(i) == "REACHABLE" then return i end
  end
end

local function target()
  if not (ns.db and ns.db.settings.mapRoute) then return nil end
  return FM.Target(ns.trip)
end

-- a ring around a button / pin, pulsing, with "Fly here" under it
local function ring(owner)
  local r = owner.lvlsRing
  if not r then
    r = CreateFrame("Frame", nil, owner)
    r:SetFrameLevel((owner:GetFrameLevel() or 1) + 5)
    r.tex = r:CreateTexture(nil, "OVERLAY")
    r.tex:SetTexture("Interface\\AddOns\\Lvls\\Media\\Ring")
    r.tex:SetAllPoints(r)
    r.tex:SetVertexColor(GREEN[1], GREEN[2], GREEN[3])
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.text:SetPoint("TOP", r, "BOTTOM", 0, 2)
    r.text:SetText("Fly here")
    r.text:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
    local ag = r.CreateAnimationGroup and r:CreateAnimationGroup()
    if ag then
      ag:SetLooping("BOUNCE")
      local a = ag:CreateAnimation("Alpha")
      a:SetFromAlpha(1); a:SetToAlpha(0.35); a:SetDuration(0.6)
      r.pulse = ag
    end
    owner.lvlsRing = r
  end
  local w = owner:GetWidth() or 16
  r:SetSize(w * 2.2, w * 2.2)
  r:ClearAllPoints()
  r:SetPoint("CENTER", owner, "CENTER", 0, 0)
  r:Show()
  if r.pulse then r.pulse:Play() end
  return r
end

local rung = {}
local function clear()
  for _, r in ipairs(rung) do r:Hide(); if r.pulse then r.pulse:Stop() end end
  rung = {}
end

-- TaxiFrame opened: ring the target and draw its route. Returns the slot or nil.
function FM.OnTaxiShow()
  clear()
  local t = target()
  if not t or not NumTaxiNodes or not TaxiNodeName or not TaxiNodeGetType then return nil end
  local i = FM.Slot(t, NumTaxiNodes(), TaxiNodeName, TaxiNodeGetType)
  local b = i and _G["TaxiButton" .. i]
  if not b then return nil end
  if TaxiNodeOnButtonEnter then
    pcall(TaxiNodeOnButtonEnter, b)
    if TaxiNodeOnButtonLeave then pcall(TaxiNodeOnButtonLeave, b) end
  end
  rung[#rung + 1] = ring(b)
  return i
end

-- FlightMapFrame: the pin of the target, ringed, its route drawn. Returns the pin.
function FM.OnFlightMapShow(map)
  clear()
  local t = target()
  if not t or not map or not map.EnumeratePinsByTemplate then return nil end
  local found
  for pin in map:EnumeratePinsByTemplate("FlightMap_FlightPointPinTemplate") do
    local d = pin.taxiNodeData
    if d and ((t.node and d.nodeID == t.node) or (not t.node and short(d.name) == t.name)) then found = pin; break end
  end
  if not found then return nil end
  for p in pairs(map.dataProviders or {}) do
    if type(p) == "table" and p.HighlightRouteToPin then pcall(p.HighlightRouteToPin, p, found); break end
  end
  rung[#rung + 1] = ring(found)
  return found
end

local hookedTaxi, hookedFlight
function FM.Attach()
  if not hookedTaxi and TaxiFrame and TaxiFrame.HookScript then
    -- after Blizzard's OnShow, which lays out the buttons and the one-hop lines
    TaxiFrame:HookScript("OnShow", function() FM.OnTaxiShow() end)
    TaxiFrame:HookScript("OnHide", clear)
    hookedTaxi = true
  end
  if not hookedFlight and FlightMapFrame and FlightMapFrame.HookScript then
    -- next frame: after every provider has made its pins
    FlightMapFrame:HookScript("OnShow", function(self)
      if C_Timer and C_Timer.After then C_Timer.After(0, function() FM.OnFlightMapShow(self) end)
      else FM.OnFlightMapShow(self) end
    end)
    FlightMapFrame:HookScript("OnHide", clear)
    hookedFlight = true
  end
end

ns.Events.On("LVLS_LOADED", function() FM.Attach() end)
-- Blizzard_FlightMap loads when a flight master is first spoken to
local f = CreateFrame and CreateFrame("Frame")
if f then
  f:RegisterEvent("ADDON_LOADED")
  f:SetScript("OnEvent", function(_, _, name) if name == "Blizzard_FlightMap" then FM.Attach() end end)
end

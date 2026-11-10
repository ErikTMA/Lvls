-- World map: the route ahead as numbered waypoints joined by a line, starting where
-- you stand (the current step's dot is the accent colour, the line to it solid; the
-- steps after it are lighter).
--
-- Drawn on a frame of its own on the map canvas, textures and lines only: no pins,
-- so nothing here is a protected call in combat (MapPins has to wait for it to end).
-- API (wow-ui-source branch forever): WorldMapFrame:AddDataProvider(provider);
-- MapCanvasDataProviderMixin:OnMapChanged / OnCanvasScaleChanged / RefreshAllData;
-- MapCanvasMixin:GetCanvas(), :GetCanvasScale(), :GetPinFrameLevelsManager()
-- :GetValidFrameLevel(type); Frame:CreateLine(), Line:SetStartPoint / SetEndPoint /
-- SetThickness (Blizzard_FlightMap draws its routes the same way);
-- C_Map.GetPlayerMapPosition(map, "player").
local _, ns = ...
local MR = ns:NewModule("MapRoute")

MR.AHEAD = 10      -- steps drawn after the current one
MR.MERGE = 0.004   -- points this close on the map (0..1) are one waypoint ("3-4")
MR.DOT = 18        -- dot size and line thickness on screen, whatever the zoom
MR.LINE = 3
local ACCENT = { 1, 0.48, 0.1 }
MR.ACCENT = ACCENT
local AHEAD_COLOR = { 1, 0.86, 0.55 }
MR.AHEAD_COLOR = AHEAD_COLOR

-- The waypoints of `steps` from step `from` on, placed on a map. Pure.
--   project(spot) -> x, y (0..1) or nil when the spot is not on the map
--   lead          optional { spot, title }: where the arrow points first on the way
--                 to the current step (the flight master), drawn before it
-- Returns { { x, y, n, last, title, current, travel, gap }, ... }: n..last are the
-- step numbers at the point; gap = a step before it is off this map (no line to it).
function MR.Points(steps, from, project, lead, ahead)
  local out, gap = {}, false
  if not steps or not from then return out end
  if lead and lead.spot then
    local x, y = project(lead.spot)
    if x then out[1] = { x = x, y = y, title = lead.title, travel = true } end
  end
  for i = from, math.min(#steps, from + (ahead or MR.AHEAD)) do
    local st = steps[i]
    local x, y
    if st.spot then x, y = project(st.spot) end
    if not x then
      gap = #out > 0
    else
      local prev = out[#out]
      if prev and not gap and not prev.travel and math.abs(prev.x - x) <= MR.MERGE and math.abs(prev.y - y) <= MR.MERGE then
        prev.last = i
      else
        out[#out + 1] = { x = x, y = y, n = i, last = i, title = st.title, current = i == from, gap = gap }
      end
      gap = false
    end
  end
  return out
end

-- "3", or "3-4" for steps at one place
function MR.Label(p)
  if not p.n then return "" end
  if p.last and p.last ~= p.n then return p.n .. "-" .. p.last end
  return tostring(p.n)
end

-- --- drawing ------------------------------------------------------------------------

local Provider = {}
local layer -- the frame on the canvas, with pools of waypoints and lines

local function enabled() return ns.db and ns.db.settings.mapRoute and (not ns.Viewer or ns.Viewer.Shown()) end

local function lead()
  local trip = ns.trip
  if not trip or not trip.legs or #trip.legs <= 1 then return nil end
  local spot, title = ns.Travel.NextSpot(trip)
  return spot and { spot = spot, title = title } or nil
end

local function ensureLayer(map)
  if layer then return layer end
  local canvas = map:GetCanvas()
  layer = CreateFrame("Frame", nil, canvas)
  layer:SetAllPoints(canvas)
  local level
  local fl = map.GetPinFrameLevelsManager and map:GetPinFrameLevelsManager()
  if fl and fl.GetValidFrameLevel then
    local ok, v = pcall(fl.GetValidFrameLevel, fl, "PIN_FRAME_LEVEL_MAP_HIGHLIGHT")
    if ok then level = v end
  end
  layer:SetFrameLevel(level or ((canvas:GetFrameLevel() or 1) + 1))
  layer.dots, layer.lines = {}, {}
  local acc = 0
  layer:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + (elapsed or 0)
    if acc >= 0.2 then acc = 0; MR.Tick() end
  end)
  return layer
end

local function item(pool, i, make)
  local v = pool[i]
  if not v then v = make(); pool[i] = v end
  v:Show()
  return v
end

local function hideFrom(pool, n)
  for i = n, #pool do pool[i]:Hide() end
end

local function placeLine(l, ax, ay, bx, by, color, alpha, thick)
  local w, h = layer:GetWidth() or 0, layer:GetHeight() or 0
  l:SetStartPoint("TOPLEFT", layer, ax * w, -ay * h)
  l:SetEndPoint("TOPLEFT", layer, bx * w, -by * h)
  l:SetThickness(thick)
  l:SetColorTexture(color[1], color[2], color[3], alpha)
end

local function scale(map)
  local s = map.GetCanvasScale and map:GetCanvasScale()
  return (type(s) == "number" and s > 0) and s or 1
end

local function playerXY(mapID)
  if not (C_Map and C_Map.GetPlayerMapPosition) then return nil end
  local v = C_Map.GetPlayerMapPosition(mapID, "player")
  if not v then return nil end
  local x, y
  if v.GetXY then x, y = v:GetXY() else x, y = v.x, v.y end
  x, y = ns.Util.plain(x), ns.Util.plain(y) -- secret in some places
  if type(x) ~= "number" or type(y) ~= "number" or (x == 0 and y == 0) then return nil end
  return x, y
end

-- Draw the route on `map` (a MapCanvas). Returns the points drawn.
function MR.Draw(map)
  local mapID = map and map.GetMapID and map:GetMapID()
  if not mapID then return {} end
  ensureLayer(map)
  local way = ns.Ground and ns.Ground.Leading() or nil
  MR.drawn = { steps = ns.steps, from = ns.stepIndex, trip = ns.trip, map = mapID, on = enabled(), way = way }
  local pts = {}
  if enabled() and ns.steps and ns.stepIndex then
    pts = MR.Points(ns.steps, ns.stepIndex, function(spot) return ns.Game.geo.onMap(spot, mapID) end, lead())
  end
  local s = scale(map)
  local thick = MR.LINE / s
  local w, h = layer:GetWidth() or 0, layer:GetHeight() or 0
  local nl = 0
  for i, p in ipairs(pts) do
    -- a waypoint: a small frame at 1 / zoom, so it keeps its size on screen (its
    -- anchor offsets are in its own scale: times the zoom)
    local d = item(layer.dots, i, function()
      local f = CreateFrame("Frame", nil, layer)
      f:SetSize(MR.DOT, MR.DOT)
      f.dot = f:CreateTexture(nil, "OVERLAY")
      f.dot:SetTexture("Interface\\AddOns\\Lvls\\Media\\Dot")
      f.dot:SetAllPoints(f)
      f.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      f.label:SetPoint("CENTER", f, "CENTER", 0, 0)
      f.label:SetTextColor(0.1, 0.1, 0.1)
      return f
    end)
    local c = (p.current or p.travel) and ACCENT or AHEAD_COLOR
    d.dot:SetVertexColor(c[1], c[2], c[3])
    d:SetAlpha((p.current or p.travel) and 1 or 0.85)
    d:SetScale(1 / s)
    d:ClearAllPoints()
    d:SetPoint("CENTER", layer, "TOPLEFT", p.x * w * s, -p.y * h * s)
    d.label:SetText(MR.Label(p))
    local prev = pts[i - 1]
    if prev and not p.gap then
      nl = nl + 1
      local l = item(layer.lines, nl, function() return layer:CreateLine(nil, "ARTWORK") end)
      local near = p.current or prev.travel
      placeLine(l, prev.x, prev.y, p.x, p.y, near and ACCENT or AHEAD_COLOR, near and 0.9 or 0.6, thick)
    end
  end
  hideFrom(layer.dots, #pts + 1)
  -- from where you stand to the first waypoint (the way on foot draws that stretch
  -- itself when it leads there, around the walls: UI/Ground.lua)
  layer.playerLine = nil
  local first = pts[1]
  if first and (first.current or first.travel) and not first.gap and not way then
    local px, py = playerXY(mapID)
    if px then
      nl = nl + 1
      local l = item(layer.lines, nl, function() return layer:CreateLine(nil, "ARTWORK") end)
      placeLine(l, px, py, first.x, first.y, ACCENT, 0.9, thick)
      layer.playerLine = { line = l, x = first.x, y = first.y, thick = thick, map = mapID }
    end
  end
  hideFrom(layer.lines, nl + 1)
  return pts
end

-- While the map is open: draw again when the plan moved on, else follow the player.
function MR.Tick()
  local map = MR.provider and MR.provider:GetMap()
  if not map or not layer then return end
  local d = MR.drawn or {}
  local mapID = map:GetMapID()
  if d.steps ~= ns.steps or d.from ~= ns.stepIndex or d.trip ~= ns.trip or d.map ~= mapID or d.on ~= enabled()
    or d.way ~= (ns.Ground and ns.Ground.Leading() or nil) then
    MR.Draw(map)
    return
  end
  local pl = layer.playerLine
  if pl then
    local px, py = playerXY(mapID)
    if px then placeLine(pl.line, px, py, pl.x, pl.y, ACCENT, 0.9, pl.thick) else pl.line:Hide() end
  end
end

function Provider:RemoveAllData()
  if layer then hideFrom(layer.dots, 1); hideFrom(layer.lines, 1); layer.playerLine = nil end
end

function Provider:RefreshAllData()
  MR.Draw(self:GetMap())
end

function Provider:OnMapChanged() self:RefreshAllData() end
function Provider:OnCanvasScaleChanged() self:RefreshAllData() end
function Provider:OnCanvasSizeChanged() self:RefreshAllData() end

function MR.Attach()
  if MR.provider or not WorldMapFrame or not WorldMapFrame.AddDataProvider or not MapCanvasDataProviderMixin then
    return MR.provider ~= nil
  end
  local p = CreateFromMixins and CreateFromMixins(MapCanvasDataProviderMixin) or {}
  for k, v in pairs(Provider) do p[k] = v end
  WorldMapFrame:AddDataProvider(p)
  MR.provider = p
  return true
end

ns.Events.On("LVLS_LOADED", function() MR.Attach() end)

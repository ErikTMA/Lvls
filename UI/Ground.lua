-- The way on foot: where the arrow should walk you is often behind a wall, a
-- building or up a cliff. This finds the way there (Engine/Nav over the client's
-- own map data, Data/forever/Nav*.lua) and leads along it, but only where the
-- straight line would not do (Nav.Worth: a cave, a mountain path, a walled city;
-- how readily is the "Lead the way on foot" sliders: one for out in the world, one
-- for inside buildings and caves; the one for where you stand, looked at again as
-- you go in or out):
--   * the arrow points at the next turn and counts the yards left along the way
--   * the world map draws the way as a line
--   * the game's own waypoint (nativeArrow) stays on the goal
-- Where the straight line does, the plain arrow; it looks again when you are halfway
-- there (the cave may only start near the end).
-- The search runs a few milliseconds per frame (a long way across a continent takes
-- a few hundred); the old way stays shown until the new one is ready.
local _, ns = ...
local GR = ns:NewModule("Ground")
local N = ns.Nav

GR.MIN_YARDS = 40     -- closer than this: the arrow points straight at it
GR.REACH = 6          -- yards: a corner counts as reached
GR.OFF_ROUTE = 30     -- yards away from the way: look for a new one
GR.REPLAN_SECS = 3    -- not more often than this
GR.BUDGET_MS = 4      -- search time per frame
GR.async = true       -- tests switch the search to one go
GR.route = nil        -- { cont, pts = { { x, y }, ... }, i, length, key, at }
GR.want = nil         -- the spot the way should lead to, { map, x, y }
GR.straight = nil     -- the straight line does: { key, x, y, d } (world, from where)
GR.RECHECK = 0.5      -- look again after this part of the straight line
GR.RECHECK_MIN = 60   -- yards: but not sooner than this

local job             -- the search running now
local corner = {}     -- the next corner on the player's map, reused
local cornerFor       -- route, index and map `corner` was made for
local lastX, lastY, lastMap
local nextYards

local function indoors() return ns.Game.Indoors and ns.Game.Indoors() or false end
local function help()
  local s = ns.db and ns.db.settings
  if not s then return 0 end
  if indoors() then return s.groundHelpIndoors or s.groundHelp or 0 end
  return s.groundHelp or 0
end
local function on() return help() > 0 end
-- either slider leads somewhere: keep the goal (you may walk in or out)
local function any()
  local s = ns.db and ns.db.settings
  return s and ((s.groundHelp or 0) > 0 or (s.groundHelpIndoors or 0) > 0) or false
end
local plannedIn       -- indoors() when the way was last looked for
local function now() return GetTime and GetTime() or 0 end
local function ms()
  if debugprofilestop then return debugprofilestop() end
  return os.clock() * 1000
end
local function keyOf(spot)
  return ("%d:%.1f:%.1f"):format(spot.map, spot.x, spot.y)
end

local function changed()
  cornerFor = nil
  if GR.Redraw then GR.Redraw() end
end

function GR.Clear()
  GR.want, GR.route, job, GR.straight = nil, nil, nil, nil
  nextYards = nil
  changed()
end

local function finish(j, pts, length)
  if job ~= j then return end
  job = nil
  if not GR.want or keyOf(GR.want) ~= j.key then return end
  if not pts then
    -- no way on foot (another floor of a city, an island): the plain arrow
    if GR.route and GR.route.key == j.key then GR.route = nil; changed() end
    return
  end
  if not N.Worth(pts, length, help()) then
    -- the straight line does: the plain arrow, until you are part of the way there
    local a, b = pts[1], pts[#pts]
    local dx, dy = b.x - a.x, b.y - a.y
    GR.straight = { key = j.key, x = a.x, y = a.y, d = math.sqrt(dx * dx + dy * dy) }
    if GR.route then GR.route = nil; changed() end
    return
  end
  GR.straight = nil
  GR.route = { cont = j.cont, pts = N.Simplify(pts), i = 1, length = length, key = j.key, at = now() }
  changed()
end

-- Look for the way from the player to GR.want.
local function plan()
  local goal = GR.want
  plannedIn = indoors()
  if not on() then
    -- the slider for where you stand says the straight line
    job, GR.straight = nil, nil
    if GR.route then GR.route = nil; changed() end
    return
  end
  local pos = ns.Game.Position({})
  if not goal or not pos then return end
  local geo = ns.Game.geo
  local c1, ax, ay = geo.worldNow(pos.map, pos.x, pos.y)
  local c2, bx, by = geo.world(goal.map, goal.x, goal.y)
  if not c1 or c1 ~= c2 or not N.Graph(c1) then GR.route = nil; changed(); return end
  local dx, dy = ax - bx, ay - by
  if dx * dx + dy * dy < GR.MIN_YARDS * GR.MIN_YARDS then GR.route = nil; changed(); return end
  local j = { key = keyOf(goal), cont = c1 }
  job = j
  if not GR.async then
    local pts, length = N.Route(c1, ax, ay, bx, by)
    finish(j, pts, length)
    return
  end
  j.co = coroutine.create(function()
    return N.Route(c1, ax, ay, bx, by, function()
      if ms() > j.deadline then coroutine.yield() end
    end)
  end)
end

-- Run the search for up to `budget` ms (every frame while one runs).
function GR.Step(budget)
  local j = job
  if not j or not j.co then return false end
  j.deadline = ms() + (budget or GR.BUDGET_MS)
  local ok, pts, length = coroutine.resume(j.co)
  if not ok then
    ns.Log("debug", "ground route: " .. tostring(pts))
    if job == j then job = nil end
    return false
  end
  if coroutine.status(j.co) == "dead" then finish(j, pts, length) end
  return job ~= nil
end

function GR.Busy() return job ~= nil end

-- The way being followed now (UI/MapRoute.lua leaves out its straight line from
-- the player then), or nil.
function GR.Leading()
  if on() and GR.route then return GR.route end
  return nil
end

-- Where the arrow leads now (ns.RefreshTravel): the end of the trip's first walk.
-- nil: no goal, the plain arrow.
function GR.Want(spot)
  if not any() or not spot then
    if GR.want or GR.route or job then GR.Clear() end
    return
  end
  local key = keyOf(spot)
  if GR.want and keyOf(GR.want) == key and plannedIn == indoors() and (GR.route or job or not on()) then return end
  if GR.straight and GR.straight.key == key and GR.want and keyOf(GR.want) == key and plannedIn == indoors() then return end
  GR.straight = nil
  GR.want = { map = spot.map, x = spot.x, y = spot.y }
  -- a new goal: the old way leads elsewhere
  if GR.route and GR.route.key ~= key then GR.route = nil; changed() end
  plan()
end

-- The next corner for the arrow: a spot on the player's map, and the yards left
-- along the way. nil when there is no way to follow (the arrow points at its target).
-- Called every arrow update; does its work only when the player moved.
function GR.Next(pos)
  -- went in or out: the other slider decides
  if GR.want and plannedIn ~= indoors() then GR.straight = nil; plan() end
  if not on() then return nil end
  local r = GR.route
  local s = GR.straight
  if not r and s and pos and not job then
    -- the straight line did from back there: look again when you are part of the way
    local _, px, py = ns.Game.geo.worldNow(pos.map, pos.x, pos.y)
    if px then
      local dx, dy = px - s.x, py - s.y
      local far = math.max(GR.RECHECK_MIN, s.d * GR.RECHECK)
      if dx * dx + dy * dy >= far * far then GR.straight = nil; plan() end
    end
    return nil
  end
  if not r or not pos then return nil end
  if pos.x ~= lastX or pos.y ~= lastY or pos.map ~= lastMap then
    lastX, lastY, lastMap = pos.x, pos.y, pos.map
    local c, px, py = ns.Game.geo.worldNow(pos.map, pos.x, pos.y)
    if c ~= r.cont then return nil end
    local i = N.Advance(r.pts, r.i, px, py, GR.REACH)
    if i ~= r.i then r.i = i; changed() end
    -- wandered off: a new way (the old one stays until it is ready)
    local prev = r.pts[r.i - 1] or r.pts[1]
    if not job and N.SegmentDistance(px, py, prev, r.pts[r.i]) > GR.OFF_ROUTE
      and now() - r.at >= GR.REPLAN_SECS then
      r.at = now()
      plan()
    end
    nextYards = N.Remaining(r.pts, r.i, px, py)
  end
  -- the last point is the goal itself: the arrow goes there on its own
  if r.i >= #r.pts then return nil end
  if cornerFor ~= r.pts[r.i] or corner.map ~= pos.map then
    local p = r.pts[r.i]
    local x, y = ns.Game.geo.mapPos(r.cont, p.x, p.y, pos.map)
    if not x then return nil end
    corner.map, corner.x, corner.y = pos.map, x, y
    cornerFor = p
  end
  return corner, nextYards
end

-- Driver: steps the search while one runs.
local driver = CreateFrame and CreateFrame("Frame")
if driver then
  driver:SetScript("OnUpdate", function() if job then GR.Step(GR.BUDGET_MS) end end)
end

---------------------------------------------------------------------------
-- World map: the way as a line, from the player through the corners left.
-- Own frame on the canvas with plain lines (no pins: nothing protected in combat).
-- The canvas zooms by scaling: line thickness is divided by the canvas scale.
GR.LINE = 3
GR.COLOR = { 1, 0.48, 0.1, 0.9 }  -- the route's accent (UI/MapRoute.lua): it is its first stretch

local Provider = {}
local layer, lines = nil, {}
local projected = { key = nil }   -- the corners projected on the shown map

function GR.MapPoints(map, px, py)
  -- the way left, as map fractions on `map`: player first. nil entries break the line
  local r = GR.route
  if not r or not map then return {} end
  local key = tostring(r) .. ":" .. map
  if projected.key ~= key then
    projected = { key = key }
    for k, p in ipairs(r.pts) do
      local x, y = ns.Game.geo.mapPos(r.cont, p.x, p.y, map)
      if x and x >= 0 and x <= 100 and y >= 0 and y <= 100 then projected[k] = { x / 100, y / 100 } else projected[k] = false end
    end
  end
  local out = {}
  if px then out[1] = { px, py } else out[1] = false end
  for k = r.i, #r.pts do out[#out + 1] = projected[k] end
  return out
end

local function draw(provider)
  local map = provider:GetMap()
  if not map or not map.GetCanvas then return end
  if not layer then
    local canvas = map:GetCanvas()
    if not canvas then return end
    layer = CreateFrame("Frame", nil, canvas)
    layer:SetAllPoints(canvas)
    if layer.SetFrameLevel and canvas.GetFrameLevel then layer:SetFrameLevel(canvas:GetFrameLevel() + 5) end
  end
  for _, l in ipairs(lines) do l:Hide() end
  if not on() or not GR.route or (ns.Viewer and not ns.Viewer.Shown()) then return end
  local mapID = map:GetMapID()
  local px, py
  if C_Map and C_Map.GetPlayerMapPosition then
    local v = C_Map.GetPlayerMapPosition(mapID, "player")
    if v then
      if v.GetXY then px, py = v:GetXY() else px, py = v.x, v.y end
      px, py = ns.Util.plain(px), ns.Util.plain(py)
      if not px or not py or (px == 0 and py == 0) then px, py = nil, nil end
    end
  end
  local pts = GR.MapPoints(mapID, px, py)
  local w, h = layer:GetWidth() or 0, layer:GetHeight() or 0
  local scale = map.GetCanvasScale and map:GetCanvasScale() or 1
  local n = 0
  for k = 2, #pts do
    local a, b = pts[k - 1], pts[k]
    if a and b then
      n = n + 1
      local l = lines[n]
      if not l then
        l = layer:CreateLine(nil, "OVERLAY")
        lines[n] = l
      end
      local c = ns.MapRoute and ns.MapRoute.ACCENT or GR.COLOR
      l:SetColorTexture(c[1], c[2], c[3], GR.COLOR[4])
      l:SetThickness(GR.LINE / scale)
      l:SetStartPoint("TOPLEFT", layer, a[1] * w, -a[2] * h)
      l:SetEndPoint("TOPLEFT", layer, b[1] * w, -b[2] * h)
      l:Show()
    end
  end
  GR.drawn = n
end

-- drawing must never break what called it (a refresh, the arrow): logged once
local drawFailed
local function safeDraw(provider)
  local ok, err = pcall(draw, provider)
  if not ok and not drawFailed then drawFailed = true; ns.Log("debug", "ground route map: " .. tostring(err)) end
end

function Provider:RemoveAllData()
  for _, l in ipairs(lines) do l:Hide() end
end
function Provider:RefreshAllData() safeDraw(self) end
function Provider:OnCanvasScaleChanged() safeDraw(self) end

function GR.Redraw()
  local p = GR.provider
  local map = p and p.GetMap and p:GetMap()
  if map and (not map.IsShown or map:IsShown()) then safeDraw(p) end
end

function GR.Attach()
  if GR.provider or not WorldMapFrame or not WorldMapFrame.AddDataProvider or not MapCanvasDataProviderMixin then
    return GR.provider ~= nil
  end
  local p = CreateFromMixins and CreateFromMixins(MapCanvasDataProviderMixin) or {}
  for k, v in pairs(Provider) do p[k] = v end
  WorldMapFrame:AddDataProvider(p)
  GR.provider = p
  -- the player moves while the map is open: the line follows (a few times a second)
  local acc = 0
  if WorldMapFrame.HookScript then
    WorldMapFrame:HookScript("OnUpdate", function(_, elapsed)
      acc = acc + (elapsed or 0)
      if acc >= 0.2 then acc = 0; if GR.route then safeDraw(p) end end
    end)
  end
  return true
end

ns.Events.On("LVLS_LOADED", function() GR.Attach() end)
ns.Events.On("LVLS_GUIDE", function() GR.Redraw() end)

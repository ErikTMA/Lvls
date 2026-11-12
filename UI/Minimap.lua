-- Minimap: givers, turn-ins and objective area centres of the zone you are in, of
-- the quests the guide's steps ahead name (not every quest there is), and
-- the route: the steps ahead as numbered waypoints (UI/MapRoute.lua's) joined by a
-- dotted line from where you stand, along the way on foot when it leads
-- (UI/Ground.lua). Dots, not lines: the minimap is round and a line would run past
-- its edge; a dot is drawn only inside it.
-- Placement uses the client's own scale: C_Minimap.GetViewRadius() (yards from the
-- centre to the edge) and C_Map.GetMapWorldSize() (yards across the zone map).
local _, ns = ...
local MM = ns:NewModule("Minimap")

MM.pins = {}       -- the pins shown: the zone's pins of the quests the guide wants
MM.all = {}        -- every pin of the player's zone (built on LVLS_PINS)
local buttons = {} -- pooled frames
local holder
local here = {}    -- the player's position, refilled every update
local NONE = {}
local laid = {}    -- what the last layout was for: skip it when nothing moved

-- Offset in pixels from the minimap centre for a pin, or nil when it is outside.
-- Pure: every input handed in (tests call it directly).
--   player, pin: map percent on the same map; w, h: map size in yards;
--   radius: yards to the minimap edge; half: minimap half width in pixels;
--   facing: radians (only when the minimap rotates).
function MM.Offset(player, pin, w, h, radius, half, facing)
  local ox, oy, d = MM.Project(player, pin, w, h, radius, half, facing)
  if d > radius then return nil, d end
  return ox, oy, d
end

-- The same offset, also when it lies outside the minimap (the route's lines run
-- to the edge towards it).
function MM.Project(player, pin, w, h, radius, half, facing)
  local dx = (pin.x - player.x) / 100 * w      -- yards east
  local dy = (pin.y - player.y) / 100 * h      -- yards south
  if facing then
    local c, s = math.cos(facing), math.sin(facing)
    -- rotate the (east, north) vector by -facing
    local e, n = dx, -dy
    e, n = e * c + n * s, -e * s + n * c
    dx, dy = e, -n
  end
  local d = math.sqrt(dx * dx + dy * dy)
  return dx / radius * half, -dy / radius * half, d
end

local function build(ds, char, map)
  local all = ns.MapPins.Pins(ds, char, map)
  local out, objectives = {}, {}
  for _, p in ipairs(all) do
    if p.type == "objective" then
      local key = p.quest .. ":" .. p.index
      objectives[key] = objectives[key] or {}
      table.insert(objectives[key], { map = map, x = p.x, y = p.y, src = p })
    elseif p.type ~= "trivial" then
      out[#out + 1] = p
    end
  end
  for _, spots in pairs(objectives) do
    for i, c in ipairs(ns.Geo.Group(spots, 3)) do
      if i > 6 then break end
      local src = spots[1].src
      out[#out + 1] = { type = "objective", quest = src.quest, index = src.index, kind = src.kind,
        id = src.id, x = c.x, y = c.y, pct = src.pct, vendor = src.vendor }
    end
  end
  return out
end

-- The quests the steps from `from` on name (accept, objective, turn-in, also lines).
function MM.Wanted(steps, from)
  local out = {}
  for i = from or 1, #(steps or NONE) do
    for _, l in ipairs(steps[i].lines or NONE) do
      if l.quest then out[l.quest] = true end
    end
  end
  return out
end

-- The pins of the quests the guide wants. Pure.
function MM.Filter(all, steps, from)
  local want, out = MM.Wanted(steps, from), {}
  for _, p in ipairs(all) do
    if p.quest and want[p.quest] then out[#out + 1] = p end
  end
  return out
end

local filtered = {}
local function refilter()
  if filtered.all == MM.all and filtered.steps == ns.steps and filtered.from == ns.stepIndex then return end
  filtered.all, filtered.steps, filtered.from = MM.all, ns.steps, ns.stepIndex
  MM.pins = MM.Filter(MM.all, ns.steps, ns.stepIndex)
end

local function button(i)
  local b = buttons[i]
  if b then return b end
  b = CreateFrame("Button", nil, holder)
  b:SetSize(12, 12)
  b.Icon = b:CreateTexture(nil, "OVERLAY")
  b.Icon:SetAllPoints(b)
  b:SetScript("OnEnter", function(self)
    local ds = ns.ActiveDataset()
    if not GameTooltip or not ds or not ns.char or not self.pin then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    for k, l in ipairs(ns.Style.TooltipLines(ds, ns.char, self.pin)) do
      if k == 1 then GameTooltip:SetText(l[1], l[2], l[3], l[4]) else GameTooltip:AddLine(l[1], l[2], l[3], l[4]) end
    end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  buttons[i] = b
  return b
end

-- --- the route ------------------------------------------------------------------

MM.SPACING = 8     -- pixels between the dots of the line
MM.MAX_DOTS = 200
MM.MARK = 14       -- waypoint size in pixels

-- Dots every `spacing` pixels along a path, only inside the circle of radius `limit`
-- round the centre. Pure. verts[1..n]: { x, y } pixel offsets, false breaks the path.
-- Fills out[2k-1], out[2k]; returns the count. Each segment is cut to the circle
-- first (a waypoint thousands of pixels away costs no more than a near one).
function MM.PathDots(verts, n, spacing, limit, out, max)
  local count, walked, r2 = 0, 0, limit * limit
  for k = 2, n do
    local a, b = verts[k - 1], verts[k]
    if a and b then
      local ax, ay = a[1], a[2]
      local dx, dy = b[1] - ax, b[2] - ay
      local len2 = dx * dx + dy * dy
      if len2 > 0 then
        local len = math.sqrt(len2)
        -- |a + t (b - a)| <= limit
        local B, C = 2 * (ax * dx + ay * dy), ax * ax + ay * ay - r2
        local disc = B * B - 4 * len2 * C
        if disc > 0 then
          local sq = math.sqrt(disc)
          local t0 = math.max(0, (-B - sq) / (2 * len2))
          local t1 = math.min(1, (-B + sq) / (2 * len2))
          if t1 > t0 then
            local s, s1 = t0 * len, t1 * len
            s = s + (spacing - (walked + s) % spacing) % spacing -- evenly on from the last
            while s <= s1 and count < max do
              count = count + 1
              out[2 * count - 1], out[2 * count] = ax + dx * s / len, ay + dy * s / len
              s = s + spacing
            end
          end
        end
        walked = walked + len
      end
    end
  end
  return count
end

local lineLayer, markLayer
local dots, marks = {}, {}
local verts, flat, spotBuf = {}, {}, {}
local proj = {}   -- the route's spots on the player's map, as fractions
local wayProj = {} -- the way on foot's corners, as fractions

local function routeOn()
  return ns.db and ns.db.settings.minimapRoute and ns.MapRoute and (not ns.Viewer or ns.Viewer.Shown())
end

local function lead()
  local trip = ns.trip
  if not trip or not trip.legs or #trip.legs <= 1 or not ns.Travel then return nil end
  local spot, title = ns.Travel.NextSpot(trip)
  return spot and { spot = spot, title = title } or nil
end

-- A spot on `map` as fractions, also past the map's edge (a step over the zone
-- border is still near), or nil on another continent.
local function onMap(spot, map)
  if spot.map == map then return spot.x / 100, spot.y / 100 end
  local geo = ns.Game.geo
  local cont, wx, wy = geo.world(spot.map, spot.x, spot.y)
  if not cont then return nil end
  local x, y = geo.mapPos(cont, wx, wy, map)
  if x then return x / 100, y / 100 end
end

local function routePoints(map)
  -- keyed on the tables themselves: a new one can reuse a freed one's address
  if proj.steps ~= ns.steps or proj.from ~= ns.stepIndex or proj.trip ~= ns.trip or proj.map ~= map then
    proj = { steps = ns.steps, from = ns.stepIndex, trip = ns.trip, map = map, pts = ns.MapRoute.Points(ns.steps, ns.stepIndex, function(spot) return onMap(spot, map) end, lead()) }
  end
  return proj.pts
end

local function wayPoints(r, map)
  if wayProj.route ~= r or wayProj.map ~= map then
    wayProj = { route = r, map = map }
    for k, p in ipairs(r.pts) do
      local x, y = ns.Game.geo.mapPos(r.cont, p.x, p.y, map)
      wayProj[k] = x and { x = x, y = y } or false
    end
  end
  return wayProj
end

local function layers()
  if lineLayer then return end
  local level = (Minimap:GetFrameLevel() or 1)
  lineLayer = CreateFrame("Frame", nil, Minimap)
  lineLayer:SetAllPoints(Minimap)
  lineLayer:SetFrameLevel(level + 4) -- under the pins
  markLayer = CreateFrame("Frame", nil, Minimap)
  markLayer:SetAllPoints(Minimap)
  markLayer:SetFrameLevel(level + 6) -- over them: the numbers stay readable
end

local function hideRoute(from, fromMark)
  for i = from or 1, #dots do dots[i]:Hide() end
  for i = fromMark or 1, #marks do marks[i]:Hide() end
end
MM.HideRoute = hideRoute

-- Draw the route around the player. Returns the dots and waypoints shown.
local function drawRoute(pos, w, h, radius, half, facing)
  if not routeOn() or not ns.steps or not ns.stepIndex then hideRoute(); return 0, 0 end
  layers()
  local MR = ns.MapRoute
  local pts = routePoints(pos.map)
  local n, nm = 1, 0
  verts[1] = verts[1] or {}
  verts[1][1], verts[1][2] = 0, 0
  local pin = spotBuf
  local function vert(x, y)
    n = n + 1
    local v = verts[n]
    if not v then v = {}; verts[n] = v end
    pin.x, pin.y = x, y
    v[1], v[2] = MM.Project(pos, pin, w, h, radius, half, facing)
  end
  local function brk() n = n + 1; verts[n] = false end
  -- from where you stand: along the way on foot when it leads, else straight on
  local way = ns.Ground and ns.Ground.Leading()
  local first = pts[1]
  if way then
    local wp = wayPoints(way, pos.map)
    for k = way.i, #way.pts do
      local p = wp[k]
      if p then vert(p.x, p.y) else brk() end
    end
  elseif not (first and (first.current or first.travel) and not first.gap) then
    brk()
  end
  local limit = half - 3
  for i, p in ipairs(pts) do
    if p.gap or (i == 1 and way and not (p.current or p.travel)) then brk() end
    vert(p.x * 100, p.y * 100)
    local v = verts[n]
    if v[1] * v[1] + v[2] * v[2] <= limit * limit then
      nm = nm + 1
      local m = marks[nm]
      if not m then
        m = CreateFrame("Frame", nil, markLayer)
        m:SetSize(MM.MARK, MM.MARK)
        m.dot = m:CreateTexture(nil, "OVERLAY")
        m.dot:SetTexture("Interface\\AddOns\\Lvls\\Media\\Dot")
        m.dot:SetAllPoints(m)
        m.label = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        m.label:SetPoint("CENTER", m, "CENTER", 0, 0)
        m.label:SetTextColor(0.1, 0.1, 0.1)
        MR.Hoverable(m)
        marks[nm] = m
      end
      local near = p.current or p.travel
      local c = near and MR.ACCENT or MR.AHEAD_COLOR
      m.dot:SetVertexColor(c[1], c[2], c[3])
      m:SetAlpha(near and 1 or 0.85)
      m.label:SetText(MR.Label(p))
      m.point = p
      m:ClearAllPoints()
      m:SetPoint("CENTER", Minimap, "CENTER", v[1], v[2])
      m:Show()
    end
  end
  local count = MM.PathDots(verts, n, MM.SPACING, limit, flat, MM.MAX_DOTS)
  local shown = 0
  for k = 1, count do
    local x, y = flat[2 * k - 1], flat[2 * k]
    if x * x + y * y > 25 then -- not under the player's own arrow
      shown = shown + 1
      local d = dots[shown]
      if not d then
        d = lineLayer:CreateTexture(nil, "OVERLAY")
        d:SetTexture("Interface\\AddOns\\Lvls\\Media\\Dot")
        d:SetSize(4, 4)
        dots[shown] = d
      end
      local c = MR.ACCENT
      d:SetVertexColor(c[1], c[2], c[3])
      d:ClearAllPoints()
      d:SetPoint("CENTER", Minimap, "CENTER", x, y)
      d:Show()
    end
  end
  hideRoute(shown + 1, nm + 1)
  MM.drawn = { dots = shown, marks = nm, lastX = flat[2 * count - 1], lastY = flat[2 * count] }
  return shown, nm
end

function MM.Update()
  if not holder then return end
  refilter()
  local pos = ns.Game.Position(here)
  local on = ns.db and ns.db.settings.minimap and pos and pos.map == MM.map and true or false
  local ron = routeOn() and true or false
  local w, h, radius
  if (on or ron) and pos then
    w, h = ns.Game.geo.size(pos.map)
    radius = C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius()
  end
  local shown = 0
  if not (w and w > 0 and radius and radius > 0) then laid.pins = nil; hideRoute() end -- hidden: lay out again next time
  if w and w > 0 and radius and radius > 0 then
    local half = (ns.Util.plain(Minimap:GetWidth()) or 140) / 2
    local facing
    if GetCVar and GetCVar("rotateMinimap") == "1" and GetPlayerFacing then facing = GetPlayerFacing() end
    -- standing still (same spot, facing, zoom and pins): the layout is as it was
    local way = ns.Ground and ns.Ground.Leading()
    local wayI = way and way.i
    if laid.on == on and laid.pins == MM.pins and laid.map == pos.map and laid.x == pos.x and laid.y == pos.y
      and laid.facing == facing and laid.radius == radius and laid.half == half
      and laid.steps == ns.steps and laid.from == ns.stepIndex and laid.trip == ns.trip
      and laid.way == way and laid.wayI == wayI and laid.ron == ron then
      return
    end
    laid.pins, laid.map, laid.x, laid.y, laid.facing, laid.radius, laid.half =
      MM.pins, pos.map, pos.x, pos.y, facing, radius, half
    laid.steps, laid.from, laid.trip, laid.way, laid.wayI, laid.ron, laid.on = ns.steps, ns.stepIndex, ns.trip, way, wayI, ron, on
    drawRoute(pos, w, h, radius, half - 4, facing)
    for _, p in ipairs(on and MM.pins or NONE) do
      local ox, oy = MM.Offset(pos, p, w, h, radius, half - 4, facing)
      if ox then
        shown = shown + 1
        local b = button(shown)
        if b.pin ~= p then
          b.pin = p
          local size = ns.Style.Apply(b.Icon, p)
          b:SetSize(size * 0.75, size * 0.75)
        end
        b:ClearAllPoints()
        b:SetPoint("CENTER", Minimap, "CENTER", ox, oy)
        b:Show()
      end
    end
  end
  for i = shown + 1, #buttons do buttons[i]:Hide() end
end

function MM.Rebuild()
  local ds, char = ns.ActiveDataset(), ns.char
  local pos = char and char.pos
  MM.all, MM.map = {}, pos and pos.map
  if ds and pos then MM.all = build(ds, char, pos.map) end
  MM.Update()
end

function MM.Attach()
  if holder or not CreateFrame or not Minimap then return end
  holder = CreateFrame("Frame", nil, Minimap)
  holder:SetAllPoints(Minimap)
  holder:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 5)
  local acc = 0
  holder:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + (elapsed or 0)
    if acc >= 0.1 then acc = 0; MM.Update() end
  end)
end

ns.Events.On("LVLS_LOADED", function() MM.Attach() end)
ns.Events.On("LVLS_PINS", function() MM.Rebuild() end)

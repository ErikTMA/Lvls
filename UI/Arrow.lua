-- Navigation arrow: points at the current step (or a spot you clicked), turns from
-- red (behind you) through yellow to green (straight ahead), shows the step, the
-- distance and the time to get there, and a "here" marker when you arrive.
-- Art: Media/Arrow.tga (a light grey arrow pointing up, tinted and rotated here)
-- and Media/ArrowHere.tga.
local _, ns = ...
local AR = ns:NewModule("Arrow")

AR.ARRIVED_YARDS = 5  -- "You are here": about talking range
AR.LEAVE_YARDS = 8    -- once there, the arrow comes back only past this (no flicker)
AR.LEG_YARDS = 12     -- a leg's end (flight master, entrance, path point): on to the next
AR.AREA_CHECK = 0.5 -- seconds between "am I in the quest area" checks
AR.target = nil   -- { map, x, y, title, manual }
local frame
local here = {}            -- the player's position, refilled every update
local shownYards, shownEta -- what the distance line says now

-- Direction to a target. Pure. Returns east / north yards from the player.
-- Same map: map percent times the map's size in yards. Different maps: world
-- positions from geo.world, whose axes in WoW are x = north, y = west.
function AR.Vector(player, target, geo)
  if not player or not target then return nil end
  if player.map == target.map then
    if not geo.size then return nil end
    local w, h = geo.size(player.map)
    if not w or w <= 0 or not h or h <= 0 then return nil end
    return (target.x - player.x) / 100 * w, -(target.y - player.y) / 100 * h
  end
  if not geo.world then return nil end
  local c1, px, py = geo.world(player.map, player.x, player.y)
  local c2, tx, ty = geo.world(target.map, target.x, target.y)
  if not c1 or c1 ~= c2 then return nil end
  return -(ty - py), tx - px
end

-- Arrow rotation (radians, counter-clockwise, 0 = straight ahead) from the vector and
-- the player's facing (radians counter-clockwise from north).
function AR.Rotation(east, north, facing)
  local bearing = math.atan2(-east, north) -- counter-clockwise from north
  local r = (bearing - (facing or 0)) % (2 * math.pi)
  if r > math.pi then r = r - 2 * math.pi end
  return r
end

-- Colour by how far off the heading is: 0 green, 90 degrees yellow, 180 red.
function AR.Color(rotation)
  local t = math.min(1, math.abs(rotation) / math.pi) -- 0 ahead .. 1 behind
  if t < 0.5 then
    local k = t / 0.5
    return 0.2 + 0.8 * k, 1, 0.2 * (1 - k)
  end
  local k = (t - 0.5) / 0.5
  return 1, 1 - 0.85 * k, 0
end

-- "1:05" for seconds; nil when unknown.
function AR.Eta(yards, speed)
  if not yards or not speed or speed < 0.5 then return nil end
  local s = math.floor(yards / speed + 0.5)
  return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

-- The quests whose objective area counts as "there" for a step: its own open
-- objective lines (not the "also here" ones, not talking to someone). Pure.
local AREA_KINDS = { kill = true, collect = true, object = true, event = true }
function AR.AreaQuests(lines)
  local out, seen = {}, {}
  for _, l in ipairs(lines or {}) do
    if AREA_KINDS[l.kind] and l.quest and not l.done and not l.also and not seen[l.quest] then
      seen[l.quest] = true
      out[#out + 1] = l.quest
    end
  end
  return out
end

-- Is the player inside the game's own objective area (the blue shape on the map and
-- the minimap) of one of these quests? The client draws that shape and can say
-- which quest's shape covers a point, but does not hand out the shape itself.
-- Only quests in the log have one. False when the client cannot tell.
local blob          -- a hidden QuestPOIFrame; false when the client has none
local blobKey       -- the map and quests drawn on it
function AR.InArea(pos, quests)
  if not pos or not quests or #quests == 0 or blob == false then return false end
  if not blob then
    local ok, f = pcall(CreateFrame, "QuestPOIFrame", nil, UIParent)
    if not ok or not f or not f.DrawBlob or not f.UpdateMouseOverTooltip then blob = false; return false end
    blob = f
    blob:SetSize(1, 1)
    if blob.SetFillAlpha then blob:SetFillAlpha(0) end
    if blob.SetBorderAlpha then blob:SetBorderAlpha(0) end
  end
  local key = pos.map .. ":" .. table.concat(quests, ",")
  local ok, hit = pcall(function()
    if key ~= blobKey then
      blobKey = key
      blob:SetMapID(pos.map)
      blob:DrawNone()
      for _, q in ipairs(quests) do blob:DrawBlob(q, true) end
    end
    return blob:UpdateMouseOverTooltip(pos.x / 100, pos.y / 100)
  end)
  if not ok then blobKey = nil; return false end
  return hit ~= nil
end

-- The goal (a step, a line, a pin you clicked) and the target the arrow points at
-- now: the end of the trip's first leg (the flight master, the boat, the cave
-- entrance, the next point of a path), see ns.RefreshTravel in Core/Init.lua.
-- lines: a work step's lines; inside the game's area for one of its open quests
-- is "there" wherever in it the spot is.
function AR.SetTarget(spot, title, manual, lines)
  AR.inArea, AR.areaAt, AR.arrived = false, nil, false
  if not spot then
    AR.goal, AR.target = nil, nil
  else
    AR.goal = { map = spot.map, x = spot.x, y = spot.y, title = title, manual = manual, lines = lines }
    AR.target = AR.goal
    if ns.RefreshTravel then ns.RefreshTravel() end
  end
  if frame then frame:Show() end
end

-- The goal's title changed (a work step's progress): not for a place you picked.
function AR.SetTitle(title)
  local g = AR.goal
  if not g or g.manual or g.title == title then return end
  g.title = title
end

function AR.SetLeg(spot, title)
  if not AR.goal then return end
  local old = AR.target
  if not spot then AR.target = AR.goal
  else AR.target = { map = spot.map, x = spot.x, y = spot.y, title = title or AR.goal.title, leg = true } end
  local t = AR.target
  if not old or old.map ~= t.map or old.x ~= t.x or old.y ~= t.y then AR.arrived = false end
end

local function create()
  frame = CreateFrame("Frame", "LvlsArrowFrame", UIParent)
  frame:SetSize(84, 84)
  frame:SetPoint("TOP", UIParent, "TOP", 0, -120)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame.arrow = frame:CreateTexture(nil, "ARTWORK")
  frame.arrow:SetTexture("Interface\\AddOns\\Lvls\\Media\\Arrow")
  frame.arrow:SetAllPoints(frame)
  frame.here = frame:CreateTexture(nil, "ARTWORK")
  frame.here:SetTexture("Interface\\AddOns\\Lvls\\Media\\ArrowHere")
  frame.here:SetSize(64, 64)
  frame.here:SetPoint("CENTER", frame, "CENTER", 0, 0)
  frame.here:SetVertexColor(0.25, 1, 0.25)
  frame.here:Hide()
  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.title:SetPoint("TOP", frame, "BOTTOM", 0, -2)
  frame.dist = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.dist:SetPoint("TOP", frame.title, "BOTTOM", 0, -2)
  local acc = 0
  frame:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + (elapsed or 0)
    if acc >= 0.03 then acc = 0; AR.Update() end
  end)
end

function AR.Update()
  if not frame then return end
  local t = AR.target
  local on = ns.db and ns.db.settings.arrow
  if on and t and UnitOnTaxi and UnitOnTaxi("player") then
    frame.arrow:Hide(); frame.here:Hide()
    frame.title:SetText(AR.goal and AR.goal.title or "")
    frame.dist:SetText("|cffaaaaaaflying|r"); shownYards = nil
    return
  end
  local pos = on and t and ns.Game.Position(here)
  local east, north
  if pos then east, north = AR.Vector(pos, t, ns.Game.geo) end
  if not east then
    frame.arrow:Hide(); frame.here:Hide()
    frame.title:SetText(on and t and t.title or "")
    frame.dist:SetText(on and t and "|cff999999far away|r" or ""); shownYards = nil
    if not (on and t) then frame:Hide() end
    return
  end
  frame:Show()
  local d = math.sqrt(east * east + north * north)
  frame.title:SetText(t.title or "")
  -- in the step's quest area already: there, even if the spot is across it
  local g = AR.goal
  if g and g.lines then
    local now = GetTime and GetTime() or 0
    if not AR.areaAt or now - AR.areaAt >= AR.AREA_CHECK then
      AR.areaAt = now
      AR.inArea = AR.InArea(pos, AR.AreaQuests(g.lines))
    end
    if AR.inArea then
      frame.title:SetText(g.title or "")
      frame.arrow:Hide()
      frame.here:Show()
      frame.dist:SetText("|cff40ff40In the quest area|r"); shownYards = nil
      return
    end
  end
  if t.leg and d <= AR.LEG_YARDS and ns.RefreshTravel then
    -- reached a leg's end (flight master, entrance, path point): on to the next leg
    local now = GetTime and GetTime() or 0
    if not AR.lastLeg or now - AR.lastLeg > 1 then AR.lastLeg = now; ns.RefreshTravel() end
  end
  AR.arrived = d <= (AR.arrived and AR.LEAVE_YARDS or AR.ARRIVED_YARDS)
  if AR.arrived then
    frame.arrow:Hide()
    frame.here:Show()
    frame.dist:SetText("|cff40ff40You are here|r"); shownYards = nil
    return
  end
  frame.here:Hide()
  frame.arrow:Show()
  local rot = AR.Rotation(east, north, GetPlayerFacing and GetPlayerFacing() or 0)
  if frame.arrow.SetRotation then frame.arrow:SetRotation(rot) end
  local r, g, b = AR.Color(rot)
  frame.arrow:SetVertexColor(r, g, b)
  -- the text only when what it says changes (this runs ~30 times a second)
  -- secret in combat: no time to arrival then
  local speed = GetUnitSpeed and ns.Util.plain(GetUnitSpeed("player")) or 0
  local yards = math.floor(d + 0.5)
  local secs = speed >= 0.5 and math.floor(d / speed + 0.5) or -1
  if yards ~= shownYards or secs ~= shownEta then
    shownYards, shownEta = yards, secs
    local eta = AR.Eta(d, speed)
    frame.dist:SetText(ns.Util.yards(d) .. (eta and ("  |cffaaaaaa" .. eta .. "|r") or ""))
  end
end

function AR.Attach()
  if frame or not CreateFrame then return end
  create()
end

ns.Events.On("LVLS_LOADED", function() AR.Attach() end)

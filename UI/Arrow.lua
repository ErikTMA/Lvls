-- Navigation arrow: points at the current step (or a spot you clicked). The arrow
-- itself (the frame, its turn and colour, distance and time, "You are here") is
-- Libs/WaypointArrow.lua, shared with Profs!: one arrow when both are installed. This
-- module says where Lvls! wants it to point and adds Lvls!'s own rules: inside the
-- step's quest area is "there", the trip's legs, the way on foot (UI/Ground.lua).
local _, ns = ...
local AR = ns:NewModule("Arrow")
local WA = _G.WaypointArrow

AR.OWNER = "Lvls!"
AR.ARRIVED_YARDS = WA.ARRIVED_YARDS
AR.LEAVE_YARDS = WA.LEAVE_YARDS
AR.LEG_YARDS = 12     -- a leg's end (flight master, entrance, path point): on to the next
AR.AREA_CHECK = 0.5 -- seconds between "am I in the quest area" checks
AR.target = nil   -- { map, x, y, title, manual }

-- Direction, turn, colour and time to arrival (pure; Libs/WaypointArrow.lua).
AR.Vector, AR.Rotation, AR.Color, AR.Eta = WA.Vector, WA.Rotation, WA.Color, WA.Eta

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

-- The step's primary objective: the open line the step stands at (S.Place in
-- Engine/Steps.lua), else its first open objective. The others were grouped in
-- because they are close by; the arrow only leads to this one. Pure.
function AR.Primary(lines, spot)
  local first
  for _, l in ipairs(lines or {}) do
    if l.index and l.quest and not l.done and not l.also then
      if spot and l.at == spot then return { l } end
      first = first or l
    end
  end
  return first and { first } or {}
end

-- What the arrow says for its goal: a work step's primary objective with its
-- progress ("Kill 12 Kobold Laborer (3/12)"), not the whole step; else the title
-- it was given.
function AR.GoalTitle(g)
  if not g then return nil end
  local p = g.lines and AR.Primary(g.lines, g.spot)
  if p and #p > 0 and ns.Steps and ns.Steps.WorkTitle then return ns.Steps.WorkTitle({ lines = p }) end
  return g.title
end

-- The title under the arrow at the goal itself: a note on where it stands goes on a
-- second line ("At the top of the tower"); legs on the way keep their own title.
AR.NOTE_COLOR = "|cff8cd9ff"
function AR.GoalText(g)
  local title = AR.GoalTitle(g)
  local note = g and ns.Notes and ns.Notes.ForSpot(g.spot)
  if note then title = (title or "") .. "\n" .. AR.NOTE_COLOR .. note .. "|r" end
  return title
end

-- Is the player inside the game's own objective area (the blue shape on the map and
-- the minimap) of one of these quests? The client draws that shape and can say
-- which quest's shape covers a point, but does not hand out the shape itself.
-- Only quests in the log have one. False when the client cannot tell; AR.areaWhy
-- says why (for /lvls area).
local blob          -- a hidden QuestPOIFrame; false when the client has none
local blobKey       -- the map and quests drawn on it
function AR.InArea(pos, quests)
  if not pos or not quests or #quests == 0 then AR.areaWhy = "no open objective"; return false end
  if blob == false then return false end
  if not blob then
    local ok, f = pcall(CreateFrame, "QuestPOIFrame", nil, UIParent)
    if not ok or not f or not f.DrawBlob or not f.UpdateMouseOverTooltip then
      blob = false
      AR.areaWhy = "this client has no QuestPOIFrame: " .. tostring(ok and "missing methods" or f)
      return false
    end
    -- set up like Blizzard's own (QuestBlobPinTemplate): textures, a real size;
    -- drawn see-through
    blob = f
    blob:SetSize(512, 512)
    blob:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    if blob.SetFrameStrata then blob:SetFrameStrata("BACKGROUND") end
    if blob.SetFillTexture then blob:SetFillTexture("Interface\\WorldMap\\UI-QuestBlob-Inside") end
    if blob.SetBorderTexture then blob:SetBorderTexture("Interface\\WorldMap\\UI-QuestBlob-Outside") end
    if blob.SetFillAlpha then blob:SetFillAlpha(0) end
    if blob.SetBorderAlpha then blob:SetBorderAlpha(0) end
    if blob.EnableMouse then blob:EnableMouse(false) end
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
  if not ok then blobKey = nil; AR.areaWhy = "client error: " .. tostring(hit); return false end
  AR.areaWhy = hit ~= nil and ("inside the area of quest " .. tostring(hit)) or "outside every drawn area"
  return hit ~= nil
end

-- Our own data: within AREA_YARDS of a spawn of one of the step's open objectives
-- (the game's blue area is drawn around those spawns). Spots are looked up once per
-- line. Returns the nearest distance too.
AR.AREA_YARDS = 40
function AR.NearObjective(pos, lines, ds, geo)
  local best = math.huge
  if not pos or not ds then return false, best end
  for _, l in ipairs(lines or {}) do
    if AREA_KINDS[l.kind] and l.quest and l.index and not l.done and not l.also then
      if not l.areaSpots then
        local q = ds.quests[l.quest]
        l.areaSpots = q and ns.Quests.ObjectiveSpots(ds, q, l.index) or {}
      end
      local _, d = ns.Geo.Nearest(geo, pos, l.areaSpots)
      if d < best then best = d end
    end
  end
  return best <= AR.AREA_YARDS, best
end

-- In the step's area by either answer.
function AR.CheckArea(pos, lines)
  local near, d = AR.NearObjective(pos, lines, ns.ActiveDataset and ns.ActiveDataset(), ns.Game.geo)
  local inside = AR.InArea(pos, AR.AreaQuests(lines))
  AR.areaNearest = d
  return near or inside, near, inside
end

-- Pickups: an item that lies on the ground (a fossil, a crate, a herb) or an object
-- to use. The client does not tell addons where objects are, so near their spawns
-- (our data) the arrow leads to the nearest one instead of "in the quest area", and
-- on to the next once you were there (looted, or someone else got it first). A
-- spawn you were at is skipped for PICKUP_RESPAWN seconds.
AR.PICKUP_YARDS = 150   -- this close to a spawn: lead to it
AR.PICKUP_REACH = 5     -- at it
AR.PICKUP_LEAVE = 10    -- walked off it: on to the next
AR.PICKUP_RESPAWN = 300
AR.visited = {}         -- "map:x:y" -> when you were at that spawn

local PICKUP_KINDS = { collect = true, object = true }
local function spotKey(s) return ("%d:%.1f:%.1f"):format(s.map, s.x, s.y) end

-- The object spawns of the step's open pickup lines (not mob drops). Looked up once
-- per line.
function AR.PickupSpots(lines, ds)
  local out = {}
  if not ds then return out end
  for _, l in ipairs(lines or {}) do
    if PICKUP_KINDS[l.kind] and l.quest and l.index and not l.done and not l.also then
      if not l.pickupSpots then
        l.pickupSpots = {}
        local q = ds.quests[l.quest]
        for _, sp in ipairs(q and ns.Quests.ObjectiveSpots(ds, q, l.index) or {}) do
          if sp.kind == "o" and not sp.waypoint then
            local o = ds.objects and ds.objects[sp.id]
            sp.name = o and o.n
            l.pickupSpots[#l.pickupSpots + 1] = sp
          end
        end
      end
      for _, sp in ipairs(l.pickupSpots) do out[#out + 1] = sp end
    end
  end
  return out
end

-- The spawn to lead to: the nearest one within PICKUP_YARDS you were not at lately.
-- Pure but for `visited` and `now`.
function AR.NextPickup(pos, spots, visited, now, geo)
  local best, bestD = nil, math.huge
  for _, sp in ipairs(spots) do
    local at = visited[spotKey(sp)]
    if not at or now - at >= AR.PICKUP_RESPAWN then
      local d = ns.Geo.Distance(geo, pos, sp)
      if d < bestD then best, bestD = sp, d end
    end
  end
  if bestD <= AR.PICKUP_YARDS then return best, bestD end
end

local push

-- Lead to this spawn (nil: back to the goal).
local function setPickup(sp)
  AR.pickup, AR.pickupHere = sp, false
  if sp then
    AR.target = { map = sp.map, x = sp.x, y = sp.y, title = sp.name or AR.GoalTitle(AR.goal), pickup = true }
    push(false)
    if ns.Ground then pcall(ns.Ground.Want, sp) end
  else
    AR.target = AR.goal
    push(false)
    if ns.RefreshTravel then ns.RefreshTravel() end
  end
end

-- Every area check: at the spawn (remember it), walked off it (the next one), or a
-- nearer one / none in range.
function AR.CheckPickup(pos, lines, now)
  local geo = ns.Game.geo
  local spots = AR.PickupSpots(lines, ns.ActiveDataset and ns.ActiveDataset())
  local cur = AR.pickup
  if cur then
    local d = ns.Geo.Distance(geo, pos, cur)
    if d <= AR.PICKUP_REACH then
      AR.visited[spotKey(cur)] = now
      AR.pickupHere = true
    end
    -- still on one of the step's open lines, and you are at it: stay
    local live = false
    for _, sp in ipairs(spots) do if sp == cur then live = true; break end end
    if live and AR.pickupHere and d <= AR.PICKUP_LEAVE then return cur end
  end
  local nxt = AR.NextPickup(pos, spots, AR.visited, now, geo)
  if nxt ~= cur then setPickup(nxt) end
  return nxt
end

-- The goal (a step, a line, a pin you clicked) and the target the arrow points at
-- now: the end of the trip's first leg (the flight master, the boat, the cave
-- entrance, the next point of a path), see ns.RefreshTravel in Core/Init.lua.
-- lines: a work step's lines; inside the game's area for one of its open quests
-- is "there" wherever in it the spot is.
-- Lvls!'s rules on top of the shared arrow: inside the step's quest area is there;
-- at a leg's end (flight master, entrance, path point) on to the next leg.
local hooks = {
  -- dead: the corpse even with the guide hidden
  enabled = function()
    return ns.db and ns.db.settings.arrow and (AR.corpse or not ns.Viewer or ns.Viewer.Shown()) and true or false
  end,
  position = function(buf) return ns.Game.Position(buf) end,
  steer = function(pos) if ns.Ground and not AR.corpse then return ns.Ground.Next(pos) end end,
  status = function(pos, d, t)
    if AR.corpse then return end
    local g = AR.goal
    if g and g.lines then
      local now = GetTime and GetTime() or 0
      if not AR.areaAt or now - AR.areaAt >= AR.AREA_CHECK then
        AR.areaAt = now
        -- only the primary objective; near a pickup: the arrow leads to it, the
        -- area does not count
        local lines = AR.Primary(g.lines, g.spot)
        AR.inArea = not (not g.manual and AR.CheckPickup(pos, lines, now)) and AR.CheckArea(pos, lines)
      end
      if AR.inArea then return { text = "|cff40ff40In the quest area|r", title = AR.GoalText(g) } end
    end
    if t.leg and d <= AR.LEG_YARDS and ns.RefreshTravel then
      local now = GetTime and GetTime() or 0
      if not AR.lastLeg or now - AR.lastLeg > 1 then AR.lastLeg = now; ns.RefreshTravel() end
    end
  end,
}
hooks.geo = setmetatable({}, { __index = function(_, k) return ns.Game.geo[k] end })

function push(fresh)
  local c = AR.corpse
  if c then
    -- picked "by hand" so it beats every other target (Profs!'s too)
    return WA.Set(AR.OWNER, { map = c.map, x = c.x, y = c.y, title = AR.CORPSE_TITLE },
      { manual = true, fresh = fresh, hooks = hooks })
  end
  local t = AR.target
  if not t then return WA.Clear(AR.OWNER) end
  local gt = AR.GoalText(AR.goal)
  WA.Set(AR.OWNER, { map = t.map, x = t.x, y = t.y, title = t == AR.goal and gt or t.title, leg = t.leg,
    goalTitle = gt }, { manual = AR.goal and AR.goal.manual or false,
    fresh = fresh, hooks = hooks })
end

function AR.SetTarget(spot, title, manual, lines)
  AR.inArea, AR.areaAt = false, nil
  AR.pickup, AR.pickupHere = nil, false
  if not spot then
    AR.goal, AR.target = nil, nil
    if ns.Ground then ns.Ground.Want(nil) end
    push(true)
  else
    AR.goal = { map = spot.map, x = spot.x, y = spot.y, title = title, manual = manual, lines = lines, spot = spot }
    AR.target = AR.goal
    push(true)
    if ns.RefreshTravel then ns.RefreshTravel() end
  end
end

-- Say the goal's title again (its note changed).
function AR.Redraw() if AR.goal then push(false) end end

-- The goal's title changed (a work step's progress): not for a place you picked.
function AR.SetTitle(title)
  local g = AR.goal
  if not g or g.manual or g.title == title then return end
  g.title = title
  if AR.target == g then push(false) end
end

function AR.SetLeg(spot, title)
  if not AR.goal or AR.pickup then return end
  if not spot then AR.target = AR.goal
  else AR.target = { map = spot.map, x = spot.x, y = spot.y, title = title or AR.GoalTitle(AR.goal), leg = true } end
  push(false)
end

-- Dead or a ghost: the arrow points at your corpse, whatever the step or a spot you
-- picked; alive again it goes back to them. Where the corpse lies: the client's
-- (C_DeathInfo.GetCorpseMapPosition, asked on your map and the maps around it), else
-- where you died (inside a dungeon: its door, the last spot outside).
AR.CORPSE_TITLE = "Your corpse"

local function isDead()
  return UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") and true or false
end

-- The client's corpse spot, on the first map up from yours that has it. Nil when
-- the client does not say (not released yet, or the corpse is in an instance).
function AR.CorpseSpot()
  if not (C_DeathInfo and C_DeathInfo.GetCorpseMapPosition and C_Map and C_Map.GetBestMapForUnit) then return nil end
  local map = C_Map.GetBestMapForUnit("player")
  for _ = 1, 6 do
    if not map or map == 0 then return nil end
    local ok, v = pcall(C_DeathInfo.GetCorpseMapPosition, map)
    if ok and type(v) == "table" then
      local x, y = v.x, v.y
      if v.GetXY then x, y = v:GetXY() end
      if x and y and not (x == 0 and y == 0) then return { map = map, x = x * 100, y = y * 100 } end
    end
    local info = C_Map.GetMapInfo and C_Map.GetMapInfo(map)
    map = info and info.parentMapID
  end
end

-- Where you just died, as a fallback for the client's answer.
function AR.Died()
  local DI = ns.DungeonInfo
  local inside = DI and DI.Instance and DI.Instance()
  local spot = inside and DI.outside or ns.Game.Position()
  if spot then AR.deathSpot = { map = spot.map, x = spot.x, y = spot.y } end
  AR.CheckDead()
end

-- Dead or alive now: point at the corpse, or give the arrow back.
function AR.CheckDead()
  if not isDead() then
    AR.deathSpot = nil
    if not AR.corpse then return end
    AR.corpse = nil
    push(true)
    if ns.RefreshTravel then ns.RefreshTravel() end
    return
  end
  local c = AR.CorpseSpot() or AR.deathSpot
  if not c then return end
  local old = AR.corpse
  if old and old.map == c.map and old.x == c.x and old.y == c.y then return end
  AR.corpse = c
  push(not old)
end

-- Redraw now (the frame also does it ~30 times a second).
function AR.Update() WA.Update() end

-- The shared arrow goes where it was dragged (LvlsDB.positions.arrow, as before).
function AR.Attach()
  WA.Register(AR.OWNER, {
    load = function() return ns.db and ns.db.positions and ns.db.positions.arrow end,
    save = function(pos)
      if not ns.db then return end
      ns.db.positions = ns.db.positions or {}
      ns.db.positions.arrow = pos
    end,
  })
end

ns.Events.On("LVLS_LOADED", function() AR.Attach(); AR.CheckDead() end)
-- logged in or zoned as a ghost, released, back alive
ns.Events.On("LVLS_STATE", function() AR.CheckDead() end)
if CreateFrame then
  local f = CreateFrame("Frame")
  for _, e in ipairs({ "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do f:RegisterEvent(e) end
  f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_DEAD" then AR.Died() else AR.CheckDead() end
  end)
end
-- the guide shown again: the arrow is Lvls!'s again (a hidden frame has no OnUpdate
-- to notice by itself); hidden: the next owner's, or none
ns.Events.On("LVLS_GUIDE", function(on)
  if on and AR.target then push(false) end
  WA.Update()
end)

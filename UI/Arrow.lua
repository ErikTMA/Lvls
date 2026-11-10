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

-- The goal (a step, a line, a pin you clicked) and the target the arrow points at
-- now: the end of the trip's first leg (the flight master, the boat, the cave
-- entrance, the next point of a path), see ns.RefreshTravel in Core/Init.lua.
-- lines: a work step's lines; inside the game's area for one of its open quests
-- is "there" wherever in it the spot is.
-- Lvls!'s rules on top of the shared arrow: inside the step's quest area is there;
-- at a leg's end (flight master, entrance, path point) on to the next leg.
local hooks = {
  enabled = function() return ns.db and ns.db.settings.arrow and (not ns.Viewer or ns.Viewer.Shown()) end,
  position = function(buf) return ns.Game.Position(buf) end,
  steer = function(pos) if ns.Ground then return ns.Ground.Next(pos) end end,
  status = function(pos, d, t)
    local g = AR.goal
    if g and g.lines then
      local now = GetTime and GetTime() or 0
      if not AR.areaAt or now - AR.areaAt >= AR.AREA_CHECK then
        AR.areaAt = now
        AR.inArea = AR.CheckArea(pos, g.lines)
      end
      if AR.inArea then return { text = "|cff40ff40In the quest area|r", title = g.title } end
    end
    if t.leg and d <= AR.LEG_YARDS and ns.RefreshTravel then
      local now = GetTime and GetTime() or 0
      if not AR.lastLeg or now - AR.lastLeg > 1 then AR.lastLeg = now; ns.RefreshTravel() end
    end
  end,
}
hooks.geo = setmetatable({}, { __index = function(_, k) return ns.Game.geo[k] end })

local function push(fresh)
  local t = AR.target
  if not t then return WA.Clear(AR.OWNER) end
  WA.Set(AR.OWNER, { map = t.map, x = t.x, y = t.y, title = t.title, leg = t.leg,
    goalTitle = AR.goal and AR.goal.title }, { manual = AR.goal and AR.goal.manual or false,
    fresh = fresh, hooks = hooks })
end

function AR.SetTarget(spot, title, manual, lines)
  AR.inArea, AR.areaAt = false, nil
  if not spot then
    AR.goal, AR.target = nil, nil
    if ns.Ground then ns.Ground.Want(nil) end
    push(true)
  else
    AR.goal = { map = spot.map, x = spot.x, y = spot.y, title = title, manual = manual, lines = lines }
    AR.target = AR.goal
    push(true)
    if ns.RefreshTravel then ns.RefreshTravel() end
  end
end

-- The goal's title changed (a work step's progress): not for a place you picked.
function AR.SetTitle(title)
  local g = AR.goal
  if not g or g.manual or g.title == title then return end
  g.title = title
  if AR.target == g then push(false) end
end

function AR.SetLeg(spot, title)
  if not AR.goal then return end
  if not spot then AR.target = AR.goal
  else AR.target = { map = spot.map, x = spot.x, y = spot.y, title = title or AR.goal.title, leg = true } end
  push(false)
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

ns.Events.On("LVLS_LOADED", function() AR.Attach() end)
-- the guide shown again: the arrow is Lvls!'s again (a hidden frame has no OnUpdate
-- to notice by itself); hidden: the next owner's, or none
ns.Events.On("LVLS_GUIDE", function(on)
  if on and AR.target then push(false) end
  WA.Update()
end)

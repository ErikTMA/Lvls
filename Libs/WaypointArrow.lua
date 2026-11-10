-- WaypointArrow: one on-screen navigation arrow shared by every addon that embeds
-- this file (Lvls! and Profs!). Not an addon of its own: each addon ships this same
-- file in Libs/ and its art in Media/Arrow.tga and Media/ArrowHere.tga. The newest
-- copy loaded wins (MINOR below), so whichever addons are installed there is one
-- frame and one set of rules. Keep the copies identical; bump MINOR on any change.
-- Source: github.com/ErikTMA/WaypointArrow. Change it there, then `make arrow` in
-- each addon copies it in.
--
-- Each addon keeps its own target (a slot by owner name). The arrow shows one: a
-- target picked by hand (manual) beats an automatic one (a route step), then the
-- newest. Clearing a slot hands the arrow back to the next.
--
--   WaypointArrow.Register(owner, { load = fn() -> pos, save = fn(pos) })
--   WaypointArrow.Set(owner, { map, x, y, title, goalTitle? }, opts)
--     opts.manual        picked by hand: beats automatic targets
--     opts.fresh         a new goal: newest among its kind, "arrived" starts over
--     opts.clearOnLeave  dropped once you got there and walked off
--     opts.clearable     right-click on the arrow clears it
--     opts.hooks = {
--       enabled = fn() -> bool        the owner's on/off setting
--       position = fn(buf) -> {map,x,y}  where you are (default: C_Map)
--       geo = { size = fn(map) -> w,h, world = fn(map,x,y) -> cont,wx,wy }
--       status = fn(pos, yards, target) -> nil | { text, title? }  "there" by other rules
--       steer = fn(pos) -> corner, yardsLeft   a way on foot: point at its next corner
--       onClear = fn()                  the arrow dropped this target
--     }
--   WaypointArrow.Clear(owner)
--   WaypointArrow.Update()     redraw now (also runs on the frame's OnUpdate)
--
-- Game API (Gethe/wow-ui-source branch `forever`): C_Map.GetBestMapForUnit,
-- GetPlayerMapPosition, GetWorldPosFromMapPos, CreateVector2D, GetPlayerFacing,
-- GetUnitSpeed (secret in combat: issecretvalue), UnitOnTaxi, Texture:SetRotation.
local addonName = ...
local MINOR = 1

local WA = _G.WaypointArrow
if WA and (WA.MINOR or 0) >= MINOR then return end
WA = WA or { slots = {}, clients = {}, seq = 0 }
_G.WaypointArrow = WA
WA.MINOR = MINOR
WA.MEDIA = WA.MEDIA or ("Interface\\AddOns\\" .. tostring(addonName) .. "\\Media\\")

WA.ARRIVED_YARDS = 5  -- "You are here": about talking range
WA.LEAVE_YARDS = 8    -- once there, the arrow comes back only past this (no flicker)

local here = {}
local shownYards, shownEta, shownSlot

local function plain(v)
  if v ~= nil and type(issecretvalue) == "function" and issecretvalue(v) then return nil end
  return v
end

local function yardsText(y)
  if y < 1000 then return ("%d yd"):format(math.floor(y + 0.5)) end
  return ("%.1fk yd"):format(y / 1000)
end

-- Pure helpers ---------------------------------------------------------------

-- Direction to a target: east / north yards from the player. Same map: map percent
-- times the map's size in yards. Different maps: world positions, whose axes in
-- WoW are x = north, y = west.
function WA.Vector(player, target, geo)
  if not player or not target or not geo then return nil end
  if player.map == target.map and geo.size then
    local w, h = geo.size(player.map)
    if w and w > 0 and h and h > 0 then
      return (target.x - player.x) / 100 * w, -(target.y - player.y) / 100 * h
    end
  end
  if not geo.world then return nil end
  local c1, px, py = geo.world(player.map, player.x, player.y)
  local c2, tx, ty = geo.world(target.map, target.x, target.y)
  if not c1 or c1 ~= c2 then return nil end
  return -(ty - py), tx - px
end

-- Arrow rotation (radians, counter-clockwise, 0 = straight ahead) from the vector and
-- the player's facing (radians counter-clockwise from north).
function WA.Rotation(east, north, facing)
  local bearing = math.atan2(-east, north)
  local r = (bearing - (facing or 0)) % (2 * math.pi)
  if r > math.pi then r = r - 2 * math.pi end
  return r
end

-- Colour by how far off the heading is: 0 green, 90 degrees yellow, 180 red.
function WA.Color(rotation)
  local t = math.min(1, math.abs(rotation) / math.pi)
  if t < 0.5 then
    local k = t / 0.5
    return 0.2 + 0.8 * k, 1, 0.2 * (1 - k)
  end
  local k = (t - 0.5) / 0.5
  return 1, 1 - 0.85 * k, 0
end

-- "1:05" for seconds; nil when unknown.
function WA.Eta(yards, speed)
  if not yards or not speed or speed < 0.5 then return nil end
  local s = math.floor(yards / speed + 0.5)
  return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

-- Where you are and map geometry from the client (used unless the owner hands its own).
WA.geo = {
  world = function(map, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local ok, cont, p = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x / 100, y / 100))
    if ok and cont and type(p) == "table" and p.x and p.y then return cont, p.x, p.y end
    return nil
  end,
}
function WA.Position(out)
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
  local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
  if not ok or not map then return nil end
  local ok2, v = pcall(C_Map.GetPlayerMapPosition, map, "player")
  if not ok2 or type(v) ~= "table" then return nil end
  local x, y = v.x, v.y
  if v.GetXY then x, y = v:GetXY() end
  if not x or not y or (x == 0 and y == 0) then return nil end
  out = out or {}
  out.map, out.x, out.y = map, x * 100, y * 100
  return out
end

-- Slots ------------------------------------------------------------------------

local function enabled(s)
  local h = s.hooks
  if not h or not h.enabled then return true end
  local ok, on = pcall(h.enabled)
  return ok and on and true or false
end

-- The slot the arrow shows: manual first, then the newest.
function WA.Active()
  local best
  for _, s in pairs(WA.slots) do
    if enabled(s) and (not best or (s.manual and not best.manual)
        or (s.manual == best.manual and s.seq > best.seq)) then
      best = s
    end
  end
  return best
end

function WA.Set(owner, target, opts)
  if not target then return WA.Clear(owner) end
  opts = opts or {}
  local old = WA.slots[owner]
  local moved = not old or old.target.map ~= target.map or old.target.x ~= target.x or old.target.y ~= target.y
  local s = old or { owner = owner }
  if not old or opts.fresh then
    WA.seq = WA.seq + 1
    s.seq = WA.seq
  end
  if moved or opts.fresh then s.arrived, s.wasArrived = false, false end
  s.target, s.hooks = target, opts.hooks or s.hooks
  if opts.manual ~= nil or not old then s.manual = opts.manual and true or false end
  if opts.clearOnLeave ~= nil or not old then s.clearOnLeave = opts.clearOnLeave and true or false end
  if opts.clearable ~= nil or not old then s.clearable = opts.clearable and true or false end
  WA.slots[owner] = s
  if WA.frame then WA.frame:Show() end
  return s
end

function WA.Clear(owner)
  local s = WA.slots[owner]
  WA.slots[owner] = nil
  if s and s.hooks and s.hooks.onClear then pcall(s.hooks.onClear) end
end

function WA.Get(owner) return WA.slots[owner] end

-- The frame ----------------------------------------------------------------------

local function savePosition(f)
  local left, top = f.GetLeft and f:GetLeft(), f.GetTop and f:GetTop()
  local pos
  if left and top then
    pos = { "TOPLEFT", "BOTTOMLEFT", left, top }
  else
    local point, _, rel, x, y = f:GetPoint(1)
    if point then pos = { point, rel or point, x or 0, y or 0 } end
  end
  if not pos then return end
  for _, c in pairs(WA.clients) do
    if c.save then pcall(c.save, pos) end
  end
end

local function place(f)
  for _, c in ipairs(WA.order or {}) do
    local cl = WA.clients[c]
    local ok, p = pcall(cl.load or function() end)
    if ok and type(p) == "table" and p[1] then
      f:ClearAllPoints()
      f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
      return true
    end
  end
  f:ClearAllPoints()
  f:SetPoint("TOP", UIParent, "TOP", 0, -120)
  return false
end

local function tooltip(f)
  local s = WA.Active()
  if not s or not GameTooltip then return end
  GameTooltip:SetOwner(f, "ANCHOR_BOTTOM")
  GameTooltip:SetText(s.target.goalTitle or s.target.title or s.owner)
  GameTooltip:AddLine(("From %s"):format(s.owner), 0.63, 0.63, 0.63)
  if s.clearable then GameTooltip:AddLine("Right-click: clear", 0.63, 0.63, 0.63) end
  GameTooltip:AddLine("Drag: move", 0.63, 0.63, 0.63)
  GameTooltip:Show()
end

function WA.Create()
  if WA.frame or not CreateFrame then return WA.frame end
  local f = CreateFrame("Frame", "WaypointArrowFrame", UIParent)
  WA.frame = f
  f:SetSize(84, 84)
  WA.placed = place(f)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() f:StartMoving() end)
  f:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    if f.SetUserPlaced then f:SetUserPlaced(false) end -- ours, not the client's layout cache
    savePosition(f)
  end)
  f:SetScript("OnMouseUp", function(_, button)
    local s = WA.Active()
    if button == "RightButton" and s and s.clearable then
      WA.Clear(s.owner)
      if GameTooltip then GameTooltip:Hide() end
      WA.Update()
    end
  end)
  f:SetScript("OnEnter", tooltip)
  f:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  f.arrow = f:CreateTexture(nil, "ARTWORK")
  f.arrow:SetTexture(WA.MEDIA .. "Arrow")
  f.arrow:SetAllPoints(f)
  f.here = f:CreateTexture(nil, "ARTWORK")
  f.here:SetTexture(WA.MEDIA .. "ArrowHere")
  f.here:SetSize(64, 64)
  f.here:SetPoint("CENTER", f, "CENTER", 0, 0)
  f.here:SetVertexColor(0.25, 1, 0.25)
  f.here:Hide()
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.title:SetPoint("TOP", f, "BOTTOM", 0, -2)
  f.dist = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.dist:SetPoint("TOP", f.title, "BOTTOM", 0, -2)
  local acc = 0
  f:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + (elapsed or 0)
    if acc >= 0.03 then acc = 0; WA.Update() end
  end)
  return f
end

-- An addon that uses the arrow. Call once its saved variables are loaded: the frame
-- goes where the first addon with a saved spot left it.
function WA.Register(owner, client)
  WA.order = WA.order or {}
  if not WA.clients[owner] then WA.order[#WA.order + 1] = owner end
  WA.clients[owner] = client or {}
  local f = WA.Create()
  if f and not WA.placed then WA.placed = place(f) end
  return f
end

local function setText(fs, text)
  if fs.GetText and fs:GetText() == text then return end
  fs:SetText(text)
end

local function there(f, s, text, title)
  f.arrow:Hide()
  f.here:Show()
  setText(f.title, title or s.target.title or "")
  setText(f.dist, text)
  shownYards = nil
end

function WA.Update()
  local f = WA.frame
  if not f then return end
  local s = WA.Active()
  if s ~= shownSlot then shownSlot, shownYards, shownEta = s, nil, nil end
  if not s then
    f:Hide()
    return
  end
  local t, h = s.target, s.hooks or {}
  if UnitOnTaxi and plain(UnitOnTaxi("player")) then
    f:Show(); f.arrow:Hide(); f.here:Hide()
    setText(f.title, t.goalTitle or t.title or "")
    setText(f.dist, "|cffaaaaaaflying|r"); shownYards = nil
    return
  end
  local pos = (h.position or WA.Position)(here)
  local geo = h.geo or WA.geo
  local east, north
  if pos then east, north = WA.Vector(pos, t, geo) end
  if not east then
    f:Show(); f.arrow:Hide(); f.here:Hide()
    setText(f.title, t.title or "")
    setText(f.dist, "|cff999999far away|r"); shownYards = nil
    return
  end
  f:Show()
  local d = math.sqrt(east * east + north * north)
  setText(f.title, t.title or "")
  -- there by the owner's own rules (inside a quest's area); may move the target
  if h.status then
    local st = h.status(pos, d, t)
    if st then return there(f, s, st.text, st.title) end
  end
  local wasThere = s.arrived
  s.arrived = d <= (s.arrived and WA.LEAVE_YARDS or WA.ARRIVED_YARDS)
  if s.arrived then
    s.wasArrived = true
    return there(f, s, "|cff40ff40You are here|r")
  end
  if wasThere and s.clearOnLeave then
    WA.Clear(s.owner)
    return WA.Update()
  end
  f.here:Hide()
  f.arrow:Show()
  -- a way on foot: point at its next corner, count the yards along it
  if h.steer then
    local c, left = h.steer(pos)
    if c then
      local ce, cn = WA.Vector(pos, c, geo)
      if ce then east, north, d = ce, cn, left or d end
    end
  end
  local rot = WA.Rotation(east, north, plain(GetPlayerFacing and GetPlayerFacing()) or 0)
  if f.arrow.SetRotation then f.arrow:SetRotation(rot) end
  f.arrow:SetVertexColor(WA.Color(rot))
  -- the text only when what it says changes (this runs ~30 times a second);
  -- in combat the speed is secret: no time to arrival then
  local speed = GetUnitSpeed and plain(GetUnitSpeed("player")) or 0
  local yards = math.floor(d + 0.5)
  local secs = speed >= 0.5 and math.floor(d / speed + 0.5) or -1
  if yards ~= shownYards or secs ~= shownEta then
    shownYards, shownEta = yards, secs
    local eta = WA.Eta(d, speed)
    f.dist:SetText(yardsText(d) .. (eta and ("  |cffaaaaaa" .. eta .. "|r") or ""))
  end
end

-- An older copy's frame keeps running the newest functions: its scripts look them
-- up through WA, and the art it was made with is the same.

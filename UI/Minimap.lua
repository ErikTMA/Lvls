-- Minimap: givers, turn-ins and objective area centres of the zone you are in.
-- Placement uses the client's own scale: C_Minimap.GetViewRadius() (yards from the
-- centre to the edge) and C_Map.GetMapWorldSize() (yards across the zone map).
local _, ns = ...
local MM = ns:NewModule("Minimap")

MM.pins = {}       -- current pin data (zone of the player)
local buttons = {} -- pooled frames
local holder
local here = {}    -- the player's position, refilled every update
local laid = {}    -- what the last layout was for: skip it when nothing moved

-- Offset in pixels from the minimap centre for a pin, or nil when it is outside.
-- Pure: every input handed in (tests call it directly).
--   player, pin: map percent on the same map; w, h: map size in yards;
--   radius: yards to the minimap edge; half: minimap half width in pixels;
--   facing: radians (only when the minimap rotates).
function MM.Offset(player, pin, w, h, radius, half, facing)
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
  if d > radius then return nil, d end
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

function MM.Update()
  if not holder then return end
  local pos = ns.Game.Position(here)
  local on = ns.db and ns.db.settings.minimap
  local w, h, radius
  if on and pos and pos.map == MM.map then
    w, h = ns.Game.geo.size(pos.map)
    radius = C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius()
  end
  local shown = 0
  if not (w and w > 0 and radius and radius > 0) then laid.pins = nil end -- hidden: lay out again next time
  if w and w > 0 and radius and radius > 0 then
    local half = (Minimap:GetWidth() or 140) / 2
    local facing
    if GetCVar and GetCVar("rotateMinimap") == "1" and GetPlayerFacing then facing = GetPlayerFacing() end
    -- standing still (same spot, facing, zoom and pins): the layout is as it was
    if laid.pins == MM.pins and laid.map == pos.map and laid.x == pos.x and laid.y == pos.y
      and laid.facing == facing and laid.radius == radius and laid.half == half then
      return
    end
    laid.pins, laid.map, laid.x, laid.y, laid.facing, laid.radius, laid.half =
      MM.pins, pos.map, pos.x, pos.y, facing, radius, half
    for _, p in ipairs(MM.pins) do
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
  MM.pins, MM.map = {}, pos and pos.map
  if ds and pos then MM.pins = build(ds, char, pos.map) end
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

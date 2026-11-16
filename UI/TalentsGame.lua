-- The next talents of the chosen build, marked in the game's own talent window. The
-- player opens the window (N) and clicks the marked talents, then Apply: the game's
-- own clicks spend the points. Lvls! only reads the window and adds its marks: it
-- never loads it, opens it, puts a build in it or spends a point from addon code.
-- Any of that runs Blizzard's talent code under Lvls!' taint, and the Edit Mode
-- layout of the action bars stays tainted for the session: actions blocked in combat
-- (ErikTMA/Lvls#2, MainActionBar:SetPointBase after /petattack).
-- Hooks: EventRegistry callbacks only (CallbackRegistry runs them with
-- securecallfunction, so they cannot taint the game's code that fires them):
--   "PlayerSpellsFrame.TalentTab.Show", "TalentFrameBase.ButtonsUpdated" (after a
--   click, the window's buttons redrawn): the marks again;
--   "TalentDisplay.TooltipCreated": a line on the talent's tooltip.
-- Source: wow-ui-source branch forever (1.60.1): Blizzard_PlayerSpells (Camelot),
-- Blizzard_SharedTalentUI, Blizzard_SharedXMLBase/CallbackRegistry.lua.
local _, ns = ...
local G = ns:NewModule("TalentsGame")

local function has(t, k) return type(t) == "table" and type(t[k]) == "function" end

-- { [node] = { order numbers } } of the points due, in the build's order
function G.Marks(plan)
  local out = {}
  for i, p in ipairs(plan or {}) do
    out[p.id] = out[p.id] or {}
    table.insert(out[p.id], i)
  end
  return out
end

-- the game's talent buttons, when its window was loaded (by the game, never here)
local function buttons()
  local tf = type(PlayerSpellsFrame) == "table" and PlayerSpellsFrame.TalentsFrame
  if not (tf and has(tf, "EnumerateAllTalentButtons")) then return function() return nil end end
  local ok, it, state, first = pcall(tf.EnumerateAllTalentButtons, tf)
  if not ok then return function() return nil end end
  return it, state, first
end

local function nodeOf(button)
  if has(button, "GetNodeID") then
    local ok, id = pcall(button.GetNodeID, button)
    if ok then return id end
  end
  return nil
end

-- The number of each due talent's first point on its button; the rest hidden.
function G.Badges()
  local marks = G.marks or {}
  for b in buttons() do
    local id = nodeOf(b)
    local pts = id and marks[id]
    if pts and pts[1] then
      if not b.lvlsOrder then
        b.lvlsOrder = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        b.lvlsOrder:SetPoint("TOPLEFT", b, "TOPLEFT", -2, 4)
        b.lvlsOrder:SetTextColor(1, 0.48, 0.1)
      end
      b.lvlsOrder:SetText(tostring(pts[1]))
      b.lvlsOrder:Show()
    elseif b.lvlsOrder then
      b.lvlsOrder:Hide()
    end
  end
end

-- What is due changed: new marks. On the window's own redraws the points just
-- clicked (staged, not applied yet) are already counted, so the marks move on.
function G.Set(plan)
  G.marks = G.Marks(plan)
  G.Badges()
end

local function redraw()
  -- a click in the window: what is due now, quietly (no chat line per click)
  if ns.TalentsData and ns.cdb then pcall(ns.TalentsData.Due, true) end
  G.Badges()
end

local function onTooltip(_, button, tooltip)
  if not (G.marks and tooltip and has(tooltip, "AddLine")) then return end
  local id = nodeOf(button)
  local pts = id and G.marks[id]
  if not pts then return end
  tooltip:AddLine(" ")
  tooltip:AddLine("Lvls! build: learn this next (" .. table.concat(pts, ", ") .. ")", 1, 0.48, 0.1, true)
  tooltip:Show()
end

local hooked
function G.Hook()
  if hooked or not has(EventRegistry, "RegisterCallback") then return end
  hooked = true
  pcall(EventRegistry.RegisterCallback, EventRegistry, "PlayerSpellsFrame.TalentTab.Show", redraw, G)
  pcall(EventRegistry.RegisterCallback, EventRegistry, "TalentFrameBase.ButtonsUpdated", redraw, G)
  pcall(EventRegistry.RegisterCallback, EventRegistry, "TalentDisplay.TooltipCreated", onTooltip, G)
end

ns.Events.On("LVLS_TALENTS_DUE", function(plan) G.Set(plan) end)
ns.Events.On("LVLS_LOADED", function() G.Hook() end)

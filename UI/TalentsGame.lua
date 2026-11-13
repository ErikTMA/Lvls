-- Editing a build in the game's own talent window. The window shows the build the
-- way it shows a talent link from chat: PlayerSpellsFrame:SetInspectString(loadout,
-- level) puts it in its view mode with the build's ranks on the game's own buttons,
-- so every tooltip is the game's, at the build's rank. In that mode a click buys
-- nothing; the window still announces it (EventRegistry "TalentButton.OnClick",
-- Blizzard_TalentButtonSpend.lua), and Lvls! turns it into a point in the build's
-- order: left-click one more point, right-click its last point out. Each talent shows
-- the number of its first point in the order, and its tooltip ends with all of them.
-- The order list itself is Lvls!' talent window, docked beside the game's.
-- Source: wow-ui-source branch forever (1.60.1): Blizzard_PlayerSpells (Camelot),
-- Blizzard_ClassTalentImportExport.lua (the loadout string), Blizzard_SharedTalentUI.
-- When any of it is missing, UI/Talents draws the trees itself.
local _, ns = ...
local G = ns:NewModule("TalentsGame")

G.LEVEL = 60 -- the view's level: all 51 points
-- ChrSpecialization (forever 1.60.1): one spec per class; the loadout's header names it.
G.SPEC_OF_CLASS = { [1] = 1491, [2] = 1486, [3] = 1485, [4] = 1488, [5] = 1487, [7] = 1489, [8] = 1482,
  [9] = 1490, [11] = 1484 }

local function has(t, k) return type(t) == "table" and type(t[k]) == "function" end

-- The game's loadout string (Blizzard_ClassTalentImportExport.lua): serialization
-- version (8 bits), spec (16), tree hash (16 x 8 bits; zeros: not checked, which the
-- format allows for loadouts made outside the game), then for each node of the tree
-- in C_Traits.GetTreeNodes order: selected (1); when selected: purchased (1),
-- partially ranked (1) and then the ranks (6), choice node (1). Forever's talents are
-- all single nodes. Writes into stream (ExportUtil's): AddValue(bits, value).
function G.Write(stream, version, specID, nodes, ranks, maxOf)
  stream:AddValue(8, version)
  stream:AddValue(16, specID)
  for _ = 1, 16 do stream:AddValue(8, 0) end
  for _, id in ipairs(nodes) do
    local r = ranks[id] or 0
    if r > 0 then
      stream:AddValue(1, 1)
      stream:AddValue(1, 1)
      if r ~= maxOf(id) then
        stream:AddValue(1, 1)
        stream:AddValue(6, r)
      else
        stream:AddValue(1, 0)
      end
      stream:AddValue(1, 0)
    else
      stream:AddValue(1, 0)
    end
  end
end

local function frameOK()
  return type(PlayerSpellsFrame) == "table" and has(PlayerSpellsFrame, "SetInspectString")
    and type(PlayerSpellsFrame.TalentsFrame) == "table"
end

-- Can the game's window show builds? Loads it (it loads on demand) when needed.
function G.Supported()
  if not (has(C_Traits, "GetTreeNodes") and has(C_Traits, "GetLoadoutSerializationVersion")
      and has(ExportUtil, "MakeExportDataStream") and has(EventRegistry, "RegisterCallback")
      and type(ShowUIPanel) == "function") then
    return false
  end
  if not frameOK() and type(PlayerSpellsFrame_LoadUI) == "function" then pcall(PlayerSpellsFrame_LoadUI) end
  return frameOK()
end

function G.SpecID(classId)
  if has(PlayerUtil, "GetCurrentSpecID") then
    local ok, id = pcall(PlayerUtil.GetCurrentSpecID)
    if ok and type(id) == "number" and id > 0 then return id end
  end
  return G.SPEC_OF_CLASS[classId]
end

-- The loadout string for these ranks, or nil and why.
function G.String(classId, tree, ranks)
  local spec = G.SpecID(classId)
  if not (spec and tree) then return nil, "no spec" end
  local okN, nodes = pcall(C_Traits.GetTreeNodes, tree.tree)
  local okV, version = pcall(C_Traits.GetLoadoutSerializationVersion)
  if not (okN and type(nodes) == "table" and okV and type(version) == "number") then return nil, "the game's tree is not readable" end
  local config = ns.TalentsData.ConfigID()
  local function maxOf(id)
    local e = tree.byId[id]
    if config and has(C_Traits, "GetNodeInfo") then
      local ok, info = pcall(C_Traits.GetNodeInfo, config, id)
      if ok and type(info) == "table" and type(info.maxRanks) == "number" and info.maxRanks > 0 then return info.maxRanks end
    end
    return e and e.node.m or 1
  end
  local stream = ExportUtil.MakeExportDataStream()
  local ok, err = pcall(G.Write, stream, version, spec, nodes, ranks, maxOf)
  if not ok then return nil, tostring(err) end
  return stream:GetExportString()
end

-- badges: the number of each talent's first point on the game's buttons
local function buttons()
  local tf = PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame
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

function G.Badges(points)
  for b in buttons() do
    local id = nodeOf(b)
    local pts = G.active and id and points and points[id]
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

local function onClick(_, button, mouse)
  if not (G.active and G.onPoint) then return end
  if not (PlayerSpellsFrame and has(PlayerSpellsFrame, "GetInspectString") and PlayerSpellsFrame:GetInspectString() == G.shown) then return end
  local id = nodeOf(button)
  if id then G.onPoint(id, mouse == "RightButton") end
end

local function onTooltip(_, button, tooltip)
  if not (G.active and G.points and tooltip and has(tooltip, "AddLine")) then return end
  local id = nodeOf(button)
  local pts = id and G.points[id]
  if not pts then return end
  local list = {}
  for _, n in ipairs(pts) do list[#list + 1] = ("%d (level %d)"):format(n, ns.Talents.Level(n)) end
  tooltip:AddLine(" ")
  tooltip:AddLine("Lvls! build: point " .. table.concat(list, ", "), 1, 0.48, 0.1, true)
  tooltip:AddLine("Left-click: one more point · Right-click: its last point out", 0.6, 0.6, 0.6, true)
  tooltip:Show()
end

local hooked
local function hook()
  if hooked then return end
  hooked = true
  pcall(EventRegistry.RegisterCallback, EventRegistry, "TalentButton.OnClick", onClick, G)
  pcall(EventRegistry.RegisterCallback, EventRegistry, "TalentDisplay.TooltipCreated", onTooltip, G)
  if PlayerSpellsFrame and has(PlayerSpellsFrame, "HookScript") then
    PlayerSpellsFrame:HookScript("OnHide", function()
      if G.active and not G.closing and G.onClosed then G.onClosed() end
    end)
  end
end

-- Show these ranks in the game's window (opening it on its talents). points: { [node]
-- = { point numbers } } for the badges. onPoint(node, remove) for clicks, onClosed()
-- when the player closes the window. true, or false and why.
function G.Show(classId, tree, ranks, points, onPoint, onClosed)
  if type(InCombatLockdown) == "function" and InCombatLockdown() then return false, "in combat" end
  if not G.Supported() then return false, "the game's talent window cannot show builds" end
  local s, why = G.String(classId, tree, ranks)
  if not s then return false, why end
  hook()
  G.onPoint, G.onClosed, G.points = onPoint, onClosed, points
  local f = PlayerSpellsFrame
  if s ~= G.shown or not (has(f, "IsInspecting") and f:IsInspecting()) then
    local ok, err = pcall(f.SetInspectString, f, s, G.LEVEL)
    if not ok or (has(f, "IsInspecting") and not f:IsInspecting()) then
      G.active, G.shown = false, nil
      return false, "the game did not take the build" .. (ok and "" or (": " .. tostring(err)))
    end
    G.shown = s
  end
  G.active = true
  if not f:IsShown() then
    if has(f, "TrySetTab") and type(PlayerSpellsUtil) == "table" and PlayerSpellsUtil.FrameTabs then
      pcall(f.TrySetTab, f, PlayerSpellsUtil.FrameTabs.ClassTalents)
    end
    pcall(ShowUIPanel, f)
  end
  G.Badges(points)
  if C_Timer and C_Timer.After then C_Timer.After(0, function() if G.active then G.Badges(G.points) end end) end
  return true
end

function G.Frame() return frameOK() and PlayerSpellsFrame or nil end

-- Done editing: the window back to the character's own talents, and closed.
function G.Close()
  if not G.active then return end
  G.active = false
  G.Badges(nil)
  local f = PlayerSpellsFrame
  G.closing = true
  if f and has(f, "GetInspectString") and f:GetInspectString() == G.shown then
    pcall(f.SetInspectString, f, nil)
    if f:IsShown() and type(HideUIPanel) == "function" then pcall(HideUIPanel, f) end
  end
  G.closing = false
  G.shown, G.points, G.onPoint, G.onClosed = nil, nil, nil, nil
end

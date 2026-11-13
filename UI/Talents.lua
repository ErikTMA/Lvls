-- The talent window (/lvls talents, Settings -> Lvls! -> Talents).
--   Choose: the three trees of your class, the one with most points preselected
--     (none spent: the class's leveling tree): only a suggestion, nothing is learned
--     until you pick a build and press Learn. Under it the builds for that tree:
--     Lvls!'s own (Data/forever/TalentBuilds.lua, preselected) and yours: New / Edit /
--     Copy / Delete (Lvls!'s own are edited as a copy). Turn off: Lvls! leaves your
--     talents alone and does not ask again (a talent reset asks again unless it is off).
--   Edit: the game's own talent window shows the build (UI/TalentsGame), with this
--     window's order panel docked beside it; when the game's window cannot, this
--     window draws the three trees itself. Left-click a talent: one more point, at the
--     end of the order; right-click: its last point out. The order is the list, one
--     line per point with the level it comes at: move a point up or down (only where
--     the tree allows it) or take it out. A point the tree no longer allows after a
--     change is red, with why, until it is fixed.
-- Learning itself is Adapters/Talents; when the game wants a click for it, a
-- question with a Learn button comes up.
local _, ns = ...
local TU = ns:NewModule("TalentsUI")
local T = ns.Talents

TU.CELL, TU.GAP = 34, 6
TU.LIST_ROWS = 13
TU.SIDE = 276 -- the order panel's width
TU.WIDTH, TU.HEIGHT = 840, 470
TU.ASK = "LVLS_TALENTS_LEARN"
local C = { bg = { 0.067, 0.067, 0.067, 0.96 }, panel = { 0.125, 0.125, 0.125, 0.95 }, bar = { 0.23, 0.23, 0.23, 1 },
  accent = { 1, 0.48, 0.1 }, text = { 0.92, 0.92, 0.92 }, dim = { 0.5, 0.5, 0.5 }, bad = { 1, 0.35, 0.3 },
  good = { 0.4, 1, 0.4 }, part = { 1, 0.82, 0.25 } }

local frame
TU.state = { mode = "pick" } -- mode "pick" | "edit"; spec, build (name) picked; edit = { name, spec, order, original }

-- pure models --------------------------------------------------------------

-- The choose page: { cards = { { name, points, suggested } }, spec, builds, build =
-- the one selected: the chosen one when it is there, else Lvls!'s own for the spec }.
function TU.PickModel(classToken, classId, points, builds, chosenSpec, shipped, chosenBuild)
  local specs = ns.Gear.SPECS[classToken] or {}
  local suggested = T.Suggested(classToken, points or {})
  local m = { cards = {}, spec = chosenSpec or suggested, suggested = suggested }
  for i, sp in ipairs(specs) do
    m.cards[i] = { name = sp.name, points = (points or {})[i] or 0, suggested = i == suggested }
  end
  m.builds = T.BuildsFor(builds, classId, m.spec, shipped)
  for _, b in ipairs(m.builds) do
    if b.name == chosenBuild then m.build = b.name end
  end
  if not m.build then
    for _, b in ipairs(m.builds) do if b.shipped then m.build = b.name; break end end
  end
  local spent = 0
  for _, p in ipairs(points or {}) do spent = spent + p end
  m.why = spent > 0 and ("%s has the most points"):format(specs[suggested] and specs[suggested].name or "?")
    or "No points yet: the class's leveling tree"
  return m
end

-- The editor's trees and list: cells[nodeId] = { rank, max, can, why, points = { n... } },
-- rows = { { id, name, rank, max, point, level, ok, why } }, spent.
function TU.EditModel(tree, order)
  local steps, ranks = T.Simulate(tree, order)
  local m = { cells = {}, rows = {}, spent = 0 }
  for id, e in pairs(tree.byId) do
    local can, why = T.CanAdd(tree, id, ranks)
    m.cells[id] = { rank = ranks[id] or 0, max = e.node.m, can = can, why = why, points = {} }
  end
  for i, s in ipairs(steps) do
    local e = tree.byId[s.id]
    local n = e and e.node
    m.rows[i] = { id = s.id, name = n and n.n or ("talent " .. tostring(s.id)), rank = s.rank, max = n and n.m or 0,
      point = s.point, level = s.point and T.Level(s.point), ok = s.ok, why = s.why, spell = n and n.s }
    if s.ok then
      m.spent = m.spent + 1
      local cell = m.cells[s.id]
      if cell then cell.points[#cell.points + 1] = s.point end
    end
  end
  return m
end

-- widgets ---------------------------------------------------------------------

local function bg(f, c)
  local t = f:CreateTexture(nil, "BACKGROUND")
  t:SetAllPoints(f)
  t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
  return t
end

local function text(parent, font, r, g, b)
  local s = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  if r then s:SetTextColor(r, g, b) end
  if s.SetJustifyH then s:SetJustifyH("LEFT") end
  return s
end

local function button(parent, label, w, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, 22)
  b.bg = bg(b, C.bar)
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.text:SetText(label)
  local h = b:CreateTexture(nil, "HIGHLIGHT")
  h:SetAllPoints(b)
  h:SetColorTexture(1, 1, 1, 0.12)
  b:SetScript("OnClick", onClick)
  b.SetLabel = function(self, t) self.text:SetText(t) end
  b.SetOn = function(self, on)
    self.on = on
    if self.Enable then if on then self:Enable() else self:Disable() end end
    self.text:SetTextColor(on and 1 or 0.45, on and 1 or 0.45, on and 1 or 0.45)
  end
  return b
end

local function tip(owner, lines)
  if not GameTooltip then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  for i, l in ipairs(lines) do
    if i == 1 then GameTooltip:SetText(l[1], l[2] or 1, l[3] or 1, l[4] or 1, 1, true)
    else GameTooltip:AddLine(l[1], l[2] or 1, l[3] or 1, l[4] or 1, true) end
  end
  GameTooltip:Show()
end
local function untip() if GameTooltip then GameTooltip:Hide() end end

local function spellIcon(spell)
  if C_Spell and type(C_Spell.GetSpellTexture) == "function" and spell and spell > 0 then
    local ok, icon = pcall(C_Spell.GetSpellTexture, spell)
    if ok and icon then return icon end
  end
  return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function say(msg, bad)
  if not frame then return end
  frame.status:SetText(msg or "")
  local c = bad and C.bad or C.dim
  frame.status:SetTextColor(c[1], c[2], c[3])
end

-- the choose page -----------------------------------------------------------

local function classInfo()
  local token, id = ns.GearData.Class()
  return token, id, T.Tree(id)
end

local function buildPick(f)
  local p = CreateFrame("Frame", nil, f)
  p:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -40)
  p:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 40)
  p.intro = text(p, "GameFontHighlight", C.text[1], C.text[2], C.text[3])
  p.intro:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
  p.intro:SetWidth(TU.WIDTH - 24)
  p.intro:SetText("Pick the spec your talents follow, then a build: Lvls! learns its points in its order as you level. "
    .. "The preselected spec is only a suggestion. Nothing is learned until you press Learn.")
  p.cards = {}
  for i = 1, 3 do
    local card = CreateFrame("Button", nil, p)
    card:SetSize(262, 74)
    card:SetPoint("TOPLEFT", p, "TOPLEFT", (i - 1) * 274, -44)
    card.bg = bg(card, C.panel)
    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(40, 40)
    card.icon:SetPoint("LEFT", card, "LEFT", 10, 0)
    card.name = text(card, "GameFontNormalLarge", C.part[1], C.part[2], C.part[3])
    card.name:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 10, -2)
    card.points = text(card, "GameFontHighlightSmall", C.text[1], C.text[2], C.text[3])
    card.points:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -4)
    card.tag = text(card, "GameFontDisableSmall", C.accent[1], C.accent[2], C.accent[3])
    card.tag:SetPoint("TOPLEFT", card.points, "BOTTOMLEFT", 0, -3)
    card.ring = card:CreateTexture(nil, "BORDER")
    card.ring:SetPoint("TOPLEFT", card, "TOPLEFT", -2, 2)
    card.ring:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", 2, -2)
    card.ring:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    local h = card:CreateTexture(nil, "HIGHLIGHT")
    h:SetAllPoints(card)
    h:SetColorTexture(1, 1, 1, 0.06)
    card:SetScript("OnClick", function()
      TU.state.spec, TU.state.build = i, nil
      TU.Refresh()
    end)
    p.cards[i] = card
  end
  p.buildsTitle = text(p, "GameFontNormal", C.part[1], C.part[2], C.part[3])
  p.buildsTitle:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -136)
  p.rows = {}
  for i = 1, 8 do
    local r = CreateFrame("Button", nil, p)
    r:SetSize(560, 22)
    r:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -156 - (i - 1) * 24)
    r.bg = bg(r, C.panel)
    r.mark = r:CreateTexture(nil, "ARTWORK")
    r.mark:SetSize(4, 22)
    r.mark:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.mark:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    r.text = text(r, "GameFontHighlightSmall", C.text[1], C.text[2], C.text[3])
    r.text:SetPoint("LEFT", r, "LEFT", 12, 0)
    r.info = text(r, "GameFontDisableSmall", C.dim[1], C.dim[2], C.dim[3])
    r.info:SetPoint("RIGHT", r, "RIGHT", -8, 0)
    local h = r:CreateTexture(nil, "HIGHLIGHT")
    h:SetAllPoints(r)
    h:SetColorTexture(1, 1, 1, 0.08)
    r:SetScript("OnClick", function(self) TU.state.build = self.name; TU.Refresh() end)
    r:SetScript("OnDoubleClick", function(self) TU.state.build = self.name; TU.EditSelected() end)
    p.rows[i] = r
  end
  p.none = text(p, "GameFontDisableSmall", C.dim[1], C.dim[2], C.dim[3])
  p.none:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -160)
  p.none:SetWidth(560)
  p.new = button(p, "New build", 120, function() TU.Edit(nil) end)
  p.new:SetPoint("TOPLEFT", p, "TOPLEFT", 580, -156)
  p.edit = button(p, "Edit", 120, function() TU.EditSelected() end)
  p.edit:SetPoint("TOPLEFT", p.new, "BOTTOMLEFT", 0, -6)
  p.copy = button(p, "Copy", 120, function()
    local b = TU.Find(TU.state.build)
    if b then TU.Edit(b.name, true) end
  end)
  p.copy:SetPoint("TOPLEFT", p.edit, "BOTTOMLEFT", 0, -6)
  p.delete = button(p, "Delete", 120, function()
    local _, id = classInfo()
    if TU.state.build and not T.Reserved(TU.state.build) then
      ns.TalentsData.Delete(id, TU.state.build)
      say(("deleted %s"):format(TU.state.build))
      TU.state.build = nil
      TU.Refresh()
    end
  end)
  p.delete:SetPoint("TOPLEFT", p.copy, "BOTTOMLEFT", 0, -18)
  p.learn = button(p, "Learn with this build", 180, function()
    if not TU.state.build then return end
    ns.TalentsData.Use(TU.state.spec, TU.state.build)
    say(("learning with %s"):format(TU.state.build))
    TU.Refresh()
  end)
  p.learn:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 0, 0)
  p.off = button(p, "Turn off", 120, function()
    ns.TalentsData.TurnOff()
    say("off: Lvls! leaves your talents alone. /lvls talents turns it back on")
    TU.Refresh()
  end)
  p.off:SetPoint("LEFT", p.learn, "RIGHT", 8, 0)
  p.later = button(p, "Not now", 120, function() TU.Hide() end)
  p.later:SetPoint("LEFT", p.off, "RIGHT", 8, 0)
  p.now = text(p, "GameFontDisableSmall", C.dim[1], C.dim[2], C.dim[3])
  p.now:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 4)
  return p
end

function TU.Find(name) return ns.TalentsData.Find(name) end

-- Edit the selected build: Lvls!'s own as a copy (they stay as they are).
function TU.EditSelected()
  local b = TU.Find(TU.state.build)
  if b then TU.Edit(b.name, b.shipped) end
end

local function refreshPick()
  local p = frame.pick
  local token, id, tree = classInfo()
  local points = ns.GearData.Points()
  local m = TU.PickModel(token, id, points, ns.TalentsData.Builds(), TU.state.spec, ns.TalentsData.Shipped(),
    TU.state.build)
  TU.state.spec, TU.state.build = m.spec, m.build
  for i, card in ipairs(p.cards) do
    local c = m.cards[i]
    card:SetShown(c ~= nil)
    if c then
      card.name:SetText(c.name)
      card.points:SetText(("%d point%s spent"):format(c.points, c.points == 1 and "" or "s"))
      card.tag:SetText(c.suggested and ("Suggested: " .. m.why) or "")
      card.ring:SetShown(i == m.spec)
      local first = tree and tree.tabs[i] and tree.tabs[i].nodes[1]
      card.icon:SetTexture(spellIcon(first and first.s))
    end
  end
  local specName = m.cards[m.spec] and m.cards[m.spec].name or "?"
  p.buildsTitle:SetText(("Builds for %s"):format(specName))
  local found = false
  for i, r in ipairs(p.rows) do
    local b = m.builds[i]
    r:SetShown(b ~= nil)
    if b then
      r.name = b.name
      r.text:SetText(b.name)
      local problem = tree and T.FirstProblem(tree, b.order)
      r.info:SetText(("%s%d points%s"):format(b.shipped and (b.source and "Wowhead leveling guide · " or "Lvls!'s own · ") or "", #b.order,
        problem and (" · stops at point " .. problem) or ""))
      r.mark:SetShown(b.name == TU.state.build)
      if b.name == TU.state.build then found = true end
    end
  end
  if not found then TU.state.build = nil end
  p.none:SetShown(#m.builds == 0)
  p.none:SetText(("No builds for %s yet. Press New build: click the talents in the order you want them."):format(specName))
  local own = TU.state.build ~= nil and not T.Reserved(TU.state.build)
  p.edit:SetOn(TU.state.build ~= nil)
  p.edit:SetLabel((TU.state.build and not own) and "Edit a copy" or "Edit")
  p.copy:SetOn(own)
  p.delete:SetOn(own)
  p.learn:SetOn(TU.state.build ~= nil)
  local c = ns.TalentsData.Choice()
  if c.off then p.now:SetText("Now: off")
  elseif c.build then p.now:SetText(("Now: %s, %s"):format((ns.Gear.SPECS[token] or {})[c.spec] and ns.Gear.SPECS[token][c.spec].name or "?", c.build))
  else p.now:SetText("Now: nothing chosen") end
end

-- the editor ------------------------------------------------------------------
-- p.trees: the three trees drawn here (when the game's window cannot show the build);
-- p.side: the order panel (name, points, the order list, Save / Cancel), on the right
-- of this window, or alone and docked beside the game's talent window.

local function treeOrigin(ti)
  return 12 + (ti - 1) * (4 * (TU.CELL + TU.GAP) + 16), -48
end

local function buildSide(p)
  local s = CreateFrame("Frame", nil, p)
  s:SetPoint("TOPRIGHT", p, "TOPRIGHT", -12, 0)
  s:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -12, 0)
  s:SetWidth(TU.SIDE)
  s.nameLabel = text(s, "GameFontHighlightSmall", C.dim[1], C.dim[2], C.dim[3])
  s.nameLabel:SetPoint("TOPLEFT", s, "TOPLEFT", 0, -12)
  s.nameLabel:SetText("Name")
  s.name = CreateFrame("EditBox", nil, s, "InputBoxTemplate")
  s.name:SetSize(TU.SIDE - 50, 20)
  s.name:SetPoint("LEFT", s.nameLabel, "RIGHT", 12, 0)
  if s.name.SetAutoFocus then s.name:SetAutoFocus(false) end
  s.name:SetScript("OnEnterPressed", function(self) if self.ClearFocus then self:ClearFocus() end end)
  s.name:SetScript("OnEscapePressed", function(self) if self.ClearFocus then self:ClearFocus() end end)
  s.spec = text(s, "GameFontHighlightSmall", C.text[1], C.text[2], C.text[3])
  s.spec:SetPoint("TOPLEFT", s, "TOPLEFT", 0, -36)
  s.spent = text(s, "GameFontNormal", C.part[1], C.part[2], C.part[3])
  s.spent:SetPoint("TOPRIGHT", s, "TOPRIGHT", 0, -36)
  s.mine = button(s, "Start from my talents", 150, function() TU.FromMine() end)
  s.mine:SetPoint("TOPLEFT", s, "TOPLEFT", 0, -54)
  s.clear = button(s, "Clear", 70, function()
    TU.state.edit.order = {}
    TU.Refresh()
  end)
  s.clear:SetPoint("LEFT", s.mine, "RIGHT", 6, 0)
  s.list = CreateFrame("Frame", nil, s)
  s.list:SetPoint("TOPLEFT", s, "TOPLEFT", 0, -100)
  s.list:SetSize(TU.SIDE, TU.LIST_ROWS * 20 + 4)
  bg(s.list, C.panel)
  s.list:EnableMouseWheel(true)
  s.list:SetScript("OnMouseWheel", function(_, delta) TU.Scroll(-delta * 3) end)
  s.listTitle = text(s, "GameFontNormal", C.part[1], C.part[2], C.part[3])
  s.listTitle:SetPoint("BOTTOMLEFT", s.list, "TOPLEFT", 0, 4)
  s.listTitle:SetText("Order")
  s.rows = {}
  for i = 1, TU.LIST_ROWS do
    local r = CreateFrame("Button", nil, s.list)
    r:SetSize(TU.SIDE - 4, 20)
    r:SetPoint("TOPLEFT", s.list, "TOPLEFT", 2, -2 - (i - 1) * 20)
    r.num = text(r, "GameFontDisableSmall", C.dim[1], C.dim[2], C.dim[3])
    r.num:SetPoint("LEFT", r, "LEFT", 2, 0)
    r.num:SetWidth(52)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(16, 16)
    r.icon:SetPoint("LEFT", r, "LEFT", 56, 0)
    r.text = text(r, "GameFontHighlightSmall", C.text[1], C.text[2], C.text[3])
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
    r.text:SetWidth(TU.SIDE - 140)
    local h = r:CreateTexture(nil, "HIGHLIGHT")
    h:SetAllPoints(r)
    h:SetColorTexture(1, 1, 1, 0.06)
    r.up = button(r, "^", 18, function(self) TU.MoveRow(self:GetParent().index, -1) end)
    r.down = button(r, "v", 18, function(self) TU.MoveRow(self:GetParent().index, 1) end)
    r.del = button(r, "x", 18, function(self) TU.RemoveRow(self:GetParent().index) end)
    for _, b in ipairs({ r.up, r.down, r.del }) do b:SetHeight(18) end
    r.del:SetPoint("RIGHT", r, "RIGHT", -2, 0)
    r.down:SetPoint("RIGHT", r.del, "LEFT", -2, 0)
    r.up:SetPoint("RIGHT", r.down, "LEFT", -2, 0)
    r:SetScript("OnEnter", function(self)
      local row = self.row
      if not row then return end
      local lines = { { row.name } }
      if row.ok then
        lines[#lines + 1] = { ("Point %d, level %d: rank %d/%d"):format(row.point, row.level, row.rank, row.max), 0.8, 0.8, 0.8 }
      else
        lines[#lines + 1] = { "Not allowed here: " .. (row.why or "?"), C.bad[1], C.bad[2], C.bad[3] }
      end
      lines[#lines + 1] = { "^ v: earlier or later · x: take it out", 0.6, 0.6, 0.6 }
      tip(self, lines)
    end)
    r:SetScript("OnLeave", untip)
    s.rows[i] = r
  end
  s.save = button(s, "Save", 100, function() TU.SaveEdit() end)
  s.save:SetPoint("TOPLEFT", s.list, "BOTTOMLEFT", 0, -10)
  s.cancel = button(s, "Cancel", 100, function() TU.CancelEdit() end)
  s.cancel:SetPoint("LEFT", s.save, "RIGHT", 8, 0)
  return s
end

local function buildEdit(f)
  local p = CreateFrame("Frame", nil, f)
  p:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -30)
  p:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 40)
  p.trees = CreateFrame("Frame", nil, p)
  p.trees:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
  p.trees:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -(TU.SIDE + 24), 0)
  p.heads, p.cells = {}, {}
  for ti = 1, 3 do
    local x, y = treeOrigin(ti)
    local h = text(p.trees, "GameFontNormal", C.part[1], C.part[2], C.part[3])
    h:SetPoint("TOPLEFT", p.trees, "TOPLEFT", x, y + 22)
    p.heads[ti] = h
    local back = CreateFrame("Frame", nil, p.trees)
    back:SetPoint("TOPLEFT", p.trees, "TOPLEFT", x - 4, y + 4)
    back:SetSize(4 * (TU.CELL + TU.GAP) + 2, 7 * (TU.CELL + TU.GAP) + 2)
    bg(back, C.panel)
  end
  p.hint = text(p.trees, "GameFontDisableSmall", C.dim[1], C.dim[2], C.dim[3])
  p.hint:SetPoint("BOTTOMLEFT", p.trees, "BOTTOMLEFT", 12, 0)
  p.hint:SetWidth(TU.WIDTH - TU.SIDE - 48)
  p.hint:SetText("Left-click a talent: one more point at the end of the order. Right-click: its last point out. "
    .. "The order is the order Lvls! learns them in, one per level from 10.")
  p.side = buildSide(p)
  p.name = p.side.name
  return p
end

-- The game's own tooltip for a talent at a rank (Blizzard_TalentDisplay.lua builds it
-- the same way: the title, then the trait entry at the current rank and, while ranks
-- are left, at the next one).
function TU.TalentTooltip(owner, node, rank)
  if not GameTooltip then return false end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  local shown = false
  if type(GameTooltip.AppendInfo) == "function" and node.e then
    GameTooltip:SetText(node.n, 1, 1, 1, 1, true)
    GameTooltip:AddLine(("Rank %d/%d"):format(rank, node.m), 1, 1, 1)
    GameTooltip:AddLine(" ")
    shown = pcall(GameTooltip.AppendInfo, GameTooltip, "GetTraitEntry", node.e, math.max(rank, 1))
    if shown and rank > 0 and rank < node.m then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("Next rank:", 1, 1, 1)
      pcall(GameTooltip.AppendInfo, GameTooltip, "GetTraitEntry", node.e, rank + 1)
    end
  end
  if not shown then
    GameTooltip:ClearLines()
    if type(GameTooltip.SetSpellByID) == "function" and node.s > 0 then
      pcall(GameTooltip.SetSpellByID, GameTooltip, node.s)
    else
      GameTooltip:SetText(node.n, 1, 1, 1)
    end
  end
  return true
end

local function cellFor(p, ti, node)
  local key = node.id
  local b = p.cells[key]
  if not b then
    b = CreateFrame("Button", nil, p.trees)
    b:SetSize(TU.CELL, TU.CELL)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)
    b.rank = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.rank:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
    local h = b:CreateTexture(nil, "HIGHLIGHT")
    h:SetAllPoints(b)
    h:SetColorTexture(1, 1, 1, 0.2)
    if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    b:SetScript("OnClick", function(self, mouse)
      if mouse == "RightButton" then TU.RemovePoint(self.node.id) else TU.AddPoint(self.node.id) end
    end)
    b:SetScript("OnEnter", function(self)
      local cell = self.cell or {}
      if not TU.TalentTooltip(self, self.node, cell.rank or 0) then return end
      local pts = {}
      for _, n in ipairs(cell.points or {}) do pts[#pts + 1] = ("%d (level %d)"):format(n, T.Level(n)) end
      GameTooltip:AddLine(" ")
      if #pts > 0 then GameTooltip:AddLine("Lvls! build: point " .. table.concat(pts, ", "), C.accent[1], C.accent[2], C.accent[3], true) end
      if not cell.can and cell.why then GameTooltip:AddLine(cell.why, C.bad[1], C.bad[2], C.bad[3], true) end
      GameTooltip:AddLine("Left-click: one more point · Right-click: its last point out", 0.6, 0.6, 0.6, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", untip)
    p.cells[key] = b
  end
  local x, y = treeOrigin(ti)
  b:ClearAllPoints()
  b:SetPoint("TOPLEFT", p.trees, "TOPLEFT", x + (node.c - 1) * (TU.CELL + TU.GAP), y - (node.r - 1) * (TU.CELL + TU.GAP))
  b.node = node
  b.icon:SetTexture(spellIcon(node.s))
  return b
end

local function drawTrees(p, tree, m, points, specs)
  for ti, tab in ipairs(tree.tabs) do
    p.heads[ti]:SetText(("%s  %d"):format(specs[ti] and specs[ti].name or tab.name, points[ti] or 0))
    for _, node in ipairs(tab.nodes) do
      local b = cellFor(p, ti, node)
      local cell = m.cells[node.id]
      b.cell = cell
      b.rank:SetText(("%d/%d"):format(cell.rank, cell.max))
      local col = cell.rank >= cell.max and C.good or cell.rank > 0 and C.part or C.text
      b.rank:SetTextColor(col[1], col[2], col[3])
      if b.icon.SetDesaturated then b.icon:SetDesaturated(cell.rank == 0 and not cell.can) end
      b.icon:SetAlpha((cell.rank > 0 or cell.can) and 1 or 0.45)
      b:Show()
    end
  end
end

-- This window as the order panel beside the game's talent window, or whole.
local function layout(game)
  if TU.layout == game then return end
  TU.layout = game
  if game then frame.edit.trees:Hide() else frame.edit.trees:Show() end
  frame:ClearAllPoints()
  if game then
    frame:SetSize(TU.SIDE + 24, TU.HEIGHT)
    frame:SetPoint("TOPLEFT", ns.TalentsGame.Frame(), "TOPRIGHT", 4, 0)
  else
    frame:SetSize(TU.WIDTH, TU.HEIGHT)
    ns.Style.Place(frame, "talents", "CENTER", "CENTER", 0, 40)
  end
  frame.status:SetWidth((game and TU.SIDE or TU.WIDTH - 24))
end

local function refreshEdit()
  local p = frame.edit
  local s = p.side
  local token, id, tree = classInfo()
  local e = TU.state.edit
  if not (tree and e) then return end
  local m = TU.EditModel(tree, e.order)
  TU.model = m
  local specs = ns.Gear.SPECS[token] or {}
  if s.name.GetText and s.name:GetText() ~= e.name and not s.name.typed then s.name:SetText(e.name) end
  s.spec:SetText(("Built around %s"):format(specs[e.spec] and specs[e.spec].name or "?"))
  s.spent:SetText(("%d / %d points"):format(m.spent, T.MaxPoints()))
  local ranks = select(2, T.Simulate(tree, e.order))
  local game = false
  if e.game then
    local points = {}
    for nid, cell in pairs(m.cells) do if #cell.points > 0 then points[nid] = cell.points end end
    local ok, why = ns.TalentsGame.Show(id, tree, ranks, points,
      function(nid, remove) if remove then TU.RemovePoint(nid) else TU.AddPoint(nid) end end,
      function() TU.Hide() end)
    if ok then
      game = true
    else
      e.game = false -- the game's window could not show it: the trees here
      say("the game's talent window cannot show the build (" .. tostring(why) .. "): the trees are here instead")
    end
  end
  layout(game)
  if not game then drawTrees(p, tree, m, T.Points(tree, ranks), specs) end
  local off = TU.state.scroll or 0
  local maxOff = math.max(0, #m.rows - TU.LIST_ROWS)
  if off > maxOff then off = maxOff end
  TU.state.scroll = off
  for i, r in ipairs(s.rows) do
    local idx = off + i
    local row = m.rows[idx]
    r.index, r.row = idx, row
    r:SetShown(row ~= nil)
    if row then
      r.num:SetText(row.ok and ("%d · L%d"):format(row.point, row.level) or "  --")
      r.icon:SetTexture(spellIcon(row.spell))
      r.text:SetText(("%s %d/%d"):format(row.name, row.rank, row.max))
      local c = row.ok and C.text or C.bad
      r.text:SetTextColor(c[1], c[2], c[3])
      r.up:SetOn(idx > 1)
      r.down:SetOn(idx < #m.rows)
    end
  end
end

-- editing actions (the buttons and the tree call these; tests too)

function TU.AddPoint(id)
  local _, _, tree = classInfo()
  local e = TU.state.edit
  if not (tree and e) then return false end
  local out, why = T.Append(tree, e.order, id)
  if not out then say(why, true); return false end
  e.order = out
  TU.state.scroll = math.max(0, #out - TU.LIST_ROWS)
  say("")
  TU.Refresh()
  return true
end

function TU.RemovePoint(id)
  local e = TU.state.edit
  if not e then return false end
  local out = T.RemoveLast(e.order, id)
  if not out then return false end
  e.order = out
  say("")
  TU.Refresh()
  return true
end

function TU.MoveRow(i, dir)
  local _, _, tree = classInfo()
  local e = TU.state.edit
  if not (tree and e and i) then return false end
  local out, why = T.Move(tree, e.order, i, dir)
  if not out then say("cannot move it there: " .. (why or "?"), true); return false end
  e.order = out
  say("")
  TU.Refresh()
  return true
end

function TU.RemoveRow(i)
  local e = TU.state.edit
  if not (e and i and e.order[i]) then return false end
  e.order = T.Remove(e.order, i)
  TU.Refresh()
  return true
end

function TU.Scroll(by)
  TU.state.scroll = math.max(0, (TU.state.scroll or 0) + by)
  TU.Refresh()
end

function TU.FromMine()
  local _, _, tree = classInfo()
  local st = ns.TalentsData.State()
  local e = TU.state.edit
  if not (tree and e) then return false end
  if not st then say("your talents cannot be read right now", true); return false end
  e.order = T.FromRanks(tree, st.ranks)
  say(("started from your %d points: add the rest in the order you want them"):format(#e.order))
  TU.Refresh()
  return true
end

function TU.SaveEdit()
  local _, id, tree = classInfo()
  local e = TU.state.edit
  if not (e and tree) then return false end
  local name = frame.edit.name.GetText and frame.edit.name:GetText() or e.name
  name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then say("give the build a name", true); return false end
  if T.Reserved(name) then say(("names starting with %s are Lvls!'s own builds"):format(T.SHIPPED_PREFIX), true); return false end
  if #e.order == 0 then say("the build has no points yet", true); return false end
  for _, b in ipairs(ns.TalentsData.Builds()) do
    if b.class == id and b.name == name and name ~= e.original then
      say(("there is a build called %s already"):format(name), true)
      return false
    end
  end
  local order = {}
  for i, v in ipairs(e.order) do order[i] = v end
  ns.TalentsData.Save({ name = name, class = id, spec = e.spec, order = order }, e.original)
  local problem, why = T.FirstProblem(tree, order)
  ns.TalentsGame.Close()
  TU.state.mode, TU.state.edit, TU.state.build, TU.state.spec = "pick", nil, name, e.spec
  say(problem and ("saved %s: it stops at point %d (%s)"):format(name, problem, why) or ("saved " .. name), problem ~= nil)
  TU.Refresh()
  return true
end

-- Back to choosing, the edit dropped.
function TU.CancelEdit()
  ns.TalentsGame.Close()
  TU.state.mode, TU.state.edit = "pick", nil
  TU.Refresh()
end

-- Open the editor: a saved build by name (copy: as a new one), or a new one. The
-- game's talent window shows it when it can (out of combat), else the trees here.
function TU.Edit(name, copy)
  local _, id = classInfo()
  local token = ns.GearData.Class()
  local b = name and TU.Find(name)
  local spec = b and b.spec or TU.state.spec or 1
  local order = {}
  for i, v in ipairs(b and b.order or {}) do order[i] = v end
  local specName = (ns.Gear.SPECS[token] or {})[spec] and ns.Gear.SPECS[token][spec].name or "Build"
  local base = (b and not b.shipped) and (b.name .. " copy") or specName
  local newName = (b and not copy) and b.name or T.FreeName(ns.TalentsData.Builds(), id, base)
  local inCombat = type(InCombatLockdown) == "function" and InCombatLockdown()
  TU.state.edit = { name = newName, spec = spec, order = order, original = (b and not copy) and b.name or nil,
    game = not inCombat and ns.TalentsGame.Supported() }
  TU.state.mode, TU.state.scroll = "edit", 0
  if frame then frame.edit.name.typed = nil; frame.edit.name:SetText(newName) end
  TU.Show()
end

-- the window -----------------------------------------------------------------

local function create()
  frame = CreateFrame("Frame", "LvlsTalentsFrame", UIParent)
  frame:SetSize(TU.WIDTH, TU.HEIGHT)
  frame:SetFrameStrata("DIALOG")
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  bg(frame, C.bg)
  frame.titleBar = CreateFrame("Frame", nil, frame)
  frame.titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  frame.titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
  frame.titleBar:SetHeight(28)
  bg(frame.titleBar, C.bar)
  frame.title = text(frame.titleBar, "GameFontNormal", C.accent[1], C.accent[2], C.accent[3])
  frame.title:SetPoint("LEFT", frame.titleBar, "LEFT", 12, 0)
  frame.close = button(frame.titleBar, "x", 22, function() TU.Hide() end)
  frame.close:SetPoint("RIGHT", frame.titleBar, "RIGHT", -4, 0)
  ns.Style.Draggable(frame, "talents", frame.titleBar)
  -- docked beside the game's talent window it stays there: no dragging
  local start, stop = frame.titleBar:GetScript("OnDragStart"), frame.titleBar:GetScript("OnDragStop")
  frame.titleBar:SetScript("OnDragStart", function(...) if not TU.layout and start then start(...) end end)
  frame.titleBar:SetScript("OnDragStop", function(...) if not TU.layout and stop then stop(...) end end)
  -- closed while the game's window shows the build: that view ends, the edit stays
  -- for /lvls talents to go on with
  frame:SetScript("OnHide", function() ns.TalentsGame.Close(); TU.layout = nil end)
  frame.status = text(frame, "GameFontDisableSmall", C.dim[1], C.dim[2], C.dim[3])
  frame.status:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 12)
  frame.status:SetWidth(TU.WIDTH - 24)
  frame.pick = buildPick(frame)
  frame.edit = buildEdit(frame)
  frame.edit.name:SetScript("OnTextChanged", function(self, user) if user then self.typed = true end end)
  if UISpecialFrames then table.insert(UISpecialFrames, "LvlsTalentsFrame") end -- Escape closes it
  frame:Hide()
  TU.frame = frame
end

function TU.Refresh()
  if not frame or not frame:IsShown() then return end
  local _, _, tree = classInfo()
  local editing = TU.state.mode == "edit" and TU.state.edit ~= nil and tree ~= nil
  frame.pick:SetShown(not editing)
  frame.edit:SetShown(editing)
  frame.title:SetText(editing and "Lvls! talents: edit build" or "Lvls! talents: spec and build")
  if editing then refreshEdit() else layout(false); refreshPick() end
end

function TU.Show(mode)
  if not frame then create() end
  if not select(3, classInfo()) then
    ns.Log("info", "talent trees for your class are not known")
    return false
  end
  if mode then TU.state.mode = mode end
  if not frame:IsShown() then TU.layout = nil end -- placed by the first refresh
  frame:Show()
  TU.Refresh()
  return true
end

function TU.Hide() if frame then frame:Hide() end end

-- The picker, asked by Adapters/Talents (points to spend, nothing chosen): what is
-- chosen preselected, else the suggestion. In combat it waits for the fight to end.
function TU.Pick()
  if type(InCombatLockdown) == "function" and InCombatLockdown() then TU.afterCombat = true; return false end
  TU.afterCombat = nil
  local c = ns.TalentsData.Choice()
  TU.state.mode, TU.state.spec, TU.state.build = "pick", c.spec, c.build
  return TU.Show()
end

local function define()
  if not StaticPopupDialogs or type(StaticPopup_Show) ~= "function" then return false end
  StaticPopupDialogs[TU.ASK] = StaticPopupDialogs[TU.ASK] or {
    text = "Lvls!: learn %s?",
    button1 = "Learn", button2 = "Not now",
    OnAccept = function() ns.TalentsData.Learn(true) end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  }
  return true
end

-- "Cruelty 2/5, Unbridled Wrath 1/5"
function TU.PlanText(plan)
  local names = {}
  for _, p in ipairs(plan or {}) do names[#names + 1] = ("%s %d/%d"):format(p.name, p.rank, p.max) end
  return table.concat(names, ", ")
end

ns.Events.On("LVLS_TALENTS_PICK", function() TU.Pick() end)
ns.Events.On("LVLS_TALENTS_ASK", function(plan)
  if define() then StaticPopup_Show(TU.ASK, TU.PlanText(plan)) end
end)
ns.Events.On("LVLS_UPDATED", function() if frame and frame:IsShown() and TU.state.mode == "pick" then TU.Refresh() end end)

local combat = CreateFrame and CreateFrame("Frame")
if combat then
  combat:RegisterEvent("PLAYER_REGEN_ENABLED")
  combat:SetScript("OnEvent", function() if TU.afterCombat then TU.Pick() end end)
end

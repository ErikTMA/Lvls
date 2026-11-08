-- The step viewer: a dark panel with the current step, one line per goal (icon,
-- check box, text, progress), the objectives you can do at the same time, a preview
-- of the next step and the experience bar. Prev / next browse the plan; clicking a
-- line points the arrow at it, right-clicking skips its quest.
local _, ns = ...
local V = ns:NewModule("Viewer")

V.WIDTH = 330
V.LINE = 18
V.MAX_LINES = 12
V.COLORS = {
  bg = { 0.067, 0.067, 0.067, 0.92 },     -- panel
  step = { 0.125, 0.125, 0.125, 0.95 },   -- step box
  bar = { 0.23, 0.23, 0.23, 1 },          -- title / progress bar background
  accent = { 1, 0.48, 0.1, 1 },           -- orange
  text = { 0.92, 0.92, 0.92 }, done = { 0.45, 0.45, 0.45 }, also = { 0.7, 0.75, 0.85 },
  title = { 1, 0.82, 0.25 }, travel = { 1, 0.6, 0.3 },
}
local ICONS = "Interface\\AddOns\\Lvls\\Media\\Icons"
local ICON_SLOT = { checkoff = 0, checkon = 1, accept = 2, turnin = 3, kill = 4, collect = 5, talk = 6, ["goto"] = 7,
  fly = 8, transit = 9, hearth = 10, enter = 11, path = 12 }
local ICON_SLOTS = 16

V.view = nil -- index of the step being shown (nil: follow the current step)
local frame, rows = nil, {}
V.rows = rows -- line buttons (tests click them)

-- Texture coordinates of an icon in Media/Icons.tga (32 px icons in 512 x 32).
function V.IconCoords(name)
  local i = ICON_SLOT[name] or ICON_SLOT["goto"]
  return i / ICON_SLOTS, (i + 1) / ICON_SLOTS, 0, 1
end

-- What the viewer shows, as plain data. Pure: { header, sub, lines = { { icon,
-- check, text, progress, color, line } }, next, stepNo, stepCount }. base: steps
-- finished before this plan (the numbers go on across plans and sessions).
function V.Model(ds, char, steps, current, view, base)
  base = base or 0
  local m = { lines = {}, stepCount = (steps and #steps or 0) + base }
  local i = view or current
  local st = steps and i and steps[i]
  if not st then
    m.header = "No route from here"
    m.sub = "Accept a quest or move closer to quest givers"
    return m
  end
  m.stepNo = i + base
  m.header = st.title
  if st.spot then
    m.sub = ("%s  %.1f, %.1f"):format(ds.maps[st.spot.map] or "", st.spot.x, st.spot.y)
  elseif st.kind == "dungeon" then
    m.sub = "Entrance not known yet: Lvls! learns it when you walk in"
  elseif st.kind == "use" then
    m.sub = (ns.db and ns.db.settings.itemBar) and "Click its item button, or right-click it in your bags" or "In your bags: right-click it"
  end
  if ns.guideName then
    m.sub = (m.sub and (m.sub .. "  ·  ") or "") .. (ns.sync and "Sync: " or "Guide: ") .. ns.guideName
  end
  m.spot = st.spot
  -- how to get there (current step only): "Talk to Thor, fly to Lakeshire", "Enter ..."
  if not view or view == current then
    for _, t in ipairs(ns.trip and ns.Travel.Lines(ns.trip) or {}) do
      m.lines[#m.lines + 1] = { icon = t.kind, check = "checkoff", text = t.text, color = V.COLORS.travel,
        line = { kind = t.kind, spot = t.spot, text = t.text }, travel = true }
    end
  end
  for _, l in ipairs(st.lines) do
    if #m.lines >= V.MAX_LINES then break end
    local progress
    if l.need and l.need > 1 and not l.done then progress = ("%d/%d"):format(l.have or 0, l.need) end
    local c = l.done and V.COLORS.done or (l.also and V.COLORS.also or V.COLORS.text)
    m.lines[#m.lines + 1] = { icon = ns.Steps.ICON[l.kind] or "goto", check = l.done and "checkon" or "checkoff",
      text = (l.also and "Also: " or "") .. l.text, progress = progress, color = c, line = l }
  end
  local nxt = steps[i + 1]
  if nxt then m.next = nxt.title .. ": " .. (nxt.lines[1] and nxt.lines[1].text or "") end
  m.backlog = V.Backlog(ds, ns.backlog)
  return m
end

-- "In your log for later: 3 (Westfall, Elwynn Forest), 1 grey": quests in the log
-- this plan does not hand in, so none of them is out of sight. nil when none.
function V.Backlog(ds, list)
  if not list or #list == 0 then return nil end
  local maps, seen, grey = {}, {}, 0
  for _, b in ipairs(list) do
    local name = b.map and ds.maps and ds.maps[b.map]
    if name and not seen[name] then seen[name] = true; maps[#maps + 1] = name end
    if b.grey then grey = grey + 1 end
  end
  local t = ("In your log for later: %d"):format(#list)
  if #maps > 0 then t = t .. " (" .. table.concat(maps, ", ", 1, math.min(#maps, 3)) .. (#maps > 3 and ", ..." or "") .. ")" end
  if grey > 0 then t = t .. (", %d grey: abandon to free the log"):format(grey) end
  return t
end

local function bg(f, c)
  local t = f:CreateTexture(nil, "BACKGROUND")
  t:SetAllPoints(f)
  t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
  return t
end

local function button(parent, label, w, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, 18)
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.text:SetText(label)
  local h = b:CreateTexture(nil, "HIGHLIGHT")
  h:SetAllPoints(b)
  h:SetColorTexture(1, 1, 1, 0.12)
  b:SetScript("OnClick", onClick)
  return b
end

local function row(i)
  if rows[i] then return rows[i] end
  local r = CreateFrame("Button", nil, frame.step)
  r:SetHeight(V.LINE)
  r:SetPoint("TOPLEFT", frame.step, "TOPLEFT", 6, -(40 + (i - 1) * V.LINE))
  r:SetPoint("RIGHT", frame.step, "RIGHT", -6, 0)
  r.check = r:CreateTexture(nil, "ARTWORK")
  r.check:SetSize(14, 14)
  r.check:SetPoint("LEFT", r, "LEFT", 0, 0)
  r.check:SetTexture(ICONS)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(16, 16)
  r.icon:SetPoint("LEFT", r.check, "RIGHT", 4, 0)
  r.icon:SetTexture(ICONS)
  r.progress = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.progress:SetPoint("RIGHT", r, "RIGHT", 0, 0)
  r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.text:SetPoint("LEFT", r.icon, "RIGHT", 5, 0)
  r.text:SetPoint("RIGHT", r.progress, "LEFT", -4, 0)
  if r.text.SetJustifyH then r.text:SetJustifyH("LEFT") end
  if r.text.SetWordWrap then r.text:SetWordWrap(false) end
  local h = r:CreateTexture(nil, "HIGHLIGHT")
  h:SetAllPoints(r)
  h:SetColorTexture(1, 1, 1, 0.06)
  if r.RegisterForClicks then r:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  -- left: point the arrow there; right: skip the line's quest
  r:SetScript("OnClick", function(self, button)
    if button == "RightButton" then
      if self.line and self.line.quest then ns.SetSkip(self.line.quest, true) end
    else
      V.PointAt(self.line)
    end
  end)
  rows[i] = r
  return r
end

local function create()
  local C = V.COLORS
  frame = CreateFrame("Frame", "LvlsViewerFrame", UIParent)
  frame:SetSize(V.WIDTH, 120)
  frame:SetPoint("RIGHT", UIParent, "RIGHT", -40, 80)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:SetClampedToScreen(true)
  bg(frame, C.bg)
  -- title bar
  frame.bar = CreateFrame("Frame", nil, frame)
  frame.bar:SetHeight(22)
  frame.bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  frame.bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
  bg(frame.bar, C.bar)
  frame.bar:EnableMouse(true)
  frame.bar:RegisterForDrag("LeftButton")
  frame.bar:SetScript("OnDragStart", function() frame:StartMoving() end)
  frame.bar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
  frame.logo = frame.bar:CreateTexture(nil, "ARTWORK")
  frame.logo:SetTexture("Interface\\AddOns\\Lvls\\Media\\LvlsIcon")
  frame.logo:SetSize(18, 18)
  frame.logo:SetPoint("LEFT", frame.bar, "LEFT", 3, 0)
  frame.name = frame.bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.name:SetPoint("LEFT", frame.logo, "RIGHT", 4, 0)
  frame.name:SetText(ns.displayName)
  frame.name:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
  frame.close = button(frame.bar, "x", 20, function() V.Show(false) end)
  frame.close:SetPoint("RIGHT", frame.bar, "RIGHT", -2, 0)
  frame.nextBtn = button(frame.bar, ">", 20, function() V.Browse(1) end)
  frame.nextBtn:SetPoint("RIGHT", frame.close, "LEFT", -2, 0)
  frame.stepNo = frame.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.stepNo:SetPoint("RIGHT", frame.nextBtn, "LEFT", -4, 0)
  frame.prevBtn = button(frame.bar, "<", 20, function() V.Browse(-1) end)
  frame.prevBtn:SetPoint("RIGHT", frame.stepNo, "LEFT", -4, 0)
  frame.guides = button(frame.bar, "Guides", 44, function(b) V.GuideMenu(b) end)
  frame.guides:SetPoint("LEFT", frame.name, "RIGHT", 6, 0)
  -- step box
  frame.step = CreateFrame("Button", nil, frame)
  frame.step:SetPoint("TOPLEFT", frame.bar, "BOTTOMLEFT", 4, -4)
  frame.step:SetPoint("TOPRIGHT", frame.bar, "BOTTOMRIGHT", -4, -4)
  bg(frame.step, C.step)
  frame.accentBar = frame.step:CreateTexture(nil, "ARTWORK")
  frame.accentBar:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
  frame.accentBar:SetPoint("TOPLEFT", frame.step, "TOPLEFT", 0, 0)
  frame.accentBar:SetPoint("BOTTOMLEFT", frame.step, "BOTTOMLEFT", 0, 0)
  frame.accentBar:SetWidth(3)
  frame.header = frame.step:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.header:SetPoint("TOPLEFT", frame.step, "TOPLEFT", 10, -6)
  frame.header:SetPoint("RIGHT", frame.step, "RIGHT", -8, 0)
  if frame.header.SetJustifyH then frame.header:SetJustifyH("LEFT") end
  frame.header:SetTextColor(C.title[1], C.title[2], C.title[3])
  frame.sub = frame.step:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.sub:SetPoint("TOPLEFT", frame.header, "BOTTOMLEFT", 0, -2)
  frame.step:SetScript("OnClick", function() V.PointAt(nil) end)
  -- next step preview and experience bar
  frame.next = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.next:SetPoint("TOPLEFT", frame.step, "BOTTOMLEFT", 6, -5)
  frame.next:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
  if frame.next.SetJustifyH then frame.next:SetJustifyH("LEFT") end
  if frame.next.SetWordWrap then frame.next:SetWordWrap(false) end
  frame.xp = CreateFrame("Frame", nil, frame)
  frame.xp:SetHeight(12)
  frame.xp:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 4, 4)
  frame.xp:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
  bg(frame.xp, C.bar)
  frame.xp.fill = frame.xp:CreateTexture(nil, "ARTWORK")
  frame.xp.fill:SetPoint("TOPLEFT", frame.xp, "TOPLEFT", 0, 0)
  frame.xp.fill:SetPoint("BOTTOMLEFT", frame.xp, "BOTTOMLEFT", 0, 0)
  frame.xp.fill:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.85)
  frame.xp.text = frame.xp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.xp.text:SetPoint("CENTER", frame.xp, "CENTER", 0, 0)
end

-- The dungeon guide menu (Blizzard_Menu): one radio per dungeon with quests for
-- you, and a way back to the leveling route.
function V.GuideItems()
  local items = {}
  for _, d in ipairs(ns.GuideList()) do
    if d.open > 0 then
      local levels = d.minLevel and (" (%d-%d)"):format(d.minLevel, d.maxLevel or d.minLevel) or ""
      items[#items + 1] = { area = d.area, text = ("%s%s: %d quest%s"):format(d.name, levels, d.open, d.open == 1 and "" or "s") }
    end
  end
  return items
end

-- Class quest chains for the menu: { chain, text } ("Heirloom Weapon: 5 quests",
-- "Whirlwind Weapon: 6 quests (from level 30)").
function V.ClassItems()
  local items = {}
  local level = ns.char and ns.char.level or 1
  for _, c in ipairs(ns.ClassChains()) do
    local when = c.minLevel > level and (" (from level %d)"):format(c.minLevel) or ""
    items[#items + 1] = { chain = c.id, ready = #c.reach > 0, text = ("%s: %d quest%s%s"):format(c.name, c.open, c.open == 1 and "" or "s", when) }
  end
  return items
end

-- The Guides menu: Engine/Picker's tree, shown with Blizzard_Menu (submenus,
-- tooltips with each guide's quests).
function V.MenuTree()
  local ds = ns.ActiveDataset()
  if not ds or not ns.char then return {} end
  local tree = {}
  local function add(it) tree[#tree + 1] = it end
  local name = ns.guide and ns.guideName
  add({ kind = "title", text = name and ("Guide: " .. name) or "Following the leveling route" })
  add({ kind = "sub", text = "Dungeons", children = ns.Picker.Dungeons(ds, ns.char, ns.GuideList(), {
    info = function(area)
      local d = ns.DungeonInfo.Data(area)
      local e = ns.DungeonInfo.Entrance(area)
      return { raid = d and d.raid, size = d and d.size, map = e and e.map }
    end,
    current = function() return ns.cdb and ns.cdb.guide end,
    select = function(area) ns.SetGuide(area) end,
  }) })
  add({ kind = "sub", text = "Class quests", children = ns.Picker.Classes(ds, ns.char, ns.ClassChains(), {
    current = function() return ns.cdb and ns.cdb.classGuide end,
    select = function(id) ns.SetClassGuide(id) end,
  }) })
  local group = {}
  for _, p in ipairs(ns.SyncPeers()) do
    if p.version == "ok" and p.count > 0 then
      group[#group + 1] = { kind = "radio", key = "c" .. p.name,
        text = ("Catch up with %s: %s"):format(p.name, p.count == 1 and "1 quest" or (p.count .. " quests")),
        selected = function() return ns.sync and ns.sync.mode == "catchup" and ns.sync.with == p.name end,
        select = function() ns.SetSync(p.name, "catchup") end }
    end
    if ns.GroupSync.requests[p.name] or (ns.sync and ns.sync.mode == "follow" and ns.sync.with == p.name) then
      group[#group + 1] = { kind = "radio", key = "f" .. p.name, text = ("Follow %s (helping them catch up)"):format(p.name),
        selected = function() return ns.sync and ns.sync.mode == "follow" and ns.sync.with == p.name end,
        select = function() ns.SetSync(p.name, "follow") end }
    end
  end
  if #group > 0 then add({ kind = "sub", text = "Group", children = group }) end
  add({ kind = "divider" })
  add({ kind = "radio", key = 0, text = "Leveling route (no guide)",
    selected = function() return not (ns.sync or (ns.cdb and (ns.cdb.guide or ns.cdb.classGuide))) end,
    select = function() ns.SetGuide(nil) end })
  return tree
end

local function tooltip(el, it)
  if not (it.tip and el.SetTooltip) then return end
  el:SetTooltip(function(tt)
    local t = it.tip()
    if GameTooltip_SetTitle then GameTooltip_SetTitle(tt, t.title) else tt:SetText(t.title) end
    for _, l in ipairs(t.lines) do
      local c = l.color or { 1, 1, 1 }
      tt:AddLine(l.text, c[1], c[2], c[3], true)
    end
  end)
end

function V.RenderMenu(parent, items)
  for _, it in ipairs(items) do
    if it.kind == "title" then
      parent:CreateTitle(it.text)
    elseif it.kind == "divider" then
      parent:CreateDivider()
    elseif it.kind == "sub" then
      local sub = parent:CreateButton(it.text)
      V.RenderMenu(sub, it.children)
    elseif it.kind == "radio" then
      local r = parent:CreateRadio(it.text, it.selected, it.select, it.key)
      tooltip(r, it)
      if it.disabled and r.SetEnabled then r:SetEnabled(false) end
    end
  end
end

function V.GuideMenu(owner)
  if not (MenuUtil and MenuUtil.CreateContextMenu) then
    ns.commands.guide("")
    return
  end
  local tree = V.MenuTree()
  MenuUtil.CreateContextMenu(owner, function(_, root) V.RenderMenu(root, tree) end)
end

-- Point the arrow at a line's place (nil: the step itself).
function V.PointAt(line)
  local m = V.model
  if not m or not m.spot then return end
  local ds, char = ns.ActiveDataset(), ns.char
  local spot, title = m.spot, m.header
  if line and line.spot then
    spot, title = line.spot, line.text
  elseif line and line.index and ds and char then
    local q = ds.quests[line.quest]
    local spots = q and ns.Quests.ObjectiveSpots(ds, q, line.index)
    local near = spots and char.pos and ns.Geo.Nearest(ns.Game.geo, char.pos, spots)
    if near then spot, title = near, line.text end
  elseif line then
    title = line.text
  end
  ns.Arrow.SetTarget(spot, title, true)
end

function V.Browse(delta)
  local n = ns.steps and #ns.steps or 0
  if n == 0 then return end
  local i = (V.view or ns.stepIndex or 1) + delta
  if i < 1 then i = 1 end
  if i > n then i = n end
  V.view = (i ~= ns.stepIndex) and i or nil
  V.Render()
  local st = ns.steps[i]
  if V.model and V.model.spot then
    ns.Arrow.SetTarget(V.model.spot, V.model.header, V.view ~= nil, st and st.kind == "work" and st.lines or nil)
  end
end

function V.Render()
  if not frame then return end
  local ds, char = ns.ActiveDataset(), ns.char
  if not ds or not char then return end
  local m = V.Model(ds, char, ns.steps, ns.stepIndex, V.view, ns.planBase)
  V.model = m
  local C = V.COLORS
  frame.header:SetText(m.header or "")
  frame.sub:SetText(m.sub or "")
  frame.stepNo:SetText(m.stepNo and ("Step %d/%d"):format(m.stepNo, m.stepCount) or "")
  if V.view then frame.stepNo:SetTextColor(C.accent[1], C.accent[2], C.accent[3]) else frame.stepNo:SetTextColor(1, 1, 1) end
  for i, l in ipairs(m.lines) do
    local r = row(i)
    r.line = l.line
    r.check:SetTexCoord(V.IconCoords(l.check))
    r.icon:SetTexCoord(V.IconCoords(l.icon))
    r.text:SetText(l.text)
    r.text:SetTextColor(l.color[1], l.color[2], l.color[3])
    r.progress:SetText(l.progress or "")
    r:Show()
  end
  for i = #m.lines + 1, #rows do rows[i]:Hide() end
  local stepH = 44 + math.max(1, #m.lines) * V.LINE
  frame.step:SetHeight(stepH)
  local preview = m.next and ("Next: " .. m.next) or ""
  if m.backlog then preview = preview ~= "" and (preview .. "  ·  " .. m.backlog) or m.backlog end
  frame.next:SetText(preview)
  local xpMax = char.xpMax or 0
  local p = xpMax > 0 and math.min(1, (char.xp or 0) / xpMax) or 0
  frame.xp.fill:SetWidth(math.max(1, (V.WIDTH - 8) * p))
  frame.xp.text:SetText(("Level %d  %d / %d xp"):format(char.level or 0, char.xp or 0, xpMax))
  frame:SetHeight(22 + 4 + stepH + 20 + 18)
end

function V.Show(on)
  if not CreateFrame then return end
  if not frame then create() end
  if on == nil then on = not frame:IsShown() end
  if on then frame:Show() else frame:Hide() end
  if ns.cdb then ns.cdb.viewer = on end
  V.Render()
end

ns.Events.On("LVLS_LOADED", function()
  if ns.cdb and ns.cdb.viewer ~= false then V.Show(true) end
end)
ns.Events.On("LVLS_UPDATED", function() V.Render() end)

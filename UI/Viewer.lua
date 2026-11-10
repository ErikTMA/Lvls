-- The step viewer: a dark panel with the current step, one line per goal (icon,
-- check box, text, progress), the objectives you can do at the same time, a preview
-- of the next step and the experience bar. Prev / next browse the plan; clicking a
-- line points the arrow at it, right-clicking skips its quest (hover: a tooltip
-- says so, and that WoW Forever's quests may still lack prerequisites). The gear opens the
-- settings page.
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
  fly = 8, transit = 9, hearth = 10, enter = 11, path = 12, settings = 13 }
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
-- check, text, progress, color, line } }, next, offset }. offset: how far the step
-- browsed to is from the current one (nil on the current step).
function V.Model(ds, char, steps, current, view)
  local m = { lines = {} }
  local i = view or current
  local st = steps and i and steps[i]
  if not st then
    m.header = "No route from here"
    m.sub = "Accept a quest or move closer to quest givers"
    return m
  end
  if view and current and view ~= current then m.offset = view - current end
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
  -- a part that is done leaves the list: only what is still to do shows. A step that
  -- is all done (browsed to) shows its lines ticked off, not an empty box.
  local shown = {}
  for _, l in ipairs(st.lines) do
    if not l.done or (st.done and not l.also) then shown[#shown + 1] = l end
  end
  -- objectives stand under their quest's name ("[29] Razormaw Needling (Elite)"):
  -- right-click it to skip the quest; a quest only worked "also here" says so there
  local byQuest, order = {}, {}
  for _, l in ipairs(shown) do
    if l.index and l.quest and ds.quests[l.quest] then
      if not byQuest[l.quest] then byQuest[l.quest] = {}; order[#order + 1] = l.quest end
      table.insert(byQuest[l.quest], l)
    end
  end
  local function add(l, indent)
    if #m.lines >= V.MAX_LINES then return end
    local progress
    if l.need and l.need > 1 then progress = ("%d/%d"):format(l.have or 0, l.need) end
    m.lines[#m.lines + 1] = { icon = ns.Steps.ICON[l.kind] or "goto", check = l.done and "checkon" or "checkoff",
      text = (l.also and not indent and "Also: " or "") .. l.text, progress = progress, indent = indent,
      color = l.done and V.COLORS.done or l.also and V.COLORS.also or V.COLORS.text, line = l }
  end
  local headed = {}
  for _, l in ipairs(shown) do
    local group = l.index and byQuest[l.quest]
    if not group then add(l)
    elseif not headed[l.quest] and #m.lines < V.MAX_LINES then
      headed[l.quest] = true
      local also = true
      for _, g in ipairs(group) do also = also and g.also and true or false end
      m.lines[#m.lines + 1] = { quest = true, text = (also and "Also: " or "") .. V.QuestLabel(ds.quests[l.quest], char),
        color = also and V.COLORS.also or V.COLORS.title, line = { quest = l.quest, kind = "quest" } }
      for _, g in ipairs(group) do add(g, true) end
    end
  end
  local nxt = steps[i + 1]
  if nxt then m.next = nxt.title .. ": " .. (nxt.lines[1] and nxt.lines[1].text or "") end
  m.backlog = V.Backlog(ds, ns.backlog)
  m.train = V.Train(char and char.training)
  return m
end

-- "[29] Razormaw Needling (Elite)": a quest's name, its level and the quest log's tag.
function V.QuestLabel(q, char)
  return (q.l and ("[%d] "):format(q.l) or "") .. q.n .. ns.Steps.QuestTag(q) .. ns.ClassQuests.Tag(q, char)
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

-- On the experience bar: "3 to train" ("worth a trip" when it is), nil with nothing
-- you can pay for waiting at your trainer. /lvls train lists them.
function V.Train(t)
  if not t or t.count == 0 or (t.afford or 0) < ns.Training.PASS then return nil end
  return ("%d to train%s"):format(t.count, t.worth == "trip" and ", worth a trip" or "")
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
  r:SetScript("OnEnter", function(self)
    local tip = GameTooltip and V.LineTip(self.line)
    if not tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(tip[1][1], tip[1][2], tip[1][3], tip[1][4], true)
    for k = 2, #tip do GameTooltip:AddLine(tip[k][1], tip[k][2], tip[k][3], tip[k][4], true) end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  rows[i] = r
  return r
end

-- A quest line's tooltip: { {text, r, g, b}, ... } (nil: not a quest line). WoW
-- Forever's own quests (Prereqs.FOREVER_FROM and up) come without prerequisites
-- (Wowhead has none yet): the guide can send you to one the giver does not offer.
function V.LineTip(line)
  if not (line and line.quest) then return nil end
  local ds = ns.ActiveDataset()
  local q = ds and ds.quests[line.quest]
  local tip = { { q and q.n or line.text or ("Quest " .. line.quest), 1, 0.82, 0.25 } }
  if line.quest >= ns.Prereqs.FOREVER_FROM then
    tip[#tip + 1] = { "A WoW Forever quest: its data (prerequisites, chains) is still being gathered,"
      .. " so the guide may send you to it before it is offered.", 0.9, 0.9, 0.9 }
  end
  local o = q and line.index and q.obj and q.obj[line.index]
  if o and o.t == "item" and not o.from then
    local verb, names = ns.Steps.ItemSources(ds, o, line.quest, line.index)
    if names and #names > ns.Steps.SOURCE_NAMES then
      tip[#tip + 1] = { (verb == "Buy" and "Sold by: " or "From: ") .. table.concat(names, ", "), 0.9, 0.9, 0.9 }
    end
  end
  if q and q.kind == "group" then
    tip[#tip + 1] = { "An elite quest: made for a group.", 1, 0.5, 0.25 }
  end
  tip[#tip + 1] = { "Right-click: skip this quest (/lvls unskip takes it back)", 0.6, 0.8, 1 }
  return tip
end

-- Grow upwards: the viewer keeps its bottom edge, else its top edge.
function V.GrowUp() return ns.db and ns.db.settings.viewerGrowUp and true or false end

-- Pin the viewer by the edge the setting keeps, where it stands now (the setting
-- changed, or a position saved by the other edge).
function V.Anchor()
  if not frame then return end
  local up = V.GrowUp()
  local p = ns.db and ns.db.positions and ns.db.positions.viewer
  if type(p) ~= "table" or not p[1] then
    if not up then return end -- never moved: the default spot, growing downwards is fine
  elseif p[1] == (up and "BOTTOMLEFT" or "TOPLEFT") then
    return
  end
  ns.Style.SavePosition(frame, "viewer", up)
  ns.Style.Place(frame, "viewer", "RIGHT", "RIGHT", -40, 80)
end

local function create()
  local C = V.COLORS
  frame = CreateFrame("Frame", "LvlsViewerFrame", UIParent)
  frame:SetSize(V.WIDTH, 120)
  ns.Style.Place(frame, "viewer", "RIGHT", "RIGHT", -40, 80)
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
  ns.Style.Draggable(frame, "viewer", frame.bar, V.GrowUp)
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
  -- the settings page (/lvls settings): a gear
  frame.settings = button(frame.bar, "", 20, function() V.OpenSettings() end)
  frame.settings:SetPoint("RIGHT", frame.close, "LEFT", -2, 0)
  frame.settings.icon = frame.settings:CreateTexture(nil, "ARTWORK")
  frame.settings.icon:SetSize(14, 14)
  frame.settings.icon:SetPoint("CENTER", frame.settings, "CENTER", 0, 0)
  frame.settings.icon:SetTexture(ICONS)
  frame.settings.icon:SetTexCoord(V.IconCoords("settings"))
  frame.settings:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Settings")
    GameTooltip:Show()
  end)
  frame.settings:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  frame.nextBtn = button(frame.bar, ">", 20, function() V.Browse(1) end)
  frame.nextBtn:SetPoint("RIGHT", frame.settings, "LEFT", -2, 0)
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

-- The gear on the title bar: the settings page, as /lvls settings.
function V.OpenSettings() ns.Slash("settings") end

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
  -- a step browsed to while still open: browsing ends once it is done (Core/Init)
  V.viewOpen = V.view ~= nil and not (ns.steps[i] and ns.steps[i].done)
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
  local m = V.Model(ds, char, ns.steps, ns.stepIndex, V.view)
  V.model = m
  local C = V.COLORS
  frame.header:SetText(m.header or "")
  frame.sub:SetText(m.sub or "")
  frame.stepNo:SetText(m.offset and ("%+d"):format(m.offset) or "")
  frame.stepNo:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
  for i, l in ipairs(m.lines) do
    local r = row(i)
    r.line = l.line
    -- a quest's name: no box, no icon; its objectives under it, indented
    r.check:ClearAllPoints()
    r.check:SetPoint("LEFT", r, "LEFT", l.indent and 12 or 0, 0)
    r.text:ClearAllPoints()
    r.text:SetPoint("LEFT", l.quest and r or r.icon, l.quest and "LEFT" or "RIGHT", l.quest and 0 or 5, 0)
    r.text:SetPoint("RIGHT", r.progress, "LEFT", -4, 0)
    if l.quest then r.check:Hide(); r.icon:Hide() else r.check:Show(); r.icon:Show() end
    if l.check then r.check:SetTexCoord(V.IconCoords(l.check)) end
    if l.icon then r.icon:SetTexCoord(V.IconCoords(l.icon)) end
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
  frame.xp.text:SetText(("Level %d  %d / %d xp"):format(char.level or 0, char.xp or 0, xpMax)
    .. (m.train and ("  ·  " .. m.train) or ""))
  frame:SetHeight(22 + 4 + stepH + 20 + 18)
  V.Anchor()
end

function V.Show(on)
  if not CreateFrame then return end
  if not frame then create() end
  if on == nil then on = not frame:IsShown() end
  if on then frame:Show() else frame:Hide() end
  local was = V.Shown()
  if ns.cdb then ns.cdb.viewer = on end
  V.Render()
  if was ~= on then ns.Events.Fire("LVLS_GUIDE", on) end
end

-- The guide is shown: the viewer, and with it Lvls!'s arrow and route lines. Hidden
-- (the minimap button's right-click, the viewer's x), Lvls! lets go of the shared
-- arrow: it shows Profs!'s target if it has one, else it hides.
function V.Shown() return not ns.cdb or ns.cdb.viewer ~= false end

ns.Events.On("LVLS_LOADED", function()
  if ns.cdb and ns.cdb.viewer ~= false then V.Show(true) end
end)
ns.Events.On("LVLS_UPDATED", function() V.Render() end)

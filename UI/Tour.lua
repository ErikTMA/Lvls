-- The tour: the first time Lvls! runs, a box beside each part of it says what it does,
-- the things you would not guess included (right-click a quest to skip it, click a
-- note with a position). Next / Back step through it; "Skip the tour" ends it.
-- Which tips you have seen is kept for the account (LvlsDB.tour): a later version
-- with new tips shows only those. /lvls tour shows all of it again.
local _, ns = ...
local T = ns:NewModule("Tour")

T.WIDTH = 270
T.DELAY = 3 -- seconds after login: the viewer and the arrow are in place by then

local function viewer(part)
  return function()
    local f = ns.Viewer and ns.Viewer.frame
    if not f then return nil end
    if part then return f[part] end
    return f
  end
end
local function named(name) return function() return _G[name] end end

-- Every tip, in order. id: kept in LvlsDB.tour once seen (never reuse one); target:
-- the frame it points at (nil, or not shown: the box stands in the middle);
-- to: a second frame, the highlight runs from target's top left to its bottom right.
T.STEPS = {
  { id = "welcome", target = viewer(), title = "Welcome to Lvls!",
    text = "Lvls! plans a leveling route for your character and leads you through it, one step at a time. This is the step viewer: the step you are on, its goals and, under it, the next step and your experience.\n\nA few things here are not obvious. This tour shows them." },
  { id = "move", target = viewer("bar"), title = "Move the viewer",
    text = "Drag the title bar to put the viewer where you want it.\n\nSettings: \"Step viewer grows upwards\" keeps its bottom edge in place instead of its top." },
  { id = "lines", target = viewer("step"), title = "Click a line",
    text = "Click the step, or one of its lines: the arrow points there, at the nearest spot for that goal.\n\nHover a line for more about its quest." },
  { id = "skip", target = viewer("step"), title = "Right-click a quest to skip it",
    text = "Right-click a line of a quest you do not want: the route leaves it out from then on.\n\n/lvls unskip <quest> (or /lvls unskip all) takes it back. /lvls why <quest> says why a quest is in the route or not." },
  { id = "noteCoord", target = viewer("step"), title = "Notes with a position",
    text = "Blue lines are notes from players' comments on the quest. When one gives a position, like \"the entrance is at 76,75\", click it and the arrow points there." },
  { id = "browse", target = viewer("prevBtn"), to = viewer("nextBtn"), title = "Look ahead",
    text = "< and > show the steps before and after this one; the number says how far it is from the step you are on, and the arrow points at it.\n\nOnce the step you looked at is done, the viewer follows the route again." },
  { id = "guides", target = viewer("guides"), title = "Guides",
    text = "Instead of the leveling route: one zone, a dungeon (its quests and the chains leading to them, ending at its entrance) or a class quest chain.\n\nIn a group with others running Lvls!, catch up with them here." },
  { id = "replan", target = viewer("replan"), title = "Plan again",
    text = "Plans the route again from where you are now. With nothing changed it is the same route." },
  { id = "trash", target = viewer("trash"), title = "Abandon grey quests",
    text = "Abandons the grey quests in your log (no experience left in them). It asks first and names any items that would go with them. Shift-click: at once, when no items would.\n\nDim: none in your log." },
  { id = "settings", target = viewer("settings"), title = "Settings",
    text = "What Lvls! does for you: accepting and handing in quests, choosing rewards, putting on upgrades, the arrow, the map and minimap. Also /lvls settings." },
  { id = "hide", target = viewer("close"), title = "Hide the guide",
    text = "x hides the viewer, the arrow and the route lines. Right-click the minimap button, or type /lvls, to bring them back." },
  { id = "arrow", target = named("WaypointArrowFrame"), title = "The arrow",
    text = "Points at the next goal, and leads the way on foot round walls, buildings and cliffs (Settings: \"Turn-by-turn\"). Drag it to move it." },
  { id = "shift", title = "Hold Shift to do it yourself",
    text = "At an npc, Lvls! accepts the quests the route picks, hands in finished ones and takes the best reward.\n\nHold Shift while you talk to the npc and it leaves that to you." },
  { id = "itemBar", target = named("LvlsItemBar"), title = "Buttons for quest items",
    text = "When a quest needs an item used (or an item starts a quest), a button for it shows up. Drag a button to move the row.\n\nKeys for them: Key Bindings -> AddOns -> Lvls!." },
  { id = "maps", title = "The world map and the minimap",
    text = "The next steps are drawn as numbered waypoints joined by a line, starting where you stand.\n\nClick a quest pin on the world map: the arrow points there. Hover a waypoint on the minimap for its steps." },
  { id = "minimapButton", target = named("LvlsMinimapButton"), title = "The minimap button",
    text = "Left-click: settings. Right-click: hide or show the guide. Drag it round the minimap." },
  { id = "done", target = viewer(), title = "That is all",
    text = "/lvls help lists every command. /lvls tour shows this tour again.\n\nGood leveling!" },
}

-- The tips not seen yet, in order (seen: LvlsDB.tour, { [id] = true }).
function T.Pending(seen)
  local out = {}
  for _, st in ipairs(T.STEPS) do
    if not (seen and seen[st.id]) then out[#out + 1] = st end
  end
  return out
end

-- The step's frame, when there is one on screen.
function T.Target(st)
  local f = st and st.target and st.target()
  if f and f.IsVisible and f:IsVisible() == false then return nil end
  if f and f.IsShown and not f:IsShown() then return nil end
  return f
end

T.steps, T.index = nil, nil -- the tour on screen: its steps and the one shown
local box, glow

local function seen()
  if not ns.db then return {} end
  if type(ns.db.tour) ~= "table" then ns.db.tour = {} end
  return ns.db.tour
end

local function bg(f, c)
  local t = f:CreateTexture(nil, "BACKGROUND")
  t:SetAllPoints(f)
  t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
  return t
end

local function button(parent, label, w, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, 20)
  bg(b, ns.Viewer.COLORS.bar)
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.text:SetText(label)
  local h = b:CreateTexture(nil, "HIGHLIGHT")
  h:SetAllPoints(b)
  h:SetColorTexture(1, 1, 1, 0.12)
  b:SetScript("OnClick", onClick)
  return b
end

local function create()
  local C = ns.Viewer.COLORS
  box = CreateFrame("Frame", "LvlsTourFrame", UIParent)
  box:SetSize(T.WIDTH, 120)
  box:SetFrameStrata("DIALOG")
  box:SetClampedToScreen(true)
  box:EnableMouse(true)
  bg(box, { 0.067, 0.067, 0.067, 0.97 })
  box.accent = box:CreateTexture(nil, "ARTWORK")
  box.accent:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
  box.accent:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
  box.accent:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 0, 0)
  box.accent:SetWidth(3)
  box.count = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  box.count:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -8)
  box.count:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
  box.title = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  box.title:SetPoint("TOPLEFT", box.count, "BOTTOMLEFT", 0, -4)
  box.title:SetWidth(T.WIDTH - 22) -- a width of its own: it wraps (and measures) before the box is laid out
  if box.title.SetJustifyH then box.title:SetJustifyH("LEFT") end
  box.title:SetTextColor(C.title[1], C.title[2], C.title[3])
  box.body = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  box.body:SetPoint("TOPLEFT", box.title, "BOTTOMLEFT", 0, -6)
  box.body:SetWidth(T.WIDTH - 22)
  if box.body.SetJustifyH then box.body:SetJustifyH("LEFT") end
  if box.body.SetWordWrap then box.body:SetWordWrap(true) end
  if box.body.SetSpacing then box.body:SetSpacing(2) end
  box.body:SetTextColor(C.text[1], C.text[2], C.text[3])
  -- "Skip the tour": the viewer's own check box
  box.skip = CreateFrame("Button", nil, box)
  box.skip:SetSize(110, 20)
  box.skip:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 10, 8)
  box.skip.check = box.skip:CreateTexture(nil, "ARTWORK")
  box.skip.check:SetSize(14, 14)
  box.skip.check:SetPoint("LEFT", box.skip, "LEFT", 0, 0)
  box.skip.check:SetTexture("Interface\\AddOns\\Lvls\\Media\\Icons")
  box.skip.check:SetTexCoord(ns.Viewer.IconCoords("checkoff"))
  box.skip.text = box.skip:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  box.skip.text:SetPoint("LEFT", box.skip.check, "RIGHT", 4, 0)
  box.skip.text:SetText("Skip the tour")
  local sh = box.skip:CreateTexture(nil, "HIGHLIGHT")
  sh:SetAllPoints(box.skip)
  sh:SetColorTexture(1, 1, 1, 0.06)
  box.skip:SetScript("OnClick", function(self)
    self.check:SetTexCoord(ns.Viewer.IconCoords("checkon"))
    T.Stop(true)
  end)
  box.next = button(box, "Next", 52, function() T.Go(1) end)
  box.next:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -10, 8)
  box.back = button(box, "Back", 52, function() T.Go(-1) end)
  box.back:SetPoint("RIGHT", box.next, "LEFT", -6, 0)
  -- the highlight round what a tip is about: an orange frame that breathes; the
  -- mouse goes through it, so you can try the thing at once
  glow = CreateFrame("Frame", nil, UIParent)
  glow:SetFrameStrata("DIALOG")
  glow.edges = {}
  -- each edge: its two corners, and whether it is a side (else the top or bottom)
  for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT", true }, { "TOPRIGHT", "BOTTOMRIGHT", true } }) do
    local t = glow:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    t:SetPoint(e[1], glow, e[1], 0, 0)
    t:SetPoint(e[2], glow, e[2], 0, 0)
    if e[3] then t:SetWidth(2) else t:SetHeight(2) end
    glow.edges[#glow.edges + 1] = t
  end
  local clock = 0
  glow:SetScript("OnUpdate", function(self, elapsed)
    clock = clock + (elapsed or 0)
    self:SetAlpha(0.6 + 0.4 * math.abs(math.sin(clock * 2.5)))
  end)
  glow:Hide()
  box:Hide()
  T.box, T.glow = box, glow
end

-- The box beside the target: on its left when there is room (the viewer stands at
-- the right of the screen), else on its right; no target: the middle of the screen.
local function place(target, to)
  box:ClearAllPoints()
  glow:ClearAllPoints()
  if not target then
    box:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    glow:Hide()
    return
  end
  local pad = 4
  glow:SetPoint("TOPLEFT", target, "TOPLEFT", -pad, pad)
  glow:SetPoint("BOTTOMRIGHT", to or target, "BOTTOMRIGHT", pad, -pad)
  glow:Show()
  local left = target.GetLeft and target:GetLeft()
  local scale = (target.GetEffectiveScale and target:GetEffectiveScale() or 1) / (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1)
  if left and left * scale < T.WIDTH + 24 then
    box:SetPoint("TOPLEFT", to or target, "TOPRIGHT", 14, pad)
  else
    box:SetPoint("TOPRIGHT", target, "TOPLEFT", -14, pad)
  end
end

-- The box as tall as its text: the buttons under the last line, never over it. It
-- grows down from its top (beside a frame) or both ways (in the middle).
function T.Fit()
  if not box then return end
  local function h(fs, min) return math.max(min, (fs.GetStringHeight and fs:GetStringHeight()) or 0) end
  box:SetHeight(8 + h(box.count, 12) + 4 + h(box.title, 14) + 6 + h(box.body, 14) + 12 + 20 + 8)
end

function T.Render()
  if not (box and T.steps) then return end
  local st = T.steps[T.index]
  if not st then return end
  local n = #T.steps
  local whole = T.steps[1] == T.STEPS[1]
  box.count:SetText(("%s  %d / %d"):format(whole and "Lvls! tour" or "New in Lvls!", T.index, n))
  box.title:SetText(st.title)
  box.body:SetText(st.text)
  box.next.text:SetText(T.index == n and "Done" or "Next")
  if T.index > 1 then box.back:Show() else box.back:Hide() end
  box.skip.check:SetTexCoord(ns.Viewer.IconCoords("checkoff"))
  if T.index == n then box.skip:Hide() else box.skip:Show() end
  T.Fit()
  local target = T.Target(st)
  local to = target and st.to and st.to()
  place(target, to)
  box:Show()
  -- measured again once drawn: the client wraps the text only then
  if C_Timer and C_Timer.After then C_Timer.After(0, T.Fit) end
  seen()[st.id] = true -- seen once shown: a tour left halfway goes on from here next time
end

-- Next (1) or back (-1); past the last tip: the tour is over.
function T.Go(delta)
  if not T.steps then return end
  local i = T.index + delta
  if i < 1 then i = 1 end
  if i > #T.steps then return T.Stop(true) end
  T.index = i
  T.Render()
end

-- Start the tour. all: every tip (/lvls tour); else only those not seen yet.
-- Returns whether it started.
function T.Start(all)
  if not (CreateFrame and ns.db and ns.Viewer) then return false end
  local steps = all and T.STEPS or T.Pending(seen())
  if #steps == 0 then return false end
  if ns.Viewer.Show and not ns.Viewer.Shown() then ns.Viewer.Show(true) end
  if not box then create() end
  T.steps, T.index = steps, 1
  T.Render()
  return true
end

-- End it. done: every tip counts as seen (Skip the tour, Done).
function T.Stop(done)
  if done and T.steps then
    local s = seen()
    for _, st in ipairs(T.steps) do s[st.id] = true end
  end
  T.steps, T.index = nil, nil
  if box then box:Hide() end
  if glow then glow:Hide() end
end

function T.Active() return T.steps ~= nil end

-- At login, once the viewer is up: the tips not seen yet. Not with the guide hidden
-- (you hid it: the tour waits until you show it and log in again), nor in combat.
function T.Auto()
  if T.Active() or not ns.db then return end
  if ns.Viewer and not ns.Viewer.Shown() then return end
  if type(InCombatLockdown) == "function" and InCombatLockdown() then return end
  T.Start(false)
end

ns.Events.On("LVLS_LOADED", function()
  if C_Timer and C_Timer.After then C_Timer.After(T.DELAY, T.Auto) else T.Auto() end
end)
-- the viewer hidden: the tour goes with it (what it points at is gone)
ns.Events.On("LVLS_GUIDE", function(on) if not on and T.Active() then T.Stop(false) end end)

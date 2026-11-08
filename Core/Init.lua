-- Bootstrap: SavedVariables, state refresh, slash command. Loaded LAST (see Lvls.toc).
local _, ns = ...

local LEVELS = { error = 1, warn = 2, info = 3, debug = 4 }
ns.logLevel = LEVELS.info

function ns.Log(level, msg)
  if (LEVELS[level] or 3) > ns.logLevel then return end
  local line = "|cff3fbf3fLvls!|r " .. (level == "info" and "" or ("[" .. level .. "] ")) .. tostring(msg)
  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(line) else print(line) end
end

function ns.ActiveDataset()
  local flavor = (ns.Game and ns.Game.Flavor and ns.Game.Flavor()) or "forever"
  return ns.Registry.Get(flavor), flavor
end

ns.DEFAULT_SETTINGS = {
  worldMap = true, minimap = true, objectives = true, arrow = true, nativeArrow = false,
  showLow = true, showTrivial = false, showDungeon = false, showRepeatable = false,
  zoneFirst = true, debug = false,
}

function ns.InitDB(db)
  db = db or {}
  db.settings = db.settings or {}
  for k, v in pairs(ns.DEFAULT_SETTINGS) do
    if db.settings[k] == nil then db.settings[k] = v end
  end
  return db
end

function ns.InitCharDB(cdb)
  cdb = cdb or {}
  if cdb.viewer == nil then cdb.viewer = true end
  if type(cdb.skip) ~= "table" then cdb.skip = {} end
  return cdb
end

-- The plan: route -> steps. Kept while it holds, so the step number counts up as
-- you play; re-planned when it runs short, goes wrong (a quest became impossible or
-- was abandoned), or you took a quest it does not know about.
ns.REPLAN_BELOW = 5
local function plan(ds)
  local ctx = ns.travelCtx
  local ok, route = pcall(ns.Route.Plan, ds, ns.char, ns.Game.geo, {
    speed = ctx and ctx.speed or 7,
    travel = ctx and function(a, b) return ns.Travel.Time(a, b, ctx) end,
    zoneFirst = ns.db.settings.zoneFirst,
    skip = ns.cdb and ns.cdb.skip,
  })
  if not ok then ns.Log("debug", "route: " .. tostring(route)); route = {} end
  ns.route = route
  ns.steps = ns.Steps.Build(ds, ns.char, route, ns.Game.geo)
  ns.Steps.AddFlightPaths(ns.steps, ns.flyUnknown, ns.Game.geo)
  ns.Viewer.view = nil
end

-- The trip to the arrow's goal: legs, and where the arrow points now.
function ns.RefreshTravel()
  local goal = ns.Arrow.goal
  ns.trip = nil
  if goal and ns.char and ns.char.pos and ns.travelCtx then
    local ok, trip = pcall(ns.Travel.Plan, ns.char.pos, goal, ns.travelCtx)
    if ok then ns.trip = trip end
  end
  local spot, title = ns.Travel.NextSpot(ns.trip)
  if ns.trip and #ns.trip.legs > 1 then ns.Arrow.SetLeg(spot, title) else ns.Arrow.SetLeg(nil) end
end

local function unplanned(ds)
  local known = {}
  for _, st in ipairs(ns.steps or {}) do
    for _, l in ipairs(st.lines) do if l.quest then known[l.quest] = true end end
  end
  for qid in pairs(ns.char.active or {}) do
    local q = ds.quests[qid]
    if q and not known[qid] and (q.sn or q.so) and not q.inst
      and not (ns.cdb and ns.cdb.skip[qid]) then return true end
  end
  return false
end

function ns.Refresh(replan)
  local ds = ns.ActiveDataset()
  if not ds then return end
  ns.char = ns.Game.Character()
  ns.travelCtx = ns.TravelData.Context(ds, ns.char)
  local known, unknown = {}, {}
  if ns.char.pos then known, unknown = ns.TravelData.FlyNodes(ds, ns.char.pos.map, ns.char.faction) end
  ns.char.flyKnown = {}
  for _, f in ipairs(known) do ns.char.flyKnown[f.id] = true end
  ns.flyUnknown = unknown
  local s = ns.db.settings
  ns.nearby = ns.Quests.Nearby(ds, ns.char, ns.Game.geo, { limit = 10, maxDist = 3000,
    showLow = false, showTrivial = s.showTrivial, showDungeon = s.showDungeon,
    showRepeatable = s.showRepeatable })
  if replan or not ns.steps then plan(ds) end
  ns.stepIndex = ns.Steps.Refresh(ds, ns.char, ns.steps, ns.Game.geo)
  if not replan and (not ns.stepIndex or ns.Steps.Remaining(ns.steps, ns.stepIndex) < ns.REPLAN_BELOW
      or not ns.Steps.Valid(ds, ns.char, ns.steps, ns.stepIndex) or unplanned(ds)) then
    plan(ds)
    ns.stepIndex = ns.Steps.Refresh(ds, ns.char, ns.steps, ns.Game.geo)
  end
  -- the arrow follows the current step unless you pointed it somewhere yourself
  -- (a manual target stays until the step changes; browsing steps keeps its own)
  local st = ns.stepIndex and ns.steps[ns.stepIndex]
  if not st then
    ns.Arrow.SetTarget(nil)
  elseif not ns.Viewer.view and (st ~= ns.arrowStep or not ns.Arrow.goal) then
    ns.Arrow.SetTarget(st.spot, st.title, false)
  else
    ns.RefreshTravel()
  end
  ns.arrowStep = st
  ns.Events.Fire("LVLS_UPDATED")
end

ns.Events.On("LVLS_STATE", function()
  if ns.db then ns.Refresh() end
end)

local function onAddonLoaded()
  LvlsDB = ns.InitDB(LvlsDB)
  LvlsCharDB = ns.InitCharDB(LvlsCharDB)
  ns.db, ns.cdb = LvlsDB, LvlsCharDB
  if LvlsDB.settings.debug then ns.logLevel = LEVELS.debug end
end

local function onLogin()
  local ok, why = ns.QuestieDB.Connect()
  ns.questiedb = ok
  if not ok then
    ns.Log("warn", why .. ": prerequisites fall back to quest chains only. Install QuestieDB for exact quest availability.")
  end
  if not ns.ActiveDataset() then
    ns.Log("warn", "no quest data for this client (" .. tostring(ns.Game.Flavor()) .. ")")
  end
  ns.Events.Fire("LVLS_LOADED")
  ns.Refresh(true)
end

local commands = ns.commands

commands.show = function() ns.Viewer.Show() end

commands.nearby = function()
  local ds = ns.ActiveDataset()
  if not ds or not ns.nearby or #ns.nearby == 0 then ns.Log("info", "no available quests nearby"); return end
  for i = 1, math.min(8, #ns.nearby) do
    local n = ns.nearby[i]
    local q = ds.quests[n.quest]
    ns.Log("info", ("[%s] %s  %s"):format(q.l or "?", q.n, ns.Util.yards(n.dist)))
  end
end

commands.status = function()
  local ds, flavor = ns.ActiveDataset()
  ns.Log("info", ("flavor %s, dataset %s"):format(flavor,
    ds and ("%d quests (%s)"):format(ns.Util.count(ds.quests), tostring(ds.meta.generated)) or "MISSING"))
  ns.Log("info", "QuestieDB: " .. (ns.QuestieDB.Connected() and "connected" or "not available"))
  if ns.char and ns.char.pos then
    ns.Log("info", ("you are on %s at %.1f, %.1f"):format(ns.Game.MapName(ns.char.pos.map), ns.char.pos.x, ns.char.pos.y))
  end
end

commands.route = function()
  ns.Refresh(true)
  local ds = ns.ActiveDataset()
  if not ds or not ns.route or #ns.route == 0 then ns.Log("info", "no route from here"); return end
  for i = 1, math.min(10, #ns.route) do
    ns.Log("info", ("%d. %s"):format(i, ns.Route.Describe(ds, ns.route[i])))
  end
end

commands.next = function()
  local st = ns.stepIndex and ns.steps[ns.stepIndex]
  if st then ns.Arrow.SetTarget(st.spot, st.title, false) end
end

-- Skip a quest (the route leaves it out) or take it back.
function ns.SetSkip(qid, on)
  local ds = ns.ActiveDataset()
  local q = ds and ds.quests[qid]
  if not q or not ns.cdb then return end
  ns.cdb.skip[qid] = on and true or nil
  ns.Log("info", (on and "skipping %s (/lvls unskip to take it back)" or "no longer skipping %s"):format(q.n))
  ns.Refresh(true)
end

-- quests whose name contains `text` (or with that id) among `ids`
local function matching(ds, ids, text)
  local out, id, low = {}, tonumber(text), text:lower()
  for qid in pairs(ids) do
    local q = ds.quests[qid]
    if q and (qid == id or (not id and q.n:lower():find(low, 1, true))) then out[#out + 1] = qid end
  end
  table.sort(out)
  return out
end

commands.skip = function(arg)
  local ds = ns.ActiveDataset()
  if not ds then return end
  if arg == "" then
    local n = 0
    for qid in pairs(ns.cdb.skip) do
      local q = ds.quests[qid]
      ns.Log("info", ("skipped: %s (%d)"):format(q and q.n or "?", qid)); n = n + 1
    end
    if n == 0 then ns.Log("info", "nothing skipped. Right-click a line in the viewer, or /lvls skip <quest name>") end
    return
  end
  -- the quests of the current plan and the log first, then the whole dataset
  local ids = {}
  for _, st in ipairs(ns.steps or {}) do for _, l in ipairs(st.lines) do if l.quest then ids[l.quest] = true end end end
  for qid in pairs(ns.char and ns.char.active or {}) do ids[qid] = true end
  local found = matching(ds, ids, arg)
  if #found == 0 then found = matching(ds, ds.quests, arg) end
  if #found == 0 then ns.Log("info", "no quest matches " .. arg); return end
  for _, qid in ipairs(found) do ns.cdb.skip[qid] = true end
  ns.Log("info", ("skipping %d quest%s matching %s"):format(#found, #found == 1 and "" or "s", arg))
  ns.Refresh(true)
end

commands.unskip = function(arg)
  local ds = ns.ActiveDataset()
  if not ds then return end
  local found = arg:lower() == "all" and matching(ds, ns.cdb.skip, "") or matching(ds, ns.cdb.skip, arg)
  for _, qid in ipairs(found) do ns.cdb.skip[qid] = nil end
  ns.Log("info", ("no longer skipping %d quest%s"):format(#found, #found == 1 and "" or "s"))
  ns.Refresh(true)
end

local TOGGLES = { zone = "zoneFirst", map = "worldMap", minimap = "minimap", objectives = "objectives", arrow = "arrow", low = "showLow",
  trivial = "showTrivial", dungeon = "showDungeon", repeatable = "showRepeatable" }
for cmd, key in pairs(TOGGLES) do
  commands[cmd] = function()
    ns.db.settings[key] = not ns.db.settings[key]
    ns.Log("info", ("%s %s"):format(cmd, ns.db.settings[key] and "on" or "off"))
    ns.Refresh(key == "zoneFirst")
  end
end

commands.record = function(arg) ns.TravelData.Record(arg) end

commands.travel = function()
  local trip = ns.trip
  if not trip or #trip.legs == 0 then ns.Log("info", "no trip planned"); return end
  for i, l in ipairs(trip.legs) do
    ns.Log("info", ("%d. %s %s (%ds)"):format(i, l.mode, l.title or "", math.floor(l.secs or 0)))
  end
  ns.Log("info", ("%ds, walking would take %ds"):format(math.floor(trip.secs), math.floor(trip.walk)))
end

commands.debug = function()
  ns.db.settings.debug = not ns.db.settings.debug
  ns.logLevel = ns.db.settings.debug and LEVELS.debug or LEVELS.info
  ns.Log("info", "debug " .. (ns.db.settings.debug and "on" or "off"))
end

commands.help = function()
  ns.Log("info", "/lvls [show|route|next|skip [quest]|unskip <quest|all>|zone|nearby|travel|record|status|arrow|map|minimap|objectives|low|trivial|dungeon|repeatable|debug|help]")
end

local function slash(input)
  local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()
  local fn = commands[cmd ~= "" and cmd or "show"] or commands.help
  fn(rest)
end
ns.Slash = slash

if CreateFrame then
  local f = CreateFrame("Frame")
  f:RegisterEvent("ADDON_LOADED")
  f:RegisterEvent("PLAYER_LOGIN")
  f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ns.name then
      onAddonLoaded()
    elseif event == "PLAYER_LOGIN" then
      onLogin()
    end
  end)
  -- the nearest quests change as you walk
  local acc = 0
  f:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + (elapsed or 0)
    if acc >= 5 and ns.db and ns.char then acc = 0; ns.Refresh() end
  end)
  SLASH_LVLS1 = "/lvls"
  SlashCmdList.LVLS = slash
end

-- Minimap addon compartment (## AddonCompartmentFunc in Lvls.toc)
function Lvls_OnAddonCompartmentClick(_, button)
  if button == "RightButton" then commands.route() else commands.show() end
end

function Lvls_OnAddonCompartmentEnter(_, owner)
  if not GameTooltip then return end
  GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
  GameTooltip:SetText(ns.displayName)
  GameTooltip:AddLine("Left-click: show / hide the step viewer", 1, 1, 1)
  GameTooltip:AddLine("Right-click: plan the route from here", 1, 1, 1)
  GameTooltip:Show()
end

function Lvls_OnAddonCompartmentLeave()
  if GameTooltip then GameTooltip:Hide() end
end

ns.OnAddonLoaded, ns.OnLogin = onAddonLoaded, onLogin

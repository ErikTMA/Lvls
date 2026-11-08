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
  -- automation (Adapters/Automation.lua); hold Shift at an npc to pause it
  autoAccept = true, autoDeliver = true, autoReward = true, rewardGold = true,
  autoEquip = false, autoEquipBind = false, equipMaxQuality = 2, gearWeights = "auto",
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
  if type(cdb.spec) ~= "number" then cdb.spec = 0 end -- 0: from the talents
  return cdb
end

-- The plan: route -> steps. Kept while it holds, so the step number counts up as
-- you play; re-planned when it runs short, goes wrong (a quest became impossible or
-- was abandoned), or you took a quest it does not know about.
ns.REPLAN_BELOW = 5
-- The dungeon guide in use (LvlsCharDB.guide = its area): its quests, or nil.
local function guideSet(ds)
  local area = ns.cdb and ns.cdb.guide
  ns.guide, ns.guideName = nil, nil
  if not area then return nil end
  local g = ns.Dungeons.Set(ds, ns.char, area)
  local name = ns.DungeonInfo.Name(area)
  if #g.order == 0 or ns.Dungeons.Done(ds, ns.char, g) then
    ns.Log("info", ("%s guide: all done"):format(name))
    ns.cdb.guide = nil
    return nil
  end
  ns.guide, ns.guideName = g, name
  return g
end

local function plan(ds)
  local ctx = ns.travelCtx
  local g = guideSet(ds)
  local ok, route = pcall(ns.Route.Plan, ds, ns.char, ns.Game.geo, {
    speed = ctx and ctx.speed or 7,
    travel = ctx and function(a, b) return ns.Travel.Time(a, b, ctx) end,
    zoneFirst = ns.db.settings.zoneFirst,
    skip = ns.cdb and ns.cdb.skip,
    focus = g and g.set,
    dungeon = g and g.area,
  })
  if not ok then ns.Log("debug", "route: " .. tostring(route)); route = {} end
  ns.route = route
  ns.steps = ns.Steps.Build(ds, ns.char, route, ns.Game.geo)
  if g then
    -- the guide ends at the dungeon: go in and do its quests
    local planned = {}
    for _, a in ipairs(route) do if a.kind == "accept" then planned[a.quest] = true end end
    local st = ns.Dungeons.Step(ds, ns.char, g, ns.guideName, ns.DungeonInfo.Entrance(g.area), planned)
    if st then ns.steps[#ns.steps + 1] = st end
  end
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
  local known, handIn = {}, {}
  for _, st in ipairs(ns.steps or {}) do
    for _, l in ipairs(st.lines) do
      if l.quest then known[l.quest] = true end
      if l.kind == "turnin" then handIn[l.quest] = true end
    end
  end
  -- a guide quest finished (in the dungeon) that the plan does not hand in yet
  if ns.guide then
    for qid, entry in pairs(ns.char.active or {}) do
      if ns.guide.set[qid] and entry.complete and not handIn[qid] then return true end
    end
  end
  for qid in pairs(ns.char.active or {}) do
    local q = ds.quests[qid]
    local wanted = ns.guide and ns.guide.set[qid] or (not ns.guide and q and not q.inst)
    if q and not known[qid] and (q.sn or q.so) and wanted
      and not (ns.cdb and ns.cdb.skip[qid]) then return true end
  end
  return false
end

function ns.Refresh(replan)
  local ds = ns.ActiveDataset()
  if not ds then return end
  ns.char = ns.Game.Character()
  ns.DungeonInfo.Track(ns.char.pos)
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
  -- a guide is short on purpose: it is re-planned when it runs out, not when it is short
  local short = not ns.guide and ns.Steps.Remaining(ns.steps, ns.stepIndex or 1) < ns.REPLAN_BELOW
  if not replan and (not ns.stepIndex or short
      or not ns.Steps.Valid(ds, ns.char, ns.steps, ns.stepIndex) or unplanned(ds)) then
    plan(ds)
    ns.stepIndex = ns.Steps.Refresh(ds, ns.char, ns.steps, ns.Game.geo)
  end
  -- the arrow follows the current step unless you pointed it somewhere yourself
  -- (a manual target stays until the step changes; browsing steps keeps its own)
  local st = ns.stepIndex and ns.steps[ns.stepIndex]
  if st and st.kind == "dungeon" and ns.DungeonInfo.Inside(st.area) then
    ns.Arrow.SetTarget(nil) -- in there: nothing to point at
  elseif not st then
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

-- Dungeon guides ------------------------------------------------------------

-- Dungeons with quests for this character (Engine/Dungeons.List).
function ns.GuideList()
  local ds = ns.ActiveDataset()
  if not ds or not ns.char then return {} end
  return ns.Dungeons.List(ds, ns.char, ns.DungeonInfo.env)
end

-- Start a dungeon guide (area id) or stop it (nil).
function ns.SetGuide(area)
  local ds = ns.ActiveDataset()
  if not ds or not ns.cdb then return end
  ns.cdb.guide = area
  ns.Viewer.view = nil
  if area then
    local g = ns.Dungeons.Set(ds, ns.char, area)
    local lead = #g.order - #g.roots
    ns.Log("info", ("%s guide: %d quest%s there, %d leading up to them"):format(ns.DungeonInfo.Name(area),
      #g.roots, #g.roots == 1 and "" or "s", lead))
  else
    ns.Log("info", "guide stopped: back to the leveling route")
  end
  ns.Refresh(true)
end

-- /lvls guide [<dungeon> | off]: without a name, the list
commands.guide = function(arg)
  arg = (arg or ""):lower()
  if arg == "off" or arg == "stop" then ns.SetGuide(nil) return end
  local list = ns.GuideList()
  if arg == "" then
    if #list == 0 then ns.Log("info", "no dungeon has quests for you") return end
    for _, d in ipairs(list) do
      if d.open > 0 then
        ns.Log("info", ("%s%s (%s-%s): %d quest%s"):format(ns.cdb.guide == d.area and "> " or "", d.name,
          d.minLevel or "?", d.maxLevel or "?", d.open, d.open == 1 and "" or "s"))
      end
    end
    ns.Log("info", "/lvls guide <dungeon> starts a guide, /lvls guide off stops it")
    return
  end
  for _, d in ipairs(list) do
    if d.name:lower():find(arg, 1, true) then ns.SetGuide(d.area) return end
  end
  ns.Log("info", "no dungeon with quests for you matches " .. arg)
end

commands.settings = function()
  if not ns.Settings.Open() then ns.Log("info", "the settings page is not available: use /lvls help") end
end
commands.options, commands.config = commands.settings, commands.settings

-- /lvls spec [auto | <name> | 1-3]: the spec gear is judged for
commands.spec = function(arg)
  local token = ns.GearData.Class()
  local specs = ns.Gear.SPECS[token] or {}
  arg = (arg or ""):lower()
  if arg ~= "" then
    local pick
    if arg == "auto" or arg == "0" then pick = 0 end
    for i, sp in ipairs(specs) do
      if arg == tostring(i) or sp.name:lower():find(arg, 1, true) == 1 then pick = i end
    end
    if not pick then ns.Log("info", "no such spec: " .. arg); return end
    ns.cdb.spec = pick
  end
  local _, _, name, source = ns.GearData.Spec()
  local points = table.concat(ns.GearData.Points(), "/")
  ns.Log("info", ("spec: %s (%s; talent points %s)"):format(name or "?", source, points))
end

commands.gear = function()
  local _, label = ns.GearData.Scorer()
  ns.Log("info", "judging gear with " .. label)
end

local QUALITY = { white = 1, common = 1, green = 2, uncommon = 2, blue = 3, rare = 3, purple = 4, epic = 4 }
commands.quality = function(arg)
  local q = tonumber(arg) or QUALITY[(arg or ""):lower()]
  if q and q >= 0 and q <= 4 then ns.db.settings.equipMaxQuality = q end
  ns.Log("info", ("items that bind when equipped are put on up to quality %d"):format(ns.db.settings.equipMaxQuality))
end

commands.weights = function(arg)
  arg = (arg or ""):lower()
  if arg == "auto" or arg == "pawn" or arg == "lvls" then ns.db.settings.gearWeights = arg end
  ns.Log("info", "stat weights: " .. ns.db.settings.gearWeights)
end

local TOGGLES = { accept = "autoAccept", deliver = "autoDeliver", reward = "autoReward", gold = "rewardGold",
  equip = "autoEquip", bind = "autoEquipBind", zone = "zoneFirst", map = "worldMap", minimap = "minimap", objectives = "objectives", arrow = "arrow", low = "showLow",
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
  ns.Log("info", "/lvls [show|settings|guide [dungeon|off]|route|next|skip [quest]|unskip <quest|all>|zone|accept|deliver|reward|gold|equip|bind|quality <1-4>|weights <auto|pawn|lvls>|spec [auto|name]|gear|nearby|travel|record|status|arrow|map|minimap|objectives|low|trivial|dungeon|repeatable|debug|help]")
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

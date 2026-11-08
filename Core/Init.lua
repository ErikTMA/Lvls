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
  askClassQuests = true, -- ask to focus on a class quest chain when it becomes possible
  learnFights = true,    -- record fights (Adapters/FightLog) to learn what is hard for you
  suggestGrind = true,   -- grind steps when quests here wait only because they are too hard
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
  if type(cdb.classAsked) ~= "table" then cdb.classAsked = {} end -- class quest questions answered
  if type(cdb.fights) ~= "table" then cdb.fights = {} end -- Adapters/FightLog
  return cdb
end

-- The plan: route -> steps. Kept while it holds, so the step number counts up as
-- you play; re-planned when it runs short, goes wrong (a quest became impossible or
-- was abandoned), or you took a quest it does not know about.
ns.REPLAN_BELOW = 5
-- The dungeon guide in use (LvlsCharDB.guide = its area): its quests, or nil.
-- The guide in use, or nil: a dungeon (LvlsCharDB.guide = its area) or a class
-- quest chain (LvlsCharDB.classGuide = its id).
local function guideSet(ds)
  local area, chainId = ns.cdb and ns.cdb.guide, ns.cdb and ns.cdb.classGuide
  local before = ns.guideName -- the name it ran under (a chain's name moves on with its parts)
  ns.guide, ns.guideName = nil, nil
  local g, name
  if area then
    g, name = ns.Dungeons.Set(ds, ns.char, area), ns.DungeonInfo.Name(area)
  elseif chainId then
    local chain = ns.ClassQuests.Find(ds, ns.char, chainId)
    if chain then g, name = ns.ClassQuests.Set(ds, ns.char, chain), chain.name end
  else
    return nil
  end
  if not g or #g.order == 0 or ns.Dungeons.Done(ds, ns.char, g) then
    ns.Log("info", ("%s guide: all done"):format(before or name or "class quest"))
    ns.cdb.guide, ns.cdb.classGuide = nil, nil
    return nil
  end
  ns.guide, ns.guideName = g, name
  return g
end

-- What the fights say (Engine/Difficulty), kept until a fight is recorded.
local model
function ns.DifficultyModel()
  if not model and ns.cdb then model = ns.Difficulty.Model(ns.cdb.fights, ns.lastModel) end
  return model or ns.Difficulty.Model({})
end
ns.Events.On("LVLS_FIGHT", function()
  local before = model and model.above
  ns.lastModel = model
  model = nil
  local m = ns.DifficultyModel()
  if before and m.above ~= before then
    ns.Log("info", m.above < before
      and ("fights have been hard lately: quests up to %+d levels for now"):format(m.above)
      or ("fights are going well: quests up to %+d levels again"):format(m.above))
    ns.replanSoon = true
  end
end)

local function plan(ds)
  local ctx = ns.travelCtx
  local g = guideSet(ds)
  local dm = ns.DifficultyModel()
  local elite = dm.elite.n >= ns.Difficulty.MIN_FIGHTS and dm.elite.strain >= ns.Difficulty.HARD
  local ok, route = pcall(ns.Route.Plan, ds, ns.char, ns.Game.geo, {
    speed = ctx and ctx.speed or 7,
    travel = ctx and function(a, b) return ns.Travel.Time(a, b, ctx) end,
    zoneFirst = ns.db.settings.zoneFirst,
    skip = ns.cdb and ns.cdb.skip,
    focus = g and g.set,
    dungeon = g and g.area,
    -- what the fights say: how far above your level, how long a kill takes, grind steps
    maxAbove = dm.above,
    killSeconds = dm.killSecs,
    grind = ns.db.settings.suggestGrind,
    groupMargin = elite and 3 or 0,
  })
  if not ok then ns.Log("debug", "route: " .. tostring(route)); route = {} end
  ns.route = route
  ns.steps = ns.Steps.Build(ds, ns.char, route, ns.Game.geo)
  if g then
    local planned = {}
    for _, a in ipairs(route) do if a.kind == "accept" then planned[a.quest] = true end end
    local st
    if g.area then
      -- the guide ends at the dungeon: go in and do its quests
      st = ns.Dungeons.Step(ds, ns.char, g, ns.guideName, ns.DungeonInfo.Entrance(g.area), planned)
    else
      -- a class quest guide ends with what the route could not place
      st = ns.ClassQuests.Step(ds, ns.char, g, ns.guideName, planned)
    end
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

-- What the pins and the nearby list depend on, as a few numbers (no tables, no
-- strings: this runs every few seconds): level, completed quests, the quest log
-- (ids, complete, objective texts and states; an order-free sum), known flight
-- points. Settings changes mark it dirty (ns.Invalidate).
local function strHash(s, h)
  for i = 1, #s do h = (h * 31 + s:byte(i)) % 2147483647 end
  return h
end
local function stateOf(char)
  local done = 0
  for _ in pairs(char.completed or {}) do done = done + 1 end
  local active, sum = 0, 0
  for qid, e in pairs(char.active or {}) do
    active = active + 1
    local x = qid * 7 + (e.complete and 3 or 0)
    for _, o in ipairs(e.objectives or {}) do x = strHash(o.text or "", x) + (o.finished and 1 or 0) end
    sum = (sum + x) % 2147483647
  end
  local fly = 0
  for _ in pairs(char.flyKnown or {}) do fly = fly + 1 end
  return char.level or 0, done, active, sum, fly
end
local last = {}       -- the state the pins and the nearby list were made for
local nearbyAt = {}   -- where the nearby list was made
ns.NEARBY_MOVE = 0.5  -- map percent: moving this far makes a new nearby list

function ns.Invalidate() ns.dirty = true end

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
  local lv, done, active, sum, fly = stateOf(ns.char)
  local pos = ns.char.pos
  local map = pos and pos.map
  local changed = replan or ns.dirty or lv ~= last.lv or done ~= last.done or active ~= last.active
    or sum ~= last.sum or fly ~= last.fly
  local newMap = map ~= last.map
  ns.dirty = false
  last.lv, last.done, last.active, last.sum, last.fly, last.map = lv, done, active, sum, fly, map
  local moved = pos and (nearbyAt.map ~= pos.map or math.abs(pos.x - nearbyAt.x) > ns.NEARBY_MOVE
    or math.abs(pos.y - nearbyAt.y) > ns.NEARBY_MOVE)
  if changed or moved or not ns.nearby then
    ns.nearby = ns.Quests.Nearby(ds, ns.char, ns.Game.geo, { limit = 10, maxDist = 3000,
      showLow = false, showTrivial = s.showTrivial, showDungeon = s.showDungeon,
      showRepeatable = s.showRepeatable })
    if pos then nearbyAt.map, nearbyAt.x, nearbyAt.y = pos.map, pos.x, pos.y end
  end
  if ns.replanSoon then replan, ns.replanSoon = true, nil end
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
  elseif changed or moved then
    ns.RefreshTravel() -- the way there only changes when you move or something changed
  end
  ns.arrowStep = st
  ns.Events.Fire("LVLS_UPDATED")
  -- the pins only when what they show can have changed (they are the costly part)
  if changed or newMap then ns.Events.Fire("LVLS_PINS") end
  if changed and ns.AskClassQuest then ns.AskClassQuest(ds) end
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
  ns.cdb.guide, ns.cdb.classGuide = area, nil
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

-- Class quest chains of this character (Engine/ClassQuests.Chains).
function ns.ClassChains()
  local ds = ns.ActiveDataset()
  if not ds or not ns.char then return {} end
  return ns.ClassQuests.Chains(ds, ns.char)
end

-- Start a class quest guide (chain id) or stop it (nil).
function ns.SetClassGuide(id)
  local ds = ns.ActiveDataset()
  if not ds or not ns.cdb then return end
  ns.cdb.guide, ns.cdb.classGuide = nil, id
  ns.Viewer.view = nil
  local chain = id and ns.ClassQuests.Find(ds, ns.char, id)
  if chain and #chain.reach == 0 then
    ns.cdb.classGuide = nil
    ns.Log("info", ("%s: not before level %d"):format(chain.name, chain.minLevel))
    return
  end
  if chain then
    ns.cdb.classAsked[ns.ClassQuests.AskKey(chain)] = true
    local g = ns.ClassQuests.Set(ds, ns.char, chain)
    ns.Log("info", ("%s guide: %d class quest%s, %d leading up to them"):format(chain.name, #g.roots,
      #g.roots == 1 and "" or "s", #g.order - #g.roots))
  elseif not id then
    ns.Log("info", "guide stopped: back to the leveling route")
  end
  ns.Refresh(true)
end

-- "Later": remember the question, the chain stays in the Guides menu.
function ns.ClassLater(id)
  local ds = ns.ActiveDataset()
  local chain = ds and id and ns.ClassQuests.Find(ds, ns.char, id)
  if chain and ns.cdb then
    ns.cdb.classAsked[ns.ClassQuests.AskKey(chain)] = true
    ns.Log("info", ("%s: later. It is in the Guides menu and /lvls guide class"):format(chain.name))
  end
  ns.asking = nil
end

-- A class quest chain has just become possible: ask whether to focus on it (once
-- per part of a chain; not during a guide, a fight or a dungeon).
local function askClassQuest(ds)
  if ns.asking or ns.guide or not ns.db.settings.askClassQuests then return end
  if type(InCombatLockdown) == "function" and InCombatLockdown() then return end
  if ns.DungeonInfo.Instance() then return end
  local chain = ns.ClassQuests.ToAsk(ds, ns.char, ns.cdb.classAsked)
  if not chain then return end
  ns.asking = chain.id
  if ns.ClassPrompt and ns.ClassPrompt.Ask(chain) then return end
  -- no dialog: say it in the chat, and do not ask again
  ns.cdb.classAsked[ns.ClassQuests.AskKey(chain)] = true
  ns.asking = nil
  ns.Log("info", ("class quest available: %s (%d quests). /lvls guide class %s to focus on it"):format(
    chain.name, #chain.reach, chain.name:lower()))
end
ns.AskClassQuest = askClassQuest

-- /lvls guide [<dungeon or class quest> | class [<name>] | off]: without a name, the list
commands.guide = function(arg)
  arg = (arg or ""):lower()
  if arg == "off" or arg == "stop" then ns.SetGuide(nil) return end
  local classArg = arg:match("^class%s*(.*)$")
  if classArg then
    local chains = ns.ClassChains()
    if classArg == "" then
      if #chains == 0 then ns.Log("info", "no class quests left for you") return end
      for _, c in ipairs(chains) do
        local when = c.minLevel > (ns.char.level or 1) and (" (from level %d)"):format(c.minLevel) or ""
        ns.Log("info", ("%s%s: %d quest%s%s"):format(ns.cdb.classGuide == c.id and "> " or "", c.name, c.open,
          c.open == 1 and "" or "s", when))
      end
      ns.Log("info", "/lvls guide class <name> starts one")
      return
    end
    for _, c in ipairs(chains) do
      if c.name:lower():find(classArg, 1, true) then ns.SetClassGuide(c.id) return end
    end
    ns.Log("info", "no class quest chain matches " .. classArg)
    return
  end
  local list = ns.GuideList()
  if arg == "" then
    if #list == 0 then ns.Log("info", "no dungeon has quests for you") return end
    for _, d in ipairs(list) do
      if d.open > 0 then
        ns.Log("info", ("%s%s (%s-%s): %d quest%s"):format(ns.cdb.guide == d.area and "> " or "", d.name,
          d.minLevel or "?", d.maxLevel or "?", d.open, d.open == 1 and "" or "s"))
      end
    end
    ns.Log("info", "/lvls guide <dungeon> starts a guide, /lvls guide class lists class quests, /lvls guide off stops it")
    return
  end
  for _, d in ipairs(list) do
    if d.name:lower():find(arg, 1, true) then ns.SetGuide(d.area) return end
  end
  for _, c in ipairs(ns.ClassChains()) do
    if c.name:lower():find(arg, 1, true) then ns.SetClassGuide(c.id) return end
  end
  ns.Log("info", "no dungeon or class quest matches " .. arg)
end

-- /lvls fights [reset]: what Lvls! learned from your fights
commands.fights = function(arg)
  if arg == "reset" then
    ns.cdb.fights = {}
    ns.Events.Fire("LVLS_FIGHT", nil)
    ns.Log("info", "fight history cleared")
    return
  end
  local m = ns.DifficultyModel()
  local n = #ns.cdb.fights
  ns.Log("info", ("%d fights recorded (the last %d count)"):format(n, ns.Difficulty.RECENT))
  for d = -5, 5 do
    local b = m.diffs[d]
    if b then
      ns.Log("info", ("  mobs %+d levels: %d fights, strain %.2f, %d death%s%s"):format(d, b.n, b.strain, b.deaths,
        b.deaths == 1 and "" or "s", m.hard[d] and "  HARD" or ""))
    end
  end
  if m.elite.n > 0 then ns.Log("info", ("  elites and rares: %d fights, strain %.2f"):format(m.elite.n, m.elite.strain)) end
  ns.Log("info", ("quests up to %+d levels%s; a kill takes %s"):format(m.above,
    m.above < ns.Difficulty.DEFAULT_ABOVE and " (lowered by hard fights)" or "",
    m.killSecs and (math.floor(m.killSecs + 0.5) .. " s") or "about 15 s (not enough fights yet)"))
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
  equip = "autoEquip", bind = "autoEquipBind", zone = "zoneFirst", classask = "askClassQuests",
  grind = "suggestGrind", learn = "learnFights", map = "worldMap", minimap = "minimap", objectives = "objectives", arrow = "arrow", low = "showLow",
  trivial = "showTrivial", dungeon = "showDungeon", repeatable = "showRepeatable" }
for cmd, key in pairs(TOGGLES) do
  commands[cmd] = function()
    ns.db.settings[key] = not ns.db.settings[key]
    ns.Invalidate()
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
  ns.Log("info", "/lvls [show|settings|guide [dungeon|class [name]|off]|classask|fights [reset]|grind|learn|route|next|skip [quest]|unskip <quest|all>|zone|accept|deliver|reward|gold|equip|bind|quality <1-4>|weights <auto|pawn|lvls>|spec [auto|name]|gear|nearby|travel|record|status|arrow|map|minimap|objectives|low|trivial|dungeon|repeatable|debug|help]")
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

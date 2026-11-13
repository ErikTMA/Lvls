-- Talents, game side: read the character's talents, learn the next points of the
-- chosen build (Engine/Talents.lua), notice a reset. Forever's talents are a trait
-- tree (the ClassTalents UI; wow-ui-source branch forever, Camelot). APIs (forever
-- 1.60.1, feature detected):
--   C_ClassTalents.GetActiveConfigID() -> configID
--   C_Traits.GetNodeInfo(configID, nodeID) -> { ranksPurchased, maxRanks, canPurchaseRank, ... }
--   C_Traits.GetTreeCurrencyInfo(configID, treeID, excludeStaged) -> { { quantity, spent, maxQuantity } }
--   C_Traits.PurchaseRank(configID, nodeID) -> ok   (stages a point)
--   C_ClassTalents.CommitConfig(savedConfigID?) -> ok (Camelot's talent frame commits
--     this way, no loadout); C_Traits.CommitConfig(configID) the generic one
--   C_ClassTalents.CanEditTalents() -> canEdit, why; InCombatLockdown()
--   events TRAIT_CONFIG_UPDATED, TRAIT_TREE_CURRENCY_INFO_UPDATED, PLAYER_LEVEL_UP,
--     CONFIG_COMMIT_FAILED, PLAYER_REGEN_ENABLED
-- LvlsCharDB.talents = { spec = 1-3, build = name, off = true, spent = points last
-- seen }. LvlsDB.talentBuilds = { { name, class, spec, order } } (every character's).
-- When the game will not take a point from an addon by itself, the point waits for
-- a click (UI/Talents' "Learn" question: a click may do what an event may not).
local _, ns = ...
local TA = ns:NewModule("TalentsData")
local T = ns.Talents

local function has(t, k) return type(t) == "table" and type(t[k]) == "function" end
local plain = function(v) return ns.Util.plain(v) end

function TA.ClassId()
  local _, id = ns.GearData.Class()
  return id
end

function TA.Tree() return T.Tree(TA.ClassId()) end

function TA.ConfigID()
  if not has(C_ClassTalents, "GetActiveConfigID") then return nil end
  local ok, id = pcall(C_ClassTalents.GetActiveConfigID)
  return ok and plain(id) or nil
end

-- The character's talents: { ranks = { [nodeId] = n }, spent, unspent, config }, or
-- nil when the game does not tell (no trait API, no config yet).
function TA.State()
  local tree, config = TA.Tree(), TA.ConfigID()
  if not (tree and config and has(C_Traits, "GetNodeInfo")) then return nil end
  local ranks, spent = {}, 0
  for id in pairs(tree.byId) do
    local ok, info = pcall(C_Traits.GetNodeInfo, config, id)
    local r = ok and type(info) == "table" and plain(info.ranksPurchased) or 0
    r = tonumber(r) or 0
    if r > 0 then ranks[id] = r; spent = spent + r end
  end
  local unspent = 0
  if has(C_Traits, "GetTreeCurrencyInfo") then
    local ok, list = pcall(C_Traits.GetTreeCurrencyInfo, config, tree.tree, false)
    local c = ok and type(list) == "table" and list[1]
    unspent = c and tonumber(plain(c.quantity)) or 0
  end
  return { ranks = ranks, spent = spent, unspent = unspent, config = config }
end

-- Points per tree, for the spec (Adapters/Gear); nil when not known.
function TA.Points()
  local tree, st = TA.Tree(), TA.State()
  if not (tree and st) then return nil end
  return T.Points(tree, st.ranks)
end

-- The saved builds, every character's.
function TA.Builds()
  if not ns.db then return {} end
  ns.db.talentBuilds = ns.db.talentBuilds or {}
  return ns.db.talentBuilds
end

function TA.Choice()
  if not ns.cdb then return {} end
  if type(ns.cdb.talents) ~= "table" then ns.cdb.talents = {} end
  return ns.cdb.talents
end

-- The build in use: the saved one of that name for this class, or nil.
function TA.ActiveBuild()
  local c = TA.Choice()
  if c.off or not c.build then return nil end
  for _, b in ipairs(TA.Builds()) do
    if b.class == TA.ClassId() and b.name == c.build then return b end
  end
  return nil
end

-- Save a build (replacing the one of its name; original: the name it had when
-- editing started, so a renamed build replaces itself). The choice follows a rename.
function TA.Save(build, original)
  local list = TA.Builds()
  for i = #list, 1, -1 do
    local b = list[i]
    if b.class == build.class and (b.name == build.name or (original and b.name == original)) then table.remove(list, i) end
  end
  list[#list + 1] = build
  local c = TA.Choice()
  if original and c.build == original then c.build = build.name end
  return build
end

function TA.Delete(classId, name)
  local list = TA.Builds()
  for i, b in ipairs(list) do
    if b.class == classId and b.name == name then table.remove(list, i); break end
  end
  local c = TA.Choice()
  if c.build == name then c.build = nil end
end

-- The picker's answer: learn with this build (spec, name), or off.
function TA.Use(spec, name)
  local c = TA.Choice()
  c.off, c.spec, c.build = nil, spec, name
  TA.asked = true
  TA.Learn()
  if ns.Refresh then ns.Refresh() end
end

function TA.TurnOff()
  local c = TA.Choice()
  c.off, c.spec, c.build = true, nil, nil
  TA.asked = true
end

-- Talents reset (fewer points than last seen): the spec and build choice go, and
-- the picker asks again (unless turned off). Returns true when it was a reset.
function TA.CheckReset(st)
  local c = TA.Choice()
  local reset = T.WasReset(c.spent, st.spent)
  c.spent = st.spent
  if reset and not c.off and (c.spec or c.build) then
    c.spec, c.build = nil, nil
    TA.asked = nil
    ns.Log("info", "your talents were reset: choose a spec and build again (or turn it off)")
    return true
  end
  return false
end

local function canEdit()
  if type(InCombatLockdown) == "function" and InCombatLockdown() then return false, "in combat" end
  if has(C_ClassTalents, "CanEditTalents") then
    local ok, can, why = pcall(C_ClassTalents.CanEditTalents)
    if ok and can == false then return false, plain(why) or "the game says not now" end
  end
  return true
end

local function commit(config)
  if has(C_ClassTalents, "CommitConfig") then
    local ok, done = pcall(C_ClassTalents.CommitConfig)
    if ok and done then return true end
  end
  if has(C_Traits, "CommitConfig") then
    local ok, done = pcall(C_Traits.CommitConfig, config)
    return ok and done and true or false
  end
  return false
end

-- The points the build would spend now: { { id, name, rank, max } }, and why it
-- stops before the points run out (nil when it does not).
function TA.Pending(st, build)
  local tree = TA.Tree()
  if not (tree and st and build) then return {}, nil end
  local ranks, out, stop = {}, {}, nil
  for k, v in pairs(st.ranks) do ranks[k] = v end
  for _ = 1, st.unspent do
    local id = T.Next(build.order, ranks)
    if not id then break end
    local ok, why = T.CanAdd(tree, id, ranks)
    if not ok then stop = ("%s: %s"):format(tree.byId[id].node.n, why); break end
    ranks[id] = (ranks[id] or 0) + 1
    local n = tree.byId[id].node
    out[#out + 1] = { id = id, name = n.n, rank = ranks[id], max = n.m }
  end
  return out, stop
end

-- Spend what the build says, as far as the game takes it. byClick: from a button
-- (the click lets the game take it when an event may not). Returns the points
-- learned, or nil and why.
function TA.Learn(byClick)
  local build = TA.ActiveBuild()
  if not build then return nil, "no build chosen" end
  local st = TA.State()
  if not st then return nil, "talents not readable yet" end
  if st.unspent <= 0 then return 0 end
  local ok, why = canEdit()
  if not ok then TA.waiting = true; return nil, why end
  if TA.clickOnly and not byClick then
    local plan = TA.Pending(st, build)
    if #plan > 0 then TA.needClick = plan; ns.Events.Fire("LVLS_TALENTS_ASK", plan) end
    return nil, "waits for a click"
  end
  TA.waiting = nil
  local plan, stop = TA.Pending(st, build)
  local learned = {}
  for _, p in ipairs(plan) do
    local info = has(C_Traits, "GetNodeInfo") and select(2, pcall(C_Traits.GetNodeInfo, st.config, p.id))
    if type(info) == "table" and info.canPurchaseRank == false then
      stop = ("%s: the game will not take a point there yet"):format(p.name); break
    end
    local bought = has(C_Traits, "PurchaseRank") and select(2, pcall(C_Traits.PurchaseRank, st.config, p.id))
    if not bought then break end
    learned[#learned + 1] = p
  end
  if #learned == 0 then
    if #plan > 0 and not byClick then
      -- not taken from an event: ask for a click
      TA.needClick = plan
      ns.Events.Fire("LVLS_TALENTS_ASK", plan)
      return nil, "waits for a click"
    end
    if stop and stop ~= TA.lastStop then ns.Log("info", "talent build stops at " .. stop) end
    TA.lastStop = stop
    return nil, stop or "nothing to learn"
  end
  if not commit(st.config) then
    if has(C_Traits, "RollbackConfig") then pcall(C_Traits.RollbackConfig, st.config) end
    if not byClick then
      TA.needClick = plan
      ns.Events.Fire("LVLS_TALENTS_ASK", plan)
      return nil, "waits for a click"
    end
    ns.Log("info", "the game did not take the talents")
    return nil, "commit failed"
  end
  TA.needClick = nil
  local names = {}
  for _, p in ipairs(learned) do names[#names + 1] = ("%s %d/%d"):format(p.name, p.rank, p.max) end
  ns.Log("info", "learned " .. table.concat(names, ", "))
  if stop and stop ~= TA.lastStop then ns.Log("info", "talent build stops at " .. stop) end
  TA.lastStop = stop
  -- the points seen (Choice().spent) stay what the game said: a commit the game
  -- turns down afterwards must not look like a reset
  return #learned
end

-- After any talent change: a reset clears the choice; points to spend are spent,
-- or the picker asks when nothing is chosen yet.
function TA.Update()
  if not ns.cdb then return end
  local st = TA.State()
  if not st then return end
  TA.CheckReset(st)
  local c = TA.Choice()
  if c.off then return end
  if TA.ActiveBuild() then
    if st.unspent > 0 then TA.Learn() end
  elseif st.unspent > 0 and not TA.asked then
    TA.asked = true
    ns.Events.Fire("LVLS_TALENTS_PICK")
  end
end

local EVENTS = { "TRAIT_CONFIG_UPDATED", "TRAIT_TREE_CURRENCY_INFO_UPDATED", "PLAYER_LEVEL_UP",
  "PLAYER_REGEN_ENABLED", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "CONFIG_COMMIT_FAILED" }

-- The game turned a commit down after taking it: from now on (this session) points
-- wait for a click, so it does not try again on every event.
function TA.CommitFailed()
  TA.clickOnly = true
  local st, build = TA.State(), TA.ActiveBuild()
  local plan = TA.Pending(st, build)
  if #plan > 0 then TA.needClick = plan; ns.Events.Fire("LVLS_TALENTS_ASK", plan) end
end

if CreateFrame then
  local f = CreateFrame("Frame")
  for _, e in ipairs(EVENTS) do pcall(f.RegisterEvent, f, e) end
  f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" and not TA.waiting then return end
    local ok, err = pcall(event == "CONFIG_COMMIT_FAILED" and TA.CommitFailed or TA.Update)
    if not ok then ns.Log("debug", "talents: " .. tostring(err)) end
  end)
end
ns.Events.On("LVLS_LOADED", function()
  local ok, err = pcall(TA.Update)
  if not ok then ns.Log("debug", "talents: " .. tostring(err)) end
end)

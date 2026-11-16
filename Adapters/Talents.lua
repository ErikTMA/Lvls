-- Talents, game side: read the character's talents, say which points of the chosen
-- build (Engine/Talents.lua) come next, notice a reset. Forever's talents are a trait
-- tree (the ClassTalents UI; wow-ui-source branch forever, Camelot). APIs (forever
-- 1.60.1, feature detected), all read-only:
--   C_ClassTalents.GetActiveConfigID() -> configID
--   C_Traits.GetNodeInfo(configID, nodeID) -> { ranksPurchased, maxRanks, canPurchaseRank, ... }
--   C_Traits.GetTreeCurrencyInfo(configID, treeID, excludeStaged) -> { { quantity, spent, maxQuantity } }
--   C_Traits.ConfigHasStagedChanges(configID) -> points clicked but not applied yet
--   events TRAIT_CONFIG_UPDATED, TRAIT_TREE_CURRENCY_INFO_UPDATED, PLAYER_LEVEL_UP
-- Lvls! never spends a point itself. Committing talents from addon code taints the
-- action bars' Edit Mode layout for the rest of the session (ErikTMA/Lvls#2: blocked
-- actions in combat). The player clicks the points in the game's talent window, which
-- Lvls! marks (UI/TalentsGame); LVLS_TALENTS_DUE(plan, stop) says what is next.
-- LvlsCharDB.talents = { spec = 1-3, build = name, off = true, spent = points last
-- seen }. LvlsDB.talentBuilds = { { name, class, spec, order } } (every character's);
-- Lvls!'s own builds ("Lvls! Arms", Data/forever/TalentBuilds.lua) come with them.
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

-- Lvls!'s own builds for this class (Data/forever/TalentBuilds.lua).
function TA.Shipped() return (T.Shipped(TA.ClassId())) end

-- A build of this class by name: Lvls!'s own or a saved one; nil when none.
function TA.Find(name)
  if not name then return nil end
  local id = TA.ClassId()
  for _, b in ipairs(TA.Shipped()) do if b.name == name then return b end end
  for _, b in ipairs(TA.Builds()) do
    if b.class == id and b.name == name then return b end
  end
  return nil
end

-- The build in use, or nil.
function TA.ActiveBuild()
  local c = TA.Choice()
  if c.off or not c.build then return nil end
  return TA.Find(c.build)
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
  if T.Reserved(name) then return end -- Lvls!'s own stay
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
  TA.dueKey = nil -- say it again for the new build
  TA.Due()
  if ns.Refresh then ns.Refresh() end
end

function TA.TurnOff()
  local c = TA.Choice()
  c.off, c.spec, c.build = true, nil, nil
  TA.asked = true
  TA.Due(true)
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

-- Points clicked in the game's window but not applied yet: the spent count is not
-- the character's then (an undone click must not look like a reset).
local function staged(st)
  if not has(C_Traits, "ConfigHasStagedChanges") then return false end
  local ok, yes = pcall(C_Traits.ConfigHasStagedChanges, st.config)
  return ok and plain(yes) == true
end

local function key(plan, stop)
  local ids = {}
  for i, p in ipairs(plan) do ids[i] = p.id .. ":" .. p.rank end
  return table.concat(ids, ",") .. "|" .. tostring(stop)
end

-- The points the chosen build wants now ({} when none, or nothing chosen), and why
-- it stops before the points run out. Fires LVLS_TALENTS_DUE when that changes, and
-- says it in chat once (quiet: only the marks follow, as while clicking them).
function TA.Due(quiet)
  local st, build = TA.State(), TA.ActiveBuild()
  local plan, stop = {}, nil
  if st and build and st.unspent > 0 and not TA.Choice().off then plan, stop = TA.Pending(st, build) end
  local k = key(plan, stop)
  if k ~= TA.dueKey then
    TA.dueKey, TA.due = k, plan
    if not quiet and #plan > 0 then
      ns.Log("info", ("talents to learn: %s. Open your talents (N): Lvls! marks them"):format(TA.PlanText(plan)))
    end
    if not quiet and #plan == 0 and stop and stop ~= TA.lastStop then ns.Log("info", "talent build stops at " .. stop) end
    TA.lastStop = stop
    ns.Events.Fire("LVLS_TALENTS_DUE", plan, stop)
  end
  return plan, stop
end

-- "Cruelty 2/5, Unbridled Wrath 1/5"
function TA.PlanText(plan)
  local names = {}
  for _, p in ipairs(plan or {}) do names[#names + 1] = ("%s %d/%d"):format(p.name, p.rank, p.max) end
  return table.concat(names, ", ")
end

-- After any talent change: a reset clears the choice; the points to spend are
-- marked, or the picker asks when nothing is chosen yet.
function TA.Update()
  if not ns.cdb then return end
  local st = TA.State()
  if not st then return end
  if not staged(st) then TA.CheckReset(st) end
  local c = TA.Choice()
  if c.off then TA.Due(true); return end
  if TA.ActiveBuild() then
    TA.Due()
  elseif st.unspent > 0 and not TA.asked then
    TA.asked = true
    ns.Events.Fire("LVLS_TALENTS_PICK")
  end
end

local EVENTS = { "TRAIT_CONFIG_UPDATED", "TRAIT_TREE_CURRENCY_INFO_UPDATED", "PLAYER_LEVEL_UP",
  "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED" }

if CreateFrame then
  local f = CreateFrame("Frame")
  for _, e in ipairs(EVENTS) do pcall(f.RegisterEvent, f, e) end
  f:SetScript("OnEvent", function()
    local ok, err = pcall(TA.Update)
    if not ok then ns.Log("debug", "talents: " .. tostring(err)) end
  end)
end
ns.Events.On("LVLS_LOADED", function()
  local ok, err = pcall(TA.Update)
  if not ok then ns.Log("debug", "talents: " .. tostring(err)) end
end)

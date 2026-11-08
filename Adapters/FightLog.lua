-- Records the character's fights for Engine/Difficulty: how long, against what
-- (level, elite / rare), how many, the health before and after, deaths, and the
-- rest needed afterwards. Solo fights only (a group changes everything).
--
-- forever 1.60.1 (wow-ui-source branch forever): the combat log cannot be read by
-- addons (no CombatLogGetCurrentEventInfo), and UnitHealth / UnitHealthMax / UnitGUID
-- can return secret values, which must not be compared or used in arithmetic
-- (issecretvalue(v) tells). So: fight start / end from PLAYER_REGEN_DISABLED /
-- PLAYER_REGEN_ENABLED, targets from PLAYER_TARGET_CHANGED (UnitLevel,
-- UnitClassification, UnitCanAttack, UnitIsPlayer), health read only when not
-- secret (out of combat it is not), deaths from PLAYER_DEAD.
local _, ns = ...
local FL = ns:NewModule("FightLog")

FL.KEEP = 300      -- fights kept per character
FL.MIN_SECS = 2    -- shorter "fights" (a tag, a dot ticking) are not fights
FL.REST_MAX = 180  -- seconds of rest tracked at most
FL.REST_DONE = 0.9 -- health fraction that ends the rest

local function readable(v)
  if v == nil then return false end
  if type(issecretvalue) == "function" and issecretvalue(v) then return false end
  return type(v) == "number"
end

function FL.Health()
  if type(UnitHealth) ~= "function" or type(UnitHealthMax) ~= "function" then return nil end
  local h, m = UnitHealth("player"), UnitHealthMax("player")
  if readable(h) and readable(m) and m > 0 then return h / m end
  return nil
end

local function now() return GetTime and GetTime() or 0 end

local fight         -- the fight going on
local resting       -- { fight, since } waiting for the health to come back
local lastHealth    -- the last health read outside combat
local last, lastAt  -- the fight recorded last, and when (a death can come after it)

-- The hostile target, as { key, level, cls } or nil.
local function target()
  if type(UnitExists) ~= "function" or not UnitExists("target") then return nil end
  if type(UnitCanAttack) == "function" and not UnitCanAttack("player", "target") then return nil end
  if type(UnitIsPlayer) == "function" and UnitIsPlayer("target") then return nil end
  local level = UnitLevel and UnitLevel("target")
  if not readable(level) then return nil end
  if level < 0 then level = (UnitLevel("player") or 1) + 10 end -- "??"
  local cls = UnitClassification and UnitClassification("target") or "normal"
  local name = UnitName and ns.Util.plain(UnitName("target")) or "?"
  if type(name) ~= "string" then name = "?" end -- secret: one key for every such mob
  return { key = name .. ":" .. level, level = level, cls = cls }
end

local function addTarget(t)
  if not fight or not t or fight.seen[t.key] then return end
  fight.seen[t.key] = true
  fight.n = fight.n + 1
  -- the fight is as hard as its hardest mob
  if not fight.ml or t.level > fight.ml then fight.ml = t.level end
  if t.cls ~= "normal" and t.cls ~= "minus" and t.cls ~= "trivial" then fight.cls = t.cls end
end

function FL.Start()
  if type(IsInGroup) == "function" and IsInGroup() then fight = nil return end
  fight = { t0 = now(), lvl = UnitLevel and UnitLevel("player") or 1, n = 0, seen = {}, cls = "normal",
    hp0 = FL.Health() or lastHealth }
  resting = nil
  addTarget(target())
end

function FL.TargetChanged()
  if fight then addTarget(target()) end
end

function FL.Died()
  if fight then
    fight.died = true
  elseif last and now() - lastAt <= 3 then
    last.died, last.rest = true, nil -- the fight ended with the death
  end
  resting = nil
end

function FL.Stop()
  local f = fight
  fight = nil
  if not f or not f.ml or not ns.cdb then return nil end
  local dur = now() - f.t0
  if dur < FL.MIN_SECS and not f.died then return nil end
  local hp1 = FL.Health()
  local rec = { t = time and time() or 0, lvl = f.lvl, ml = f.ml, cls = f.cls, n = f.n, dur = math.floor(dur * 10 + 0.5) / 10,
    hp0 = f.hp0, hp1 = hp1, died = f.died or nil }
  if hp1 and hp1 >= FL.REST_DONE then rec.rest = 0 end
  local list = ns.cdb.fights
  list[#list + 1] = rec
  while #list > FL.KEEP do table.remove(list, 1) end
  if not rec.rest and not rec.died then resting = { fight = rec, since = now() } end
  last, lastAt = rec, now()
  ns.Events.Fire("LVLS_FIGHT", rec)
  return rec
end

-- About once a second: the rest after a fight ends when health is back up, a new
-- fight starts, or it took too long.
function FL.Tick()
  local h = FL.Health()
  if h and not fight then lastHealth = h end
  if not resting then return end
  local elapsed = now() - resting.since
  if fight then
    resting.fight.rest = math.floor(elapsed + 0.5) -- interrupted: at least this much
    resting = nil
  elseif (h and h >= FL.REST_DONE) or elapsed >= FL.REST_MAX then
    resting.fight.rest = math.floor(math.min(elapsed, FL.REST_MAX) + 0.5)
    resting = nil
    ns.Events.Fire("LVLS_FIGHT", nil)
  end
end

function FL.Busy() return fight ~= nil end

if CreateFrame then
  local f = CreateFrame("Frame")
  local handlers = {
    PLAYER_REGEN_DISABLED = FL.Start,
    PLAYER_REGEN_ENABLED = FL.Stop,
    PLAYER_TARGET_CHANGED = FL.TargetChanged,
    PLAYER_DEAD = FL.Died,
  }
  for e in pairs(handlers) do f:RegisterEvent(e) end
  f:SetScript("OnEvent", function(_, event)
    if not (ns.db and ns.db.settings.learnFights) then return end
    local ok, err = pcall(handlers[event])
    if not ok then ns.Log("debug", event .. ": " .. tostring(err)) end
  end)
  local acc = 0
  f:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + (elapsed or 0)
    if acc >= 1 then acc = 0; if ns.db and ns.db.settings.learnFights then FL.Tick() end end
  end)
end

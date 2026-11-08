-- How hard fights are for this character, learned from the fights it had (see
-- Adapters/FightLog.lua), and what the route makes of it. Pure.
--
-- A fight: { lvl = player level, ml = mob level, cls = "normal" | "elite" | "rare" |
--   "rareelite" | "worldboss", n = hostile targets, dur = seconds, hp0 / hp1 = health
--   at the start / end (0..1, nil when unknown), died, rest = seconds to get back
--   above 90% health afterwards (eating, regen; nil while unknown) }
--
-- Strain of a fight, 0 (easy) .. 1 (died): health lost and the rest needed after it.
-- Per level difference (mob level - your level) the recent fights against normal
-- mobs are averaged; a difference is HARD with at least MIN_FIGHTS fights there and
-- an average strain of HARD or more, and stays hard until it drops under EASY
-- (no flapping on one good or bad fight). Several mobs at once count half.
--
-- Comfort: how far above your level quests can be. Default DEFAULT_ABOVE (the
-- route's own); when difference d is hard, quests above your level + d - 1 wait
-- ("level 12 quests are hard at 12: level 13 quests when you are 14").
local _, ns = ...
local D = ns:NewModule("Difficulty")

D.MIN_FIGHTS = 8      -- fights at a level difference before it decides anything
D.HARD = 0.55         -- average strain from which a difference is hard
D.EASY = 0.45         -- ...and under which it is easy again
D.RECENT = 150        -- only the last fights count (gear and talents change)
D.DEFAULT_ABOVE = 3   -- the route's quest level margin without evidence
D.REST_FULL = 60      -- seconds of rest that count as a fully draining fight
D.MULTI_WEIGHT = 0.5  -- weight of a fight against several mobs

local function clamp(x, a, b) return math.max(a, math.min(b, x)) end

function D.Strain(f)
  if f.died then return 1 end
  local lost = 0
  if f.hp0 and f.hp1 then lost = clamp(f.hp0 - f.hp1, 0, 1) elseif f.hp1 then lost = clamp(1 - f.hp1, 0, 1) end
  local rest = f.rest and clamp(f.rest / D.REST_FULL, 0, 1) or lost
  return clamp(0.6 * lost + 0.4 * rest, 0, 1)
end

local function normal(f) return f.cls == nil or f.cls == "normal" or f.cls == "minus" or f.cls == "trivial" end

-- The model from the fights (oldest first). `previous` (the last model) gives the
-- hysteresis: a hard difference stays hard until it is easy.
-- Returns { diffs = { [d] = { n, strain, deaths } }, hard = { [d] = true },
--   above = quest level margin, killSecs = typical seconds per normal mob around
--   your level (nil without data), elite = { n, strain } }.
function D.Model(fights, previous)
  local m = { diffs = {}, hard = {}, elite = { n = 0, strain = 0 } }
  local from = math.max(1, #fights - D.RECENT + 1)
  local durs = {}
  for i = from, #fights do
    local f = fights[i]
    if f.ml and f.lvl then
      local s = D.Strain(f)
      if normal(f) then
        local d = clamp(f.ml - f.lvl, -5, 5)
        local b = m.diffs[d]
        if not b then b = { n = 0, w = 0, sum = 0, deaths = 0 }; m.diffs[d] = b end
        local w = (f.n or 1) > 1 and D.MULTI_WEIGHT or 1
        b.n = b.n + 1
        b.w = b.w + w
        b.sum = b.sum + s * w
        if f.died then b.deaths = b.deaths + 1 end
        if (f.n or 1) <= 1 and d >= -1 and d <= 1 and f.dur and f.dur > 0 and not f.died then
          durs[#durs + 1] = f.dur
        end
      else
        m.elite.n = m.elite.n + 1
        m.elite.strain = m.elite.strain + s
      end
    end
  end
  if m.elite.n > 0 then m.elite.strain = m.elite.strain / m.elite.n end
  for d, b in pairs(m.diffs) do
    b.strain = b.w > 0 and b.sum / b.w or 0
    local was = previous and previous.hard and previous.hard[d]
    if b.n >= D.MIN_FIGHTS and (b.strain >= D.HARD or (was and b.strain >= D.EASY)) then m.hard[d] = true end
  end
  -- the margin: below the lowest hard difference (0 and up; a hard -1 means even
  -- easier mobs hurt, the margin goes below your level)
  m.above = D.DEFAULT_ABOVE
  for d = -2, D.DEFAULT_ABOVE do
    if m.hard[d] then m.above = d - 1; break end
  end
  if #durs >= D.MIN_FIGHTS then
    table.sort(durs)
    m.killSecs = clamp(durs[math.floor((#durs + 1) / 2)], 4, 60)
  end
  return m
end

-- Experience for killing a mob of a level at a level (classic: 45 + 5 x mob level at
-- the same level, 5% more per level above, less below, nothing when grey).
function D.MobXP(mobLevel, level)
  local base = 45 + 5 * mobLevel
  local d = mobLevel - level
  if d >= 0 then return math.floor(base * (1 + 0.05 * math.min(d, 4)) + 0.5) end
  local grey = ns.Availability.GreyLevel(level)
  if mobLevel <= grey then return 0 end
  local zd = level <= 7 and 5 or level <= 9 and 6 or level <= 11 and 7 or level <= 15 and 8 or level <= 19 and 9
    or level <= 29 and 11 or level <= 39 and 12 or level <= 44 and 13 or level <= 49 and 14 or level <= 54 and 15 or 16
  return math.floor(base * (1 + d / zd) + 0.5)
end

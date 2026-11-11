-- The Guides menu as a tree (UI/Viewer.lua shows it with Blizzard_Menu). Pure.
--
-- Zones: the ones that suit you best first (the most experience to be had there
-- now), then every zone in a submenu per ten levels. Dungeons: the ones at your
-- level first, then a submenu per ten levels, raids apart. Class quests: the chains you can start now, the ones coming up within
-- SOON levels (shown, not startable yet), later ones per ten levels, raid quests
-- apart. Every entry says level, quest count and where; its tooltip lists the
-- quests with who gives them, where, and whether you can take them now.
--
-- item = { kind = "title" | "divider" | "sub" | "radio", text, children (sub),
--          key, selected(), select(), disabled, tip() -> { title, lines = { { text, color } } } }
local _, ns = ...
local P = ns:NewModule("Picker")
local A = ns.Availability

P.SOON = 10      -- levels ahead that "coming up" shows
P.NEAR_BELOW = 2 -- a dungeon still counts as yours this far below its range
P.NEAR_ABOVE = 3 -- and this far above
P.TIP_LINES = 14 -- quests listed in a tooltip at most
P.ZONES_BEST = 8 -- zones in "Best for you"

local GREY, WHITE, GREEN, DIM = { 0.5, 0.5, 0.5 }, { 1, 1, 1 }, { 0.25, 0.75, 0.25 }, { 0.65, 0.65, 0.65 }

local function plural(n, word) return ("%d %s%s"):format(n, word, n == 1 and "" or "s") end

local function hex(c)
  return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
end

-- "17-26" coloured like the quest log would colour its first level
local function levels(lo, hi, level)
  if not lo then return "" end
  local text = (hi and hi ~= lo) and (lo .. "-" .. hi) or tostring(lo)
  return hex(A.COLORS[A.Difficulty(lo, level)]) .. text .. "|r"
end

local function bracket(l)
  local lo = math.floor((l or 1) / 10) * 10
  if lo >= 60 then return 60, "Level 60" end
  return lo, ("Levels %d-%d"):format(math.max(lo, 1), lo + 9)
end

-- Map name of a spot / quest: where its giver stands, else its zone.
function P.MapName(ds, map) return map and ds.maps and ds.maps[map] or nil end

function P.Zone(ds, q)
  -- a zone's map, not a continent's (some npcs are only placed on the continent)
  for _, s in ipairs(ns.Quests.SharedGivers(ds, q)) do
    if ds.areaOfMap and ds.areaOfMap[s.map] then return P.MapName(ds, s.map) end
  end
  return P.MapName(ds, q.zone and ds.zones and ds.zones[q.zone])
end

local function named(list, t)
  local r = list and list[1] and t[list[1]]
  return r and r.n
end

-- Who gives a quest, as text: "Delgren the Purifier, Ashenvale", "the Shattered Orb",
-- "an item you find"
function P.Giver(ds, q)
  local zone = P.Zone(ds, q)
  local who = named(q.sn, ds.npcs) or (named(q.so, ds.objects or {}) and ("the " .. named(q.so, ds.objects)))
  if not who then return "an item you find" end
  return zone and (who .. ", " .. zone) or who
end

-- One quest as a tooltip line: "25 A Strange Artifact: an item you find (level 20)".
-- after: the quest it waits for (class chains), or nil.
function P.QuestLine(ds, char, q, after)
  local st, why = A.Status(q, char)
  local level = char.level or 1
  local text = ("%s %s: %s"):format(q.l and q.l > 0 and q.l or "?", q.n or ("Quest " .. q.id), P.Giver(ds, q))
  local color
  if st == "done" then
    text, color = text .. " (done)", GREY
  elseif st == "active" then
    text, color = text .. " (in your log)", WHITE
  else
    local min = ns.ClassQuests.MinLevel(q)
    if q.r and q.r > min then min = q.r end
    if min > level then
      text = text .. (" (level %d)"):format(min)
    elseif after and not char.completed[after.id] then
      text = text .. " (after " .. after.n .. ")"
    elseif st == "locked" or st == "low" then
      text = text .. " (" .. (why or "not yet") .. ")"
    elseif st == "available" or st == "trivial" then
      color = A.COLORS[A.Difficulty(q.l, level)]
    end
    color = color or DIM
  end
  return { text = text, color = color }
end

local function addLines(t, ds, char, ids, after)
  local n = 0
  for _, id in ipairs(ids) do
    local q = ds.quests[id]
    if q then
      n = n + 1
      if n > P.TIP_LINES then
        t.lines[#t.lines + 1] = { text = ("... and %d more"):format(#ids - P.TIP_LINES), color = DIM }
        return
      end
      t.lines[#t.lines + 1] = P.QuestLine(ds, char, q, after and after[id] and ds.quests[after[id]])
    end
  end
end

-- Zones -----------------------------------------------------------------------------

-- env: { here = map | nil (where you are), current() -> map | nil, select(map), above,
--        left(map) -> Zones.Left (the tooltip) }
local function zoneItem(ds, char, z, env)
  local now = z.ready > 0 and plural(z.ready, "quest") .. " now" or "none for you now"
  if z.active > 0 then now = now .. (" · %d in your log"):format(z.active) end
  local text = ("%s  %s · %s%s"):format(z.name, levels(z.minLevel, z.maxLevel, char.level or 1), now,
    env.here == z.map and " · you are here" or "")
  return {
    kind = "radio", key = 100000 + z.map, text = text, disabled = z.ready == 0 and z.active == 0,
    selected = function() return env.current and env.current() == z.map end,
    select = function() if env.select then env.select(z.map) end end,
    tip = function()
      local t = { title = z.name, lines = {} }
      local parts = {}
      if z.minLevel then
        parts[#parts + 1] = z.maxLevel ~= z.minLevel and ("levels " .. z.minLevel .. "-" .. z.maxLevel) or ("level " .. z.minLevel)
      end
      parts[#parts + 1] = plural(z.open, "quest") .. " not done yet"
      t.lines[1] = { text = table.concat(parts, " · "), color = DIM }
      local l = env.left and env.left(z.map) or ns.Zones.Left(ds, char, z.map, env.above)
      if #l.ready > 0 then
        t.lines[#t.lines + 1] = { text = "To take now:", color = WHITE }
        addLines(t, ds, char, l.ready)
      end
      if #l.active > 0 then
        t.lines[#t.lines + 1] = { text = "In your log:", color = WHITE }
        addLines(t, ds, char, l.active)
      end
      t.lines[#t.lines + 1] = (z.ready > 0 or z.active > 0)
        and { text = "Click: the route quests here until the zone has nothing left for you", color = GREEN }
        or { text = "Nothing to take here at your level yet", color = DIM }
      return t
    end,
  }
end

-- list: Zones.List (the best for you first).
function P.Zones(ds, char, list, env)
  local best, subs, order = {}, {}, {}
  for _, z in ipairs(list) do
    local item = zoneItem(ds, char, z, env)
    if z.xp > 0 and #best < P.ZONES_BEST then best[#best + 1] = item end
    local b, label = bracket(z.minLevel)
    if not subs[b] then subs[b] = { kind = "sub", text = label, children = {} }; order[#order + 1] = b end
    table.insert(subs[b].children, zoneItem(ds, char, z, env))
  end
  local out = { { kind = "title", text = ("Best for you (level %d)"):format(char.level or 1) } }
  if #best == 0 then out[#out + 1] = { kind = "title", text = "|cff999999none right now|r" } end
  for _, it in ipairs(best) do out[#out + 1] = it end
  if #order > 0 then
    out[#out + 1] = { kind = "divider" }
    table.sort(order)
    for _, b in ipairs(order) do
      local s = subs[b]
      table.sort(s.children, function(x, y) return x.text < y.text end)
      s.text = ("%s (%d)"):format(s.text, #s.children)
      out[#out + 1] = s
    end
  end
  return out
end

-- Dungeons -------------------------------------------------------------------------

-- env: { info(area) -> { raid, size, map } | nil, current = area | nil, select(area) }
local function dungeonItem(ds, char, d, env)
  local info = env.info and env.info(d.area) or {}
  local where = P.MapName(ds, info.map)
  local text = ("%s  %s · %s%s"):format(d.name, levels(d.minLevel, d.maxLevel, char.level or 1), plural(d.open, "quest"),
    where and (" · " .. where) or "")
  return {
    kind = "radio", key = d.area, text = text,
    selected = function() return env.current and env.current() == d.area end,
    select = function() if env.select then env.select(d.area) end end,
    tip = function()
      local t = { title = d.name, lines = {} }
      local parts = {}
      if d.minLevel then
        parts[#parts + 1] = (d.maxLevel and d.maxLevel ~= d.minLevel) and ("levels " .. d.minLevel .. "-" .. d.maxLevel)
          or ("level " .. d.minLevel)
      end
      if info.size then parts[#parts + 1] = info.size .. " players" end
      if where then parts[#parts + 1] = "entrance in " .. where end
      if #parts > 0 then t.lines[1] = { text = table.concat(parts, " · "), color = DIM } end
      local g = ns.Dungeons.Set(ds, char, d.area)
      local roots = {}
      for i, id in ipairs(g.roots) do roots[i] = id end
      table.sort(roots, function(a, b)
        local la, lb = ds.quests[a].l or 0, ds.quests[b].l or 0
        if la ~= lb then return la < lb end
        return a < b
      end)
      t.lines[#t.lines + 1] = { text = "Quests for the dungeon:", color = WHITE }
      addLines(t, ds, char, roots)
      local isRoot, lead = {}, {}
      for _, id in ipairs(g.roots) do isRoot[id] = true end
      for _, id in ipairs(g.order) do if not isRoot[id] then lead[#lead + 1] = id end end
      if #lead > 0 then
        t.lines[#t.lines + 1] = { text = ("Leading up to them (%d):"):format(#lead), color = WHITE }
        addLines(t, ds, char, lead)
      end
      t.lines[#t.lines + 1] = { text = "Click: the route takes you through all of them", color = GREEN }
      return t
    end,
  }
end

function P.Dungeons(ds, char, list, env)
  local level = char.level or 1
  local near, subs, raids, order = {}, {}, {}, {}
  for _, d in ipairs(list) do
    if d.open > 0 then
      local info = env.info and env.info(d.area) or {}
      local item = dungeonItem(ds, char, d, env)
      if info.raid then
        raids[#raids + 1] = item
      else
        local lo, hi = d.minLevel or 1, d.maxLevel or d.minLevel or 1
        if lo <= level + P.NEAR_ABOVE and hi >= level - P.NEAR_BELOW then near[#near + 1] = item end
        local b, label = bracket(lo)
        if not subs[b] then subs[b] = { kind = "sub", text = label, children = {} }; order[#order + 1] = b end
        table.insert(subs[b].children, item)
      end
    end
  end
  local out = {}
  out[#out + 1] = { kind = "title", text = ("At your level (%d)"):format(level) }
  if #near == 0 then out[#out + 1] = { kind = "title", text = "|cff999999none right now|r" } end
  for _, it in ipairs(near) do out[#out + 1] = it end
  out[#out + 1] = { kind = "divider" }
  table.sort(order)
  for _, b in ipairs(order) do
    local s = subs[b]
    s.text = ("%s (%d)"):format(s.text, #s.children)
    out[#out + 1] = s
  end
  if #raids > 0 then out[#out + 1] = { kind = "sub", text = ("Raids (%d)"):format(#raids), children = raids } end
  return out
end

-- Class quests ---------------------------------------------------------------------

-- the chain's zones: where its quests are given, most first, two at most
local function chainZone(ds, c)
  local count, zones = {}, {}
  for _, id in ipairs(c.quests) do
    local z = P.Zone(ds, ds.quests[id])
    if z then
      if not count[z] then zones[#zones + 1] = z end
      count[z] = (count[z] or 0) + 1
    end
  end
  table.sort(zones, function(a, b)
    if count[a] ~= count[b] then return count[a] > count[b] end
    return a < b
  end)
  return zones[1] and table.concat(zones, ", ", 1, math.min(2, #zones)) or nil
end

local function chainLevels(ds, c)
  local lo, hi
  for _, id in ipairs(c.quests) do
    local l = ds.quests[id].l
    if l and l > 0 then lo, hi = math.min(lo or l, l), math.max(hi or l, l) end
  end
  return lo, hi
end

-- env: { current = chain id | nil, select(id) }
local function chainItem(ds, char, c, env, ready)
  local level = char.level or 1
  local lo, hi = chainLevels(ds, c)
  local zone = chainZone(ds, c)
  local when = ready and "" or (" · from level %d"):format(c.minLevel)
  local text = ("%s  %s · %s%s%s"):format(c.name, levels(lo, hi, level), plural(c.open, "quest"),
    zone and (" · " .. zone) or "", when)
  return {
    kind = "radio", key = -c.id, text = text, disabled = not ready, chain = c,
    selected = function() return env.current and env.current() == c.id end,
    select = function() if env.select then env.select(c.id) end end,
    tip = function()
      local t = { title = c.name, lines = {} }
      local parts = { plural(#c.quests, "quest") }
      if lo then parts[#parts + 1] = hi ~= lo and ("levels " .. lo .. "-" .. hi) or ("level " .. lo) end
      if zone then parts[#parts + 1] = zone end
      t.lines[1] = { text = table.concat(parts, " · "), color = DIM }
      local after = {}
      for id, prev in pairs(c.after or {}) do after[id] = prev end
      addLines(t, ds, char, c.quests, after)
      t.lines[#t.lines + 1] = ready and { text = "Click: the route takes you through it", color = GREEN }
        or { text = ("Can be started from level %d"):format(c.minLevel), color = DIM }
      return t
    end,
  }
end

function P.Classes(ds, char, chains, env)
  local level = char.level or 1
  local now, soon, later, raids, order = {}, {}, {}, {}, {}
  local items = {}
  for _, c in ipairs(chains) do
    local ready = #c.reach > 0
    local it = chainItem(ds, char, c, env, ready and not c.raid)
    items[#items + 1] = it
    if c.raid then
      raids[#raids + 1] = it
    elseif ready then
      now[#now + 1] = it
    elseif c.minLevel <= level + P.SOON then
      soon[#soon + 1] = it
    else
      local b, label = bracket(c.minLevel)
      if not later[b] then later[b] = { kind = "sub", text = label, children = {} }; order[#order + 1] = b end
      table.insert(later[b].children, it)
    end
  end
  -- two entries that read the same: tell them apart by their first quest
  local seen = {}
  for _, it in ipairs(items) do seen[it.text] = (seen[it.text] or 0) + 1 end
  for _, it in ipairs(items) do
    local c = it.chain
    if seen[it.text] > 1 then
      local first = ds.quests[c.quests[1]].n
      local extra = first ~= c.name and (" (starts with " .. first .. ")") or (" (#" .. c.quests[1] .. ")")
      it.text = c.name .. extra .. it.text:sub(#c.name + 1)
    end
  end
  local out = { { kind = "title", text = "Ready now" } }
  if #now == 0 then out[#out + 1] = { kind = "title", text = "|cff999999none right now|r" } end
  for _, it in ipairs(now) do out[#out + 1] = it end
  if #soon > 0 then
    out[#out + 1] = { kind = "divider" }
    out[#out + 1] = { kind = "title", text = ("Coming up (next %d levels)"):format(P.SOON) }
    for _, it in ipairs(soon) do out[#out + 1] = it end
  end
  if #order > 0 then
    out[#out + 1] = { kind = "divider" }
    table.sort(order)
    local sub = { kind = "sub", text = "Later", children = {} }
    for _, b in ipairs(order) do
      local s = later[b]
      s.text = ("%s (%d)"):format(s.text, #s.children)
      sub.children[#sub.children + 1] = s
    end
    out[#out + 1] = sub
  end
  if #raids > 0 then out[#out + 1] = { kind = "sub", text = ("Raid quests (%d)"):format(#raids), children = raids } end
  return out
end

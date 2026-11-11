-- Steps: the route grouped the way a player works through it, one place at a time.
-- Pure.
--
--   "talk" step   one npc / object: its hand-ins and pick-ups in a row, in route order
--                 ("Talk to Marshal McBride: Turn in A Threat Within, Accept Kobold
--                 Camp Cleanup")
--   "work" step   objectives done together in one area ("Kill 10 Kobold Vermin,
--                 Collect 8 Tough Wolf Meat"), plus "also here" lines: every other
--                 open objective of an accepted quest whose area is close by
--
-- Every line knows whether it is done from the character's quest log, so a step
-- ticks off live and the current step is the first one with an open line.
--
-- step = { kind = "talk" | "work", spot = {map, x, y}, title, lines = {
--   { kind = "accept" | "turnin" | "kill" | "collect" | "object" | "event",
--     quest, index, text, have, need, done, also } } }
-- plus "grind", "use" and "train" steps (Route's grind / train actions; a train
-- step is done once you had a class trainer open after it was planned, or nothing
-- you can pay for is waiting any more).
local _, ns = ...
local S = ns:NewModule("Steps")
local G = ns.Geo

S.TALK_YARDS = 20   -- route actions this close at a spot without an npc are one talk step
S.WORK_YARDS = 250  -- objectives this close are worked together
S.ALSO_YARDS = 300  -- open objectives this close are listed as "also here"

local function objKind(o)
  if o.t == "kill" then return "kill" end
  if o.t == "item" then return "collect" end
  if o.t == "object" then return "object" end
  return "event"
end

S.ObjectiveKind = objKind

S.QUEST_TAGS = { group = "Elite", dungeon = "Dungeon", raid = "Raid", pvp = "PvP" }

-- " (Elite)": the quest log's tag of a quest, "" for none
function S.QuestTag(q)
  local tag = q and S.QUEST_TAGS[q.kind]
  return tag and (" (" .. tag .. ")") or ""
end

-- Wowhead's npc classification (the dataset's elite): how a mob is marked by name
S.CLASSIFICATION = { [1] = "elite", [2] = "rare elite", [3] = "boss", [4] = "rare" }

local function marked(rec, name)
  local c = rec and S.CLASSIFICATION[rec.elite]
  return c and (name .. " (" .. c .. ")") or name
end

S.SOURCE_NAMES = 2 -- up to this many sources are named in a line; more: the best and a count

-- Where an item objective comes from: verb, names (best source first). "Loot" from
-- creatures, "Collect" from objects only, "Buy" from vendors when nothing drops it.
-- The dataset's sources, else what the provider (QuestieDB) places at runtime, else
-- who the provider says it comes from without a place (inside dungeons); nil when
-- none knows (Forever's new quests are often not in either yet).
function S.ItemSources(ds, o, qid, i)
  local list = {}
  for _, s in ipairs(o.src or {}) do list[#list + 1] = { s[1], s[2] } end
  local p = ns.Prereqs and ns.Prereqs.Provider()
  if #list == 0 and qid and i and p and p.ObjectiveSpots then
    local ok, spots = pcall(p.ObjectiveSpots, qid, i, o)
    if ok and type(spots) == "table" then
      for _, sp in ipairs(spots) do
        if sp.id then list[#list + 1] = { sp.vendor and "v" or sp.kind, sp.id } end
      end
    end
  end
  -- who drops it without standing anywhere known: inside a dungeon (Head of VanCleef)
  if #list == 0 and qid and i and p and p.ObjectiveSources then
    local ok, src = pcall(p.ObjectiveSources, qid, i, o)
    if ok and type(src) == "table" then
      for _, s in ipairs(src) do list[#list + 1] = { s[1], s[2] } end
    end
  end
  local drops, vendors, seen, npc = {}, {}, {}, false
  for _, s in ipairs(list) do
    local kind, id = s[1], s[2]
    local rec = (kind == "o" and ds.objects or ds.npcs)[id]
    local name = rec and rec.n
    if not name and p and p.Name then
      local ok, n = pcall(p.Name, kind == "o" and "o" or "n", id)
      name = ok and n or nil
    end
    if name and name ~= o.text and not seen[name] then
      seen[name] = true
      if kind == "n" then name = marked(rec, name) end
      if kind == "v" then vendors[#vendors + 1] = name
      else
        drops[#drops + 1] = name
        npc = npc or kind == "n"
      end
    end
  end
  if #drops > 0 then return npc and "Loot" or "Collect", drops end
  if #vendors > 0 then return "Buy", vendors end
end

-- "A", "A or B", "A +5 more": the viewer is 330 px wide; the tooltip lists them all
local function anyOf(names)
  if #names == 1 then return names[1] end
  if #names <= S.SOURCE_NAMES then return names[1] .. " or " .. names[2] end
  return ("%s +%d more"):format(names[1], #names - 1)
end

-- "Kobold Vermin slain" -> "Kill 10 Kobold Vermin"; "Razormaw Incisor" -> "Loot 10
-- Razormaw Incisor from Highland Razormaw": who drops it, or "Collect 8 ..." when no
-- one knows. ds (and the quest id and objective index, for the provider) name it.
function S.ObjectiveText(o, ds, qid, i)
  local text = o.text or "objective"
  local n = o.qty and o.qty > 1 and (o.qty .. " ") or ""
  if o.t == "kill" then
    local name = text:gsub("%s+[Ss]lain$", "")
    local s1 = o.src and o.src[1]
    if ds and s1 and s1[1] == "n" and #o.src == 1 then name = marked(ds.npcs[s1[2]], name) end
    return "Kill " .. n .. name
  end
  if o.t == "item" then
    local verb, names
    if ds and not o.from then verb, names = S.ItemSources(ds, o, qid, i) end
    if verb then return ("%s %s%s from %s"):format(verb, n, text, anyOf(names)) end
    return "Collect " .. n .. text
  end
  if o.t == "object" then return "Use " .. text end
  return text
end

-- "Use Odd Tome from your bags to start the quest" / "...: it starts Lost Letter"
function S.UseText(item, q)
  return item == q.n and ("Use %s from your bags to start the quest"):format(item)
    or ("Use %s from your bags: it starts %s"):format(item, q.n)
end

local function questDone(char, qid) return char.completed[qid] == true end

-- Live state of an objective line from the quest log.
local function objectiveState(ds, char, qid, i)
  local q = ds.quests[qid]
  local o = q and q.obj and q.obj[i]
  if not o then return true end
  if questDone(char, qid) then return true, o.qty, o.qty end
  local entry = char.active and char.active[qid]
  if not entry or entry.simulated then return false, 0, o.qty end
  if entry.complete then return true, o.qty, o.qty end
  local lo = ns.Quests.LogObjective(entry, o, i)
  if lo then return lo.finished and true or false, lo.have, lo.need or o.qty end
  return false, 0, o.qty
end

function S.LineState(ds, char, line)
  if line.kind == "fpath" then return char.flyKnown and char.flyKnown[line.node] or false end
  if line.kind == "follow" then return line.done or false end -- as the member you follow says
  if line.kind == "grind" then
    -- the experience bar towards the level
    if (char.level or 0) >= line.level then return true end
    if char.level == line.level - 1 and char.xpMax and char.xpMax > 0 then line.have, line.need = char.xp or 0, char.xpMax end
    return false
  end
  if line.kind == "train" then
    if (char.trainedAt or 0) > (line.after or 0) then return true end
    local t = char.training
    return not t or (t.afford or 0) < ns.Training.PASS
  end
  if line.starter then
    -- loot the item that starts a quest: done once it is in your bags (or the quest is on)
    return (char.bag and char.bag[line.starter]) or (char.active and char.active[line.quest] and true)
      or questDone(char, line.quest) or false
  end
  if line.kind == "accept" then
    return (char.active and char.active[line.quest] and not char.active[line.quest].simulated)
      or questDone(char, line.quest)
  end
  if line.kind == "turnin" then return questDone(char, line.quest) end
  local done, have, need = objectiveState(ds, char, line.quest, line.index)
  line.have, line.need = have, need
  return done
end

local function placeName(ds, spot)
  local rec = spot and spot.id and (spot.kind == "o" and ds.objects or ds.npcs)[spot.id]
  return rec and rec.n
end

local function close(geo, a, b, yards)
  return G.Distance(geo, a, b) <= yards
end

-- Group route actions into steps (in route order), then mark lines done.
-- The first quest a hand-in opens that you can do (why the route makes the trip),
-- or nil.
function S.Opens(ds, char, q)
  for _, id in ipairs(ns.Route.Opens(ds, char)[q.id] or {}) do
    local f = ds.quests[id]
    if f and not char.completed[id] and not ns.Availability.Fixed(f, char) then return id end
  end
  return nil
end

function S.Build(ds, char, route, geo)
  local steps = {}
  local cur
  for _, a in ipairs(route or {}) do
    local q = a.quest and ds.quests[a.quest]
    if a.kind == "grind" then
      -- "Grind to level 14": its own step, at the mobs
      cur = { kind = "grind", spot = a.spot, title = ("Grind to level %d"):format(a.level), level = a.level - 1,
        lines = { { kind = "grind", level = a.level, npc = a.npc,
          text = ("Kill %s until level %d (about %d)"):format(a.name or "mobs", a.level, a.kills or 0) } } }
      steps[#steps + 1] = cur
      cur = nil
    elseif a.kind == "train" then
      -- "Train at Jaxon": its own step, at the trainer
      local t = char.training
      cur = { kind = "train", spot = a.spot, title = "Train at " .. (a.name or "your class trainer"), level = a.level,
        lines = { { kind = "train", after = char.trainedAt or 0,
          text = t and t.count > 0 and ns.Training.StepText(t) or "Learn your new spells" } } }
      steps[#steps + 1] = cur
      cur = nil
    elseif q and a.kind == "accept" and a.loot then
      -- started by an item that drops (Engine/Route lootStart): loot it, then use it
      local it = ns.Quests.StartItem(ds, q)
      local item = it and it.n or "the item"
      local rec = a.spot and (a.spot.kind == "o" and ds.objects or ds.npcs)[a.spot.id]
      local from = rec and rec.n or "them"
      local l = { kind = "collect", quest = a.quest, starter = a.loot,
        text = ("Loot %s from %s (%s)"):format(item, from, item == q.n and "it starts a quest" or ("it starts " .. q.n)) }
      l.done = S.LineState(ds, char, l) and true or false
      cur = { kind = "work", spot = a.spot, title = "Loot " .. item, level = a.level, lines = { l } }
      if char.bag and char.bag[a.loot] then S.AddUse(ds, char, cur, a.quest, a.loot) end
      steps[#steps + 1] = cur
      cur = nil
    elseif q and a.kind == "accept" and a.spot and a.spot.kind == "item" then
      -- started by an item in your bags: its own step, right where you are
      local it = ns.Quests.StartItem(ds, q)
      local item = it and it.n or "the item"
      cur = { kind = "use", title = "Use " .. item, level = a.level, item = a.spot.id, lines = {
        { kind = "accept", quest = a.quest, item = a.spot.id, text = S.UseText(item, q) } } }
      steps[#steps + 1] = cur
      cur = nil
    elseif q then
      local talk = a.kind == "accept" or a.kind == "turnin"
      -- a talk step is one npc: another one a few yards away (Daniel beside Brother
      -- Paxton) is a step of its own, titled with its name; only spots without an
      -- npc join by distance
      local same = a.spot.id and cur and cur.spot.id
        and a.spot.id == cur.spot.id and a.spot.kind == cur.spot.kind
      local unnamed = cur and not (a.spot.id and cur.spot.id)
      local joins = cur and ((talk and cur.kind == "talk" and (
          same or (unnamed and close(geo, a.spot, cur.spot, S.TALK_YARDS))))
        or (not talk and cur.kind == "work" and close(geo, a.spot, cur.spot, S.WORK_YARDS)))
      if not joins then
        cur = { kind = talk and "talk" or "work", spot = a.spot, lines = {}, level = a.level }
        steps[#steps + 1] = cur
      end
      if talk then
        cur.lines[#cur.lines + 1] = { kind = a.kind, quest = a.quest,
          text = (a.kind == "accept" and "Accept " or "Turn in ") .. q.n .. S.QuestTag(q) .. ns.ClassQuests.Tag(q, char),
          opens = a.kind == "turnin" and S.Opens(ds, char, q) or nil }
      else
        local o = q.obj[a.index]
        -- at: the line's own area (one worked along with another has none)
        cur.lines[#cur.lines + 1] = { kind = objKind(o), quest = a.quest, index = a.index,
          text = S.ObjectiveText(o, ds, a.quest, a.index), at = not a.along and a.spot or nil }
      end
      cur.level = a.level or cur.level
    end
  end
  for _, st in ipairs(steps) do
    if st.kind == "talk" then
      -- hand in first, then pick up (a hand-in can unlock what is picked up); a quest
      -- picked up and handed in right here keeps its order
      local acceptedHere = {}
      for _, l in ipairs(st.lines) do if l.kind == "accept" then acceptedHere[l.quest] = true end end
      local first, rest = {}, {}
      for _, l in ipairs(st.lines) do
        if l.kind == "turnin" and not acceptedHere[l.quest] then first[#first + 1] = l else rest[#rest + 1] = l end
      end
      st.lines = first
      for _, l in ipairs(rest) do st.lines[#st.lines + 1] = l end
      -- "Turn in A (opens B)" unless B is picked up right here
      for _, l in ipairs(st.lines) do
        if l.opens and not acceptedHere[l.opens] then l.text = l.text .. " (opens " .. ds.quests[l.opens].n .. ")" end
        l.opens = nil
      end
    end
    local name = st.kind ~= "grind" and st.kind ~= "use" and st.kind ~= "train" and placeName(ds, st.spot)
    if st.kind == "grind" or st.kind == "use" or st.kind == "train" then
      -- titled when built
    elseif st.kind == "talk" then
      st.title = name and ("Talk to " .. name) or "Talk"
    end -- work steps: titled from their open objectives (S.Refresh)
  end
  S.Refresh(ds, char, steps, geo)
  return steps
end

-- A work step's title: what is left of it, with progress ("Kill 12 Kobold Laborer
-- (3/12)"; two: "A & B"; more: "A +2 more"). All done: all of it.
function S.WorkTitle(st)
  local parts = {}
  local function add(l)
    local t = l.text or ""
    if l.have and l.need and l.have > 0 and l.need > 1 then t = ("%s (%d/%d)"):format(t, l.have, l.need) end
    parts[#parts + 1] = t
  end
  for _, l in ipairs(st.lines) do if not l.also and not l.done then add(l) end end
  if #parts == 0 then for _, l in ipairs(st.lines) do if not l.also then add(l) end end end
  if #parts == 0 then return "Objective" end
  if #parts == 1 then return parts[1] end
  if #parts == 2 then return parts[1] .. " & " .. parts[2] end
  return ("%s +%d more"):format(parts[1], #parts - 1)
end

-- A work step stands where its open objectives are. It was placed at the area of
-- its first objective, and the others close by were added to be worked from there;
-- once that one is done (Uncovering the Past ready to hand in, the raptors and
-- screechers still to kill) the spot moves to the area of an objective still open:
-- its own, or the one the route would choose for it from where you are (the current
-- step; a later one: from where it stood).
function S.Place(ds, char, st, geo, isCurrent)
  local open, own
  for _, l in ipairs(st.lines) do
    if l.index and not l.also and not l.done then
      if l.at == st.spot then return end
      open = open or l
      own = own or (l.at and l)
    end
  end
  if own then st.spot = own.at; return end
  if not open then return end
  local q = ds.quests[open.quest]
  local from = isCurrent and char.pos and st.spot and char.pos.map == st.spot.map and char.pos or st.spot
  local spot = q and ns.Route.WorkTarget(ds, q, open.index, geo, from)
  if spot then
    st.spot = { map = spot.map, x = spot.x, y = spot.y }
    open.at = st.spot
  end
end

-- Re-evaluate done flags and the "also here" lines; returns the current step index.
function S.Refresh(ds, char, steps, geo)
  local current
  for i, st in ipairs(steps) do
    -- drop previous "also" lines
    for k = #st.lines, 1, -1 do
      if st.lines[k].also then table.remove(st.lines, k) end
    end
    local open = 0
    for _, l in ipairs(st.lines) do
      l.done = S.LineState(ds, char, l) and true or false
      if not l.done then open = open + 1 end
    end
    st.done = open == 0
    if not st.done and not current then current = i end
    if st.kind == "work" then
      if not st.done then S.Place(ds, char, st, geo, current == i) end
      st.title = S.WorkTitle(st)
    end
  end
  local st = current and steps[current]
  if st and st.kind == "work" then
    S.AddAlso(ds, char, st, geo)
  end
  if st then S.AddBagStarts(ds, char, st) end
  return current
end

-- Other open objectives of accepted quests whose area is near this step's spot, and
-- every open objective of a quest this step works on, however far: the quest is listed
-- whole (From the Ashes: the Ironforge plan's step showed Menethil and Southshore close
-- by, and Thelsamar, 450 yards off and planned after a hand-in, went missing).
function S.AddAlso(ds, char, st, geo)
  local have, working = {}, {}
  for _, l in ipairs(st.lines) do
    if l.index then have[l.quest .. ":" .. l.index] = true end
    if l.index and not l.also then working[l.quest] = true end
  end
  local extra = {}
  for qid, entry in pairs(char.active or {}) do
    local q = ds.quests[qid]
    if q and not entry.complete then
      for i, o in ipairs(q.obj or {}) do
        if not have[qid .. ":" .. i] and not ns.Quests.ObjectiveDone(entry, o, i) then
          local near = working[qid]
          if not near then
            local spots = ns.Quests.ObjectiveSpots(ds, q, i, st.spot.map)
            local _, d = G.Nearest(geo, st.spot, spots)
            near = d <= S.ALSO_YARDS
          end
          if near then
            local l = { kind = objKind(o), quest = qid, index = i, text = S.ObjectiveText(o, ds, qid, i), also = true }
            l.done = S.LineState(ds, char, l) and true or false
            extra[#extra + 1] = l
          end
        end
      end
    end
  end
  table.sort(extra, function(a, b)
    if a.quest ~= b.quest then return a.quest < b.quest end
    return a.index < b.index
  end)
  for _, l in ipairs(extra) do st.lines[#st.lines + 1] = l end
  S.AddStarters(ds, char, st)
end

-- The mobs (and objects) this step's objectives send you to: { "n12" = name, ... }
local function targets(ds, st)
  local out = {}
  for _, l in ipairs(st.lines) do
    local q = l.quest and ds.quests[l.quest]
    local o = q and l.index and q.obj and q.obj[l.index]
    if o then
      if o.t == "kill" and o.id then out["n" .. o.id] = true end
      if o.t == "object" and o.id then out["o" .. o.id] = true end
      for _, s in ipairs(o.src or {}) do
        if s[1] == "n" or s[1] == "o" then out[s[1] .. s[2]] = true end
      end
    end
  end
  return out
end

S.STARTER_ABOVE = 3 -- a quest an item starts is worth it up to this many levels above you

-- Items that start a quest and drop from the mobs you are killing here anyway:
-- "Also: loot Nibbled-On Book from Kobold Vermin (starts a quest)". Only for quests
-- you can take and that are not grey or too high.
function S.AddStarters(ds, char, st)
  local level = char.level or 1
  local seen = {}
  for key in pairs(targets(ds, st)) do
    local kind, id = key:sub(1, 1), tonumber(key:sub(2))
    for _, qid in ipairs(ns.Quests.StartsDroppedBy(ds, kind, id)) do
      local q = ds.quests[qid]
      if not seen[qid] and q and ns.Availability.Status(q, char) == "available"
        and (not q.l or q.l <= level + S.STARTER_ABOVE) then
        seen[qid] = true
        local it = ns.Quests.StartItem(ds, q)
        local rec = (kind == "o" and ds.objects or ds.npcs)[id]
        local l = { kind = "collect", quest = qid, starter = it.id, also = true,
          text = ("Loot %s from %s (%s)"):format(it.n or "an item", rec and rec.n or "them",
            it.n == q.n and "it starts a quest" or ("it starts " .. q.n)) }
        l.done = S.LineState(ds, char, l) and true or false
        -- looted: ticked off, and using it is the next line of the same step
        if not l.done or (char.bag and char.bag[it.id]) then st.lines[#st.lines + 1] = l end
        if char.bag and char.bag[it.id] then S.AddUse(ds, char, st, qid, it.id) end
      end
    end
  end
end

-- "Use Odd Tome from your bags": a line of this step, not a step of its own (the
-- plan is made again once the quest is in the log). Not twice for a quest.
function S.AddUse(ds, char, st, qid, item)
  for _, l in ipairs(st.lines) do
    if l.kind == "accept" and l.quest == qid then return end
  end
  local q = ds.quests[qid]
  local it = ns.Quests.StartItem(ds, q)
  local l = { kind = "accept", quest = qid, item = item, also = true,
    text = S.UseText(it and it.n or "the item", q) }
  l.done = S.LineState(ds, char, l) and true or false
  st.lines[#st.lines + 1] = l
end

-- Every item in your bags that starts a quest you can take, on the current step.
function S.AddBagStarts(ds, char, st)
  if st.kind == "follow" then return end
  local list = {}
  for qid, item in pairs(ns.Quests.BagStarts(ds, char)) do list[#list + 1] = { qid, item } end
  table.sort(list, function(a, b) return a[1] < b[1] end)
  for _, e in ipairs(list) do S.AddUse(ds, char, st, e[1], e[2]) end
end

-- Line icon names in Media/Icons.tga (32 px icons, see UI/Viewer.lua).
S.ICON = { accept = "accept", turnin = "turnin", kill = "kill", collect = "collect",
  object = "goto", event = "goto", talk = "talk", work = "goto", fpath = "fly", fly = "fly",
  transit = "transit", hearth = "hearth", enter = "enter", path = "path", dungeon = "enter", grind = "kill", follow = "goto", use = "accept", train = "talk" }

-- Is the plan still good from the current step on? False when an open line can no
-- longer happen: a quest to accept became impossible for this character, or a quest
-- to work / hand in left the log (abandoned) and is not picked up again earlier.
function S.Valid(ds, char, steps, from)
  local accepting = {}
  for i = from or 1, #steps do
    for _, l in ipairs(steps[i].lines) do
      if not l.done and not l.also and l.quest then
        local q = ds.quests[l.quest]
        if l.starter then
          accepting[l.quest] = true -- "Loot Odd Tome": the quest it starts comes next
        elseif l.kind == "accept" then
          accepting[l.quest] = true
          if q and ns.Availability.Status(q, char) == "wrong" then return false, "cannot accept " .. q.n end
          -- "Use Odd Tome": the tome left your bags (sold, destroyed), nothing to use
          if l.item and not (char.bag and char.bag[l.item]) then
            return false, "no longer in your bags: the item that starts " .. (q and q.n or l.quest)
          end
        elseif not accepting[l.quest] and not (char.active and char.active[l.quest]) and not char.completed[l.quest] then
          return false, "no longer in the log: " .. (q and q.n or l.quest)
        end
      end
    end
  end
  return true
end

-- The quests a talk step still has you pick up from this npc / object (kind "n" or
-- "o", id), or nil when the step is not at it.
function S.OpenAccepts(st, kind, id)
  if not st or st.kind ~= "talk" or not st.spot or st.spot.id ~= id or st.spot.kind ~= kind then return nil end
  local out = {}
  for _, l in ipairs(st.lines) do
    if l.kind == "accept" and not l.done and not l.also and l.quest then out[#out + 1] = l.quest end
  end
  return out
end

-- What the npc's quest list says about the talk step at it: the quests to pick up
-- that it does not offer (`offered`: { [questId] = true }). Nothing while a hand-in
-- of the step is still open there: it can be what opens the next quest.
function S.NotOffered(st, kind, id, offered)
  local open = S.OpenAccepts(st, kind, id)
  if not open then return {} end
  for _, l in ipairs(st.lines) do
    if l.kind == "turnin" and not l.done then return {} end
  end
  local out = {}
  for _, qid in ipairs(open) do if not offered[qid] then out[#out + 1] = qid end end
  return out
end

-- Steps still open from `from` on.
function S.Remaining(steps, from)
  local n = 0
  for i = from or 1, #steps do if not steps[i].done then n = n + 1 end end
  return n
end

-- "Get the <town> flight path": an undiscovered flight point of your faction close
-- to a talk step becomes a line of that step (done once the client knows it). One
-- the route passes near (an open step within FLIGHT_PATH_DETOUR yards) gets its own
-- step, just before the first such step: a short detour to the flight master.
S.FLIGHT_PATH_YARDS = 150
S.FLIGHT_PATH_DETOUR = 400
local function fpLine(f)
  local who = f.npc and f.npc.name
  return { kind = "fpath", node = f.id, spot = f.spot,
    text = "Get the " .. (f.name or "?") .. " flight path" .. (who and (" from " .. who) or "") }
end
function S.AddFlightPaths(steps, undiscovered, geo)
  local taken = {}
  local line = fpLine
  for _, st in ipairs(steps) do
    if st.kind == "talk" and not st.done then
      for _, f in ipairs(undiscovered or {}) do
        if not taken[f.id] and G.Distance(geo, st.spot, f.spot) <= S.FLIGHT_PATH_YARDS then
          taken[f.id] = true
          st.lines[#st.lines + 1] = line(f)
        end
      end
    end
  end
  local before = {} -- [step index] = { step, ... }
  for _, f in ipairs(undiscovered or {}) do
    if not taken[f.id] then
      for i, st in ipairs(steps) do
        if not st.done and st.spot and G.Distance(geo, st.spot, f.spot) <= S.FLIGHT_PATH_DETOUR then
          taken[f.id] = true
          local l = line(f)
          before[i] = before[i] or {}
          table.insert(before[i], { kind = "fpath", spot = f.spot, title = l.text, lines = { l } })
          break
        end
      end
    end
  end
  for i = #steps, 1, -1 do
    for k = #(before[i] or {}), 1, -1 do table.insert(steps, i, before[i][k]) end
  end
end

-- A flight point you lack close to where you stand, wherever the route goes next:
-- a step of its own before the current one (a short walk to the flight master), made
-- again on every refresh like the dungeon step. Picked within FLIGHT_PATH_NEAR yards
-- of you, kept until you are FLIGHT_PATH_KEEP yards off (`held`: the node shown last
-- time), so walking along its edge does not make it come and go. None when an open
-- step already gets that flight path. Returns the step and the node it is for.
S.FLIGHT_PATH_NEAR = 400
S.FLIGHT_PATH_KEEP = 800
function S.NearFlightPath(steps, lacking, pos, geo, held)
  if not pos then return nil end
  local planned = {}
  for _, st in ipairs(steps or {}) do
    if not st.done then
      for _, l in ipairs(st.lines or {}) do
        if l.kind == "fpath" and not l.done then planned[l.node] = true end
      end
    end
  end
  local best, bestD
  for _, f in ipairs(lacking or {}) do
    if not planned[f.id] then
      local d = G.Distance(geo, pos, f.spot)
      local reach = f.id == held and S.FLIGHT_PATH_KEEP or S.FLIGHT_PATH_NEAR
      if d <= reach and (not bestD or d < bestD) then best, bestD = f, d end
    end
  end
  if not best then return nil end
  local l = fpLine(best)
  return { kind = "fpath", near = true, spot = best.spot, title = l.text, lines = { l } }, best.id
end

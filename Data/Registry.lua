-- Holds the validated dataset per flavor plus derived indexes.
local _, ns = ...
local R = ns:NewModule("Registry")

local datasets = {}

-- Placeholder quests the client still carries ("<UNUSED>", "[Never used]",
-- "<nyi> <TXT> ...", "zzOLD ..."): never real, never planned (Availability: wrong).
local PLACEHOLDER = { "unused", "never used", "<nyi>", "<txt>", "^zz", "deprecated", "%[ph%]" }
function R.IsPlaceholder(name)
  local n = (name or ""):lower()
  for _, p in ipairs(PLACEHOLDER) do
    if n:find(p) then return true end
  end
  return false
end

-- Placeholders whose name gives no sign: "Of Mice and Milk" (Westfall's Mouse wants
-- a cookie, hand-in Hemet Nesingwary in Stranglethorn; Wowhead forever's completion
-- text is "(PH) Thanks!", Questie blacklists it).
R.PLACEHOLDER_IDS = { [93928] = true }

-- the dataset a quest belongs to (Prereqs looks up a quest's predecessor)
local owner = setmetatable({}, { __mode = "k" })
function R.DatasetOf(q) return q and owner[q] end

-- giver / turn-in indexes: npc or object id -> { questId, ... }
local function index(ds)
  local startsN, startsO, endsN, endsO = {}, {}, {}, {}
  local function add(t, id, q)
    local l = t[id]
    if not l then l = {}; t[id] = l end
    l[#l + 1] = q
  end
  for qid, q in pairs(ds.quests) do
    q.id = qid
    owner[q] = ds
    if R.IsPlaceholder(q.n) or R.PLACEHOLDER_IDS[qid] then q.unused = true end
    for _, i in ipairs(q.sn or {}) do add(startsN, i, qid) end
    for _, i in ipairs(q.so or {}) do add(startsO, i, qid) end
    for _, i in ipairs(q.en or {}) do add(endsN, i, qid) end
    for _, i in ipairs(q.eo or {}) do add(endsO, i, qid) end
  end
  for _, t in ipairs({ startsN, startsO, endsN, endsO }) do
    for _, l in pairs(t) do table.sort(l) end
  end
  ds.starts = { n = startsN, o = startsO }
  ds.ends = { n = endsN, o = endsO }
  local mapsOfArea = {}
  for a, m in pairs(ds.zones) do mapsOfArea[m] = mapsOfArea[m] or a end
  ds.areaOfMap = mapsOfArea
  -- A series whose predecessors lead back to the quest lists alternatives one after
  -- another (one "Heeding the Call" per druid trainer), not prerequisites: quests
  -- in such a loop need none of each other (prevLoop); a quest whose predecessor is
  -- in one needs any one of them (prevAny = the loop's quests).
  for _, q in pairs(ds.quests) do
    local seen, cur = { [q.id] = true }, q
    for _ = 1, 60 do
      local p = cur.prev
      if not p then break end
      if p == q.id then
        local members = { q.id }
        local m = ds.quests[q.prev]
        while m and m.id ~= q.id do members[#members + 1] = m.id; m = ds.quests[m.prev] end
        table.sort(members)
        q.prevLoop, q.loop = true, members
        break
      end
      if seen[p] then break end
      seen[p] = true
      cur = ds.quests[p]
      if not cur then break end
    end
  end
  for _, q in pairs(ds.quests) do
    local p = q.prev and ds.quests[q.prev]
    if p and p.prevLoop and not q.prevLoop then q.prevAny = p.loop end
  end
  -- Alternatives: quests of one name leading to the same next quest are one step
  -- from different givers (three "The Hunter's Path" for a dwarf hunter, "The New
  -- Frontier" from three trainers), and so are the quests of a loop. One taken, the
  -- others are not for you (q.alts: the other ids; Engine/Prereqs).
  local groups = {}
  for id, q in pairs(ds.quests) do
    if q.next and q.n then
      local k = q.n .. "\0" .. q.next
      groups[k] = groups[k] or {}
      table.insert(groups[k], id)
    end
  end
  local function addAlts(list)
    if #list < 2 then return end
    for _, id in ipairs(list) do
      local q, seen = ds.quests[id], {}
      q.alts = q.alts or {}
      for _, a in ipairs(q.alts) do seen[a] = true end
      for _, other in ipairs(list) do
        if other ~= id and not seen[other] then table.insert(q.alts, other); seen[other] = true end
      end
      table.sort(q.alts)
    end
  end
  for _, list in pairs(groups) do addAlts(list) end
  for _, q in pairs(ds.quests) do if q.loop then addAlts(q.loop) end end
  -- "Explore Zone" next to the quest's own explore objective ("Fully explore Frostmane
  -- Hold") is not an objective of the client's: Wowhead lists both. o.dup: done with
  -- the other one (Engine/Route plans only that one; 40 quests).
  for _, q in pairs(ds.quests) do
    local generic, events = nil, 0
    for _, o in ipairs(q.obj or {}) do
      if o.t == "event" then
        events = events + 1
        if o.text == R.GENERIC_EXPLORE then generic = o end
      end
    end
    if generic and events > 1 then generic.dup = true end
  end
end
R.GENERIC_EXPLORE = "Explore Zone"

function R.Register(flavor, ds)
  local ok, errs = ns.Schema.Validate(ds)
  if not ok then
    R.lastErrors = errs
    if ns.Log then
      ns.Log("error", ("dataset %s rejected: %d errors, first: %s"):format(flavor, #errs, errs[1]))
    end
    return false, errs
  end
  index(ds)
  datasets[flavor] = ds
  return true
end

function R.Get(flavor) return datasets[flavor] end

function R.Flavors() return ns.Util.sortedKeys(datasets) end

function R.Clear() datasets = {} end

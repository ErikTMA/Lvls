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
end

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

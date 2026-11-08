-- Holds the validated dataset per flavor plus derived indexes.
local _, ns = ...
local R = ns:NewModule("Registry")

local datasets = {}

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

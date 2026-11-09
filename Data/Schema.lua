-- Dataset contract (the generated Data/<flavor>/Dataset.lua). A dataset that breaks it
-- is refused whole, never half-loaded.
--
--   meta     { schema = 1, flavor, generated, source }
--   quests   [questId] = {
--              n = name, l = quest level, r = required level,
--              side = "A" | "H" (nil: both), races / classes = bitmask (nil: all),
--              sn / so = giver npc / object ids, en / eo = turn-in npc / object ids,
--              zone = AreaTable id (inst = true for dungeon / raid zones), sort = Wowhead
--              category2 when the quest is filed under a sort instead of a zone,
--              prev / next = neighbours in Wowhead's linear series,
--              prof = { skillId [, value] }, rep = "daily" | "weekly",
--              kind = "group" | "dungeon" | "raid" | "pvp" | "class" | "event",
--              xp, money, provided = { itemId, ... },
--              si = { id = itemId, n = name, src = { { "n" | "o", id, dropPercent }, ... } }:
--                   the item that starts the quest (no giver) and where it drops,
--              obj = { { t = "kill" | "item" | "object" | "faction" | "spell" | "event",
--                        id, qty, text,
--                        src = { { "n" | "o" | "v", id, dropPercent }, ... },
--                        from = "provided" | "crafted" | { "q", questId } }, ... } }
--   npcs     [npcId]  = { n, p = { [uiMapId] = { packed, ... } }, lv = {min, max},
--                         ra / rh = reaction to Alliance / Horde (1, 0, -1), elite }
--   objects  [objId]  = { n, p }
--   zones    [areaId] = uiMapId
--   maps     [uiMapId] = name
--   travel   { fly = {npcIds}, zeppelin = {...}, ship = {...}, inn = {...} } (optional)
--   trainers [classId] = {npcIds}: class trainers (UnitClass' third value) (optional)
-- A packed point is x*10*1000 + y*10 (map percent, tenths).
local _, ns = ...
local S = ns:NewModule("Schema")

S.VERSION = 1
S.OBJECTIVE_TYPES = { kill = true, item = true, object = true, faction = true, spell = true, event = true }
S.SOURCE_KINDS = { n = true, o = true, v = true }

local function isInt(v) return type(v) == "number" and v == math.floor(v) end

local function idList(v)
  if v == nil then return true end
  if type(v) ~= "table" then return false end
  for _, x in ipairs(v) do if not isInt(x) then return false end end
  return true
end

local function points(p)
  if p == nil then return true end
  if type(p) ~= "table" then return false end
  for m, list in pairs(p) do
    if not isInt(m) or type(list) ~= "table" then return false end
    for _, v in ipairs(list) do
      if not isInt(v) or v < 0 or v > 1000 * 1000 + 1000 then return false end
    end
  end
  return true
end

function S.Validate(ds)
  local errs = {}
  local function err(msg)
    if #errs < 50 then errs[#errs + 1] = msg end
  end
  if type(ds) ~= "table" then return false, { "dataset is not a table" } end
  local meta = ds.meta
  if type(meta) ~= "table" then
    err("meta missing")
  elseif meta.schema ~= S.VERSION then
    err("schema " .. tostring(meta.schema) .. ", expected " .. S.VERSION)
  end
  for _, k in ipairs({ "quests", "npcs", "objects", "zones", "maps" }) do
    if type(ds[k]) ~= "table" then err(k .. " missing") end
  end
  if #errs > 0 then return false, errs end
  for id, q in pairs(ds.quests) do
    local where = "quest " .. tostring(id)
    if not isInt(id) then err(where .. ": id") end
    if type(q) ~= "table" or type(q.n) ~= "string" then
      err(where .. ": name")
    else
      if q.l ~= nil and not isInt(q.l) then err(where .. ": level") end
      if q.r ~= nil and not isInt(q.r) then err(where .. ": required level") end
      if q.side ~= nil and q.side ~= "A" and q.side ~= "H" then err(where .. ": side") end
      for _, k in ipairs({ "sn", "so", "en", "eo", "provided" }) do
        if not idList(q[k]) then err(where .. ": " .. k) end
      end
      if q.si ~= nil then
        if type(q.si) ~= "table" or not isInt(q.si.id) then
          err(where .. ": start item")
        else
          for _, s in ipairs(q.si.src or {}) do
            if type(s) ~= "table" or (s[1] ~= "n" and s[1] ~= "o") or not isInt(s[2]) then
              err(where .. ": start item source")
            end
          end
        end
      end
      if q.obj ~= nil then
        if type(q.obj) ~= "table" then
          err(where .. ": objectives")
        else
          for i, o in ipairs(q.obj) do
            if type(o) ~= "table" or not S.OBJECTIVE_TYPES[o.t] then
              err(where .. ": objective " .. i .. " type")
            elseif o.src ~= nil then
              for _, s in ipairs(o.src) do
                if type(s) ~= "table" or not S.SOURCE_KINDS[s[1]] or not isInt(s[2]) then
                  err(where .. ": objective " .. i .. " source")
                end
              end
            end
          end
        end
      end
    end
  end
  for _, kind in ipairs({ "npcs", "objects" }) do
    for id, rec in pairs(ds[kind]) do
      if not isInt(id) or type(rec) ~= "table" or not points(rec.p) then
        err(kind .. " " .. tostring(id) .. ": record")
      end
    end
  end
  if ds.travel ~= nil then
    if type(ds.travel) ~= "table" then err("travel") else
      for kind, ids in pairs(ds.travel) do
        if not idList(ids) then err("travel " .. tostring(kind)) end
      end
    end
  end
  if ds.trainers ~= nil then
    if type(ds.trainers) ~= "table" then err("trainers") else
      for cls, ids in pairs(ds.trainers) do
        if not isInt(cls) or not idList(ids) then err("trainers " .. tostring(cls)) end
      end
    end
  end
  for a, m in pairs(ds.zones) do
    if not isInt(a) or not isInt(m) then err("zones " .. tostring(a)) end
  end
  return #errs == 0, errs
end

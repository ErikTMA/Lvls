-- Abandoning grey quests (Engine/Grey.lua):
--   the viewer's trash can   "Abandon 3 grey quests? ..."  Abandon / Cancel (Shift-click: no question)
--   farGrey (setting)        "2 grey quests are more than 10 minutes away: ... Abandon them?"
--                            Abandon / Keep. Kept ones are not asked about again this session.
local _, ns = ...
local A = ns:NewModule("Abandon")

A.ALL, A.FAR = "LVLS_ABANDON_GREY", "LVLS_ABANDON_FAR"
A.NAMES = 6         -- names in a question, then "and 3 more"
A.CHECK_SECS = 15   -- how often the far ones are looked for, at most
A.kept = {}         -- [questId] = true: you said keep (this session)
local lastCheck

local function quests(n) return ("%d grey quest%s"):format(n, n == 1 and "" or "s") end

-- "Kobold Camp Cleanup, Wolves Across the Border and 3 more"
function A.Names(ds, ids)
  local names = {}
  for i = 1, math.min(#ids, A.NAMES) do
    local q = ds.quests[ids[i]]
    local entry = ns.char and ns.char.active and ns.char.active[ids[i]]
    names[i] = (q and q.n) or (entry and entry.title) or ("quest " .. ids[i])
  end
  local t = table.concat(names, ", ")
  if #ids > A.NAMES then t = t .. (" and %d more"):format(#ids - A.NAMES) end
  return t
end

-- Abandon these quests; returns how many the client took.
function A.Abandon(ids)
  local ds = ns.ActiveDataset()
  local done, gone = 0, {}
  for _, qid in ipairs(ids) do
    if ns.Game.AbandonQuest(qid) then done = done + 1; gone[#gone + 1] = qid end
  end
  if done > 0 then
    ns.Log("info", ("abandoned %s: %s"):format(quests(done), ds and A.Names(ds, gone) or ""))
    if ns.Refresh then ns.Refresh() end
  end
  return done
end

local function define()
  if not StaticPopupDialogs or type(StaticPopup_Show) ~= "function" then return false end
  StaticPopupDialogs[A.ALL] = StaticPopupDialogs[A.ALL] or {
    text = "Lvls!: abandon %s?\n\n%s",
    button1 = "Abandon", button2 = "Cancel",
    OnAccept = function(_, data) A.Abandon(data) end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  }
  StaticPopupDialogs[A.FAR] = StaticPopupDialogs[A.FAR] or {
    text = "Lvls!: %s\n\nAbandon them? (Settings: Offer to abandon far grey quests)",
    button1 = "Abandon", button2 = "Keep",
    OnAccept = function(_, data) A.asking = nil; A.Abandon(data) end,
    OnCancel = function(_, data)
      A.asking = nil
      for _, qid in ipairs(data or {}) do A.kept[qid] = true end
    end,
    OnHide = function() A.asking = nil end, -- closed some other way: may ask again
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  }
  return true
end

-- The grey quests in your log, now.
function A.Grey()
  local ds, char = ns.ActiveDataset(), ns.char
  if not ds or not char then return {} end
  return ns.Grey.List(ds, char)
end

-- The trash can: abandon every grey quest, after asking (Shift: at once).
function A.Trash()
  local ids = A.Grey()
  if #ids == 0 then ns.Log("info", "no grey quests in your log"); return end
  if (type(IsShiftKeyDown) == "function" and IsShiftKeyDown()) or not define() then
    A.Abandon(ids)
    return
  end
  StaticPopup_Show(A.ALL, quests(#ids), A.Names(ns.ActiveDataset(), ids), ids)
end

-- The grey quests further than the setting's minutes, not kept: { questId, ... }.
function A.Far()
  local ds, char, s = ns.ActiveDataset(), ns.char, ns.db and ns.db.settings
  if not ds or not char or not s then return {} end
  local ctx = ns.travelCtx
  local travel = ctx and function(a, b) return (ns.Travel.Time(a, b, ctx)) end
  local out = {}
  for _, f in ipairs(ns.Grey.Far(ds, char, (s.farGreyMinutes or 10) * 60, ns.Game.geo, travel, ctx and ctx.speed)) do
    if not A.kept[f.quest] then out[#out + 1] = f.quest end
  end
  return out
end

-- With the setting on: ask about the far ones (not in combat, not twice at once,
-- at most every CHECK_SECS). True when it asked.
function A.Check(now)
  local s = ns.db and ns.db.settings
  if not s or not s.farGrey or A.asking then return false end
  if type(InCombatLockdown) == "function" and InCombatLockdown() then return false end
  now = now or (GetTime and GetTime()) or 0
  if lastCheck and now - lastCheck < A.CHECK_SECS then return false end
  lastCheck = now
  local ok, ids = pcall(A.Far)
  if not ok then ns.Log("debug", "far grey quests: " .. tostring(ids)); return false end
  if #ids == 0 or not define() then return false end
  A.asking = true
  local text = ("%s %s more than %d minute%s away: %s"):format(quests(#ids), #ids == 1 and "is" or "are",
    s.farGreyMinutes or 10, (s.farGreyMinutes or 10) == 1 and "" or "s", A.Names(ns.ActiveDataset(), ids))
  StaticPopup_Show(A.FAR, text, nil, ids)
  return true
end

function A.Reset() lastCheck = nil end -- tests, and a changed setting

ns.Events.On("LVLS_UPDATED", function() A.Check() end)

-- Group sync questions (StaticPopup):
--   "Alice has done 6 quests you have not. Catch up with Alice?"  Catch up / Not now
--   "Bob wants to catch up with you (6 quests). Follow his route to help?"  Follow / No
local _, ns = ...
local P = ns:NewModule("SyncPrompt")

P.CATCHUP, P.FOLLOW = "LVLS_SYNC_CATCHUP", "LVLS_SYNC_FOLLOW"

local function define()
  if not StaticPopupDialogs or type(StaticPopup_Show) ~= "function" then return false end
  StaticPopupDialogs[P.CATCHUP] = StaticPopupDialogs[P.CATCHUP] or {
    text = "Lvls!: %s has done %s you have not.\n\nCatch up with them? Lvls! routes you through those quests and everything you need before them.",
    button1 = "Catch up", button2 = "Not now",
    OnAccept = function(_, data) ns.asking = nil; ns.SetSync(data, "catchup") end,
    OnCancel = function() ns.asking = nil end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  }
  StaticPopupDialogs[P.FOLLOW] = StaticPopupDialogs[P.FOLLOW] or {
    text = "Lvls!: %s wants to catch up with you (%s).\n\nFollow their route to help?",
    button1 = "Follow", button2 = "No",
    OnAccept = function(_, data) ns.SetSync(data, "follow") end,
    OnCancel = function(_, data) ns.GroupSync.Send(("F|%s|off"):format(data)) end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  }
  return true
end

local function quests(n) return ("%d quest%s"):format(n, n == 1 and "" or "s") end

function P.AskCatchUp(name, count)
  if not define() then return false end
  StaticPopup_Show(P.CATCHUP, name, quests(count), name)
  return true
end

function P.AskFollow(name, count)
  if not define() then return false end
  StaticPopup_Show(P.FOLLOW, name, quests(count), name)
  return true
end

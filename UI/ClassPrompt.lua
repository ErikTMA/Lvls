-- "A class quest is possible: focus on it?" A dialog with Focus and Later
-- (StaticPopup; Blizzard_StaticPopup: StaticPopup_Show(which, text1, text2, data),
-- OnAccept(dialog, data), OnCancel(dialog, data)). Later keeps it in the Guides menu.
local _, ns = ...
local P = ns:NewModule("ClassPrompt")

P.WHICH = "LVLS_CLASS_QUEST"

local function define()
  if not StaticPopupDialogs then return false end
  if not StaticPopupDialogs[P.WHICH] then
    StaticPopupDialogs[P.WHICH] = {
      text = "Lvls!: the class quest %s is possible now (%s).\n\nFocus on it?",
      button1 = "Focus",
      button2 = "Later",
      OnAccept = function(_, data) ns.asking = nil; ns.SetClassGuide(data) end,
      OnCancel = function(_, data) ns.ClassLater(data) end,
      timeout = 0,
      whileDead = true,
      hideOnEscape = true,
      preferredIndex = 3,
    }
  end
  return true
end

-- Show the question; false when the client has no dialogs (the caller says it in
-- the chat instead).
function P.Ask(chain)
  if not define() or type(StaticPopup_Show) ~= "function" then return false end
  local n = #chain.reach
  StaticPopup_Show(P.WHICH, chain.name, ("%d quest%s"):format(n, n == 1 and "" or "s"), chain.id)
  return true
end

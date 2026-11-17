-- Lvls!'s own yes/no questions (grey quests to abandon, group sync), in a window of
-- its own. Not StaticPopup: a dialog an addon shows taints StaticPopup's shared list
-- of shown dialogs, and Blizzard code that walks it while ours is up is blamed on
-- Lvls! (GuildControlUI on GUILD_RANKS_UPDATE_ACTIVE_PLAYER: StaticPopup_Hide, then
-- C_Discord.IsUserOAuthed() is ADDON_ACTION_FORBIDDEN; Blizzard_StaticPopup's
-- StaticPopup_CollapseTable says as much).
--   Ask.Define(key, { text, button1, button2, OnAccept(_, data), OnCancel(_, data), OnHide(_, data) })
--   Ask.Show(key, a1, a2, data): text:format(a1, a2); one question at a time, the
--   next waits. Escape-free: the two buttons answer.
local _, ns = ...
local A = ns:NewModule("Ask")

A.defs = {}
A.queue = {}  -- { key, text, data }: the first is on screen
A.WIDTH = 360

function A.Define(key, def) A.defs[key] = A.defs[key] or def end

local frame

local function build()
  if frame or not CreateFrame then return frame end
  local f = CreateFrame("Frame", "LvlsAsk", UIParent, "BackdropTemplate")
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetPoint("TOP", UIParent, "TOP", 0, -135)
  f:SetWidth(A.WIDTH)
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32,
      insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
  end
  f.text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  f.text:SetPoint("TOP", f, "TOP", 0, -18)
  f.text:SetWidth(A.WIDTH - 40)
  f.text:SetJustifyH("CENTER")
  f.buttons = {}
  for i = 1, 2 do
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(128, 22)
    b:SetPoint("BOTTOM", f, "BOTTOM", i == 1 and -70 or 70, 16)
    b:SetScript("OnClick", function() A.Answer(i) end)
    f.buttons[i] = b
  end
  f:Hide()
  frame = f
  return f
end

local function present()
  local q = A.queue[1]
  local f = build()
  if not q or not f then return end
  local def = A.defs[q.key]
  f.text:SetText(q.text)
  f.buttons[1]:SetText(def.button1 or "OK")
  f.buttons[2]:SetText(def.button2 or "Cancel")
  local h = f.text.GetStringHeight and f.text:GetStringHeight()
  f:SetHeight((type(h) == "number" and h or 60) + 70)
  f:Show()
end

-- True when it was asked (or waits its turn).
function A.Show(key, a1, a2, data)
  local def = A.defs[key]
  if not def then return false end
  local ok, text = pcall(string.format, def.text or "", a1 or "", a2 or "")
  A.queue[#A.queue + 1] = { key = key, text = ok and text or (def.text or ""), data = data }
  if #A.queue == 1 then present() end
  return true
end

-- The question on screen: key, data (nil when none).
function A.Current()
  local q = A.queue[1]
  if q then return q.key, q.data end
end

-- Answer the question on screen: 1 the first button, 2 the second.
function A.Answer(button)
  local q = table.remove(A.queue, 1)
  if not q then return end
  if frame then frame:Hide() end
  local def = A.defs[q.key]
  local fn = def and (button == 1 and def.OnAccept or def.OnCancel)
  if fn then fn(nil, q.data) end
  if def and def.OnHide then def.OnHide(nil, q.data) end
  present()
end

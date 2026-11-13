-- /lvls share: a box with the share string selected, ready for Ctrl+C, and where to
-- paste it (Engine/Gather.lua G.URL). Styled as the tour's box (UI/Tour.lua).
local _, ns = ...
local SH = ns:NewModule("Share")

SH.WIDTH = 420
local box

local function bg(f, c)
  local t = f:CreateTexture(nil, "BACKGROUND")
  t:SetAllPoints(f)
  t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
  return t
end

local function create()
  local C = ns.Viewer.COLORS
  box = CreateFrame("Frame", "LvlsShareFrame", UIParent)
  box:SetSize(SH.WIDTH, 132)
  box:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  box:SetFrameStrata("DIALOG")
  box:SetClampedToScreen(true)
  box:EnableMouse(true)
  bg(box, { 0.067, 0.067, 0.067, 0.97 })
  box.accent = box:CreateTexture(nil, "ARTWORK")
  box.accent:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
  box.accent:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
  box.accent:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 0, 0)
  box.accent:SetWidth(3)
  box.title = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  box.title:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -10)
  box.title:SetTextColor(C.title[1], C.title[2], C.title[3])
  box.title:SetText("Share what Lvls! gathered")
  box.body = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  box.body:SetPoint("TOPLEFT", box.title, "BOTTOMLEFT", 0, -6)
  box.body:SetPoint("RIGHT", box, "RIGHT", -10, 0)
  if box.body.SetJustifyH then box.body:SetJustifyH("LEFT") end
  if box.body.SetWordWrap then box.body:SetWordWrap(true) end
  box.body:SetTextColor(C.text[1], C.text[2], C.text[3])
  box.edit = CreateFrame("EditBox", nil, box)
  box.edit:SetPoint("TOPLEFT", box.body, "BOTTOMLEFT", 0, -8)
  box.edit:SetPoint("RIGHT", box, "RIGHT", -10, 0)
  box.edit:SetHeight(22)
  box.edit:SetFontObject("ChatFontSmall")
  box.edit:SetAutoFocus(true)
  if box.edit.SetMaxLetters then box.edit:SetMaxLetters(0) end
  if box.edit.SetMaxBytes then box.edit:SetMaxBytes(0) end
  box.edit:SetTextInsets(6, 6, 0, 0)
  bg(box.edit, { 0, 0, 0, 0.6 })
  -- the text is not for editing: typing puts it back, a click selects it all
  box.edit:SetScript("OnTextChanged", function(self, user)
    if user and box.text and self:GetText() ~= box.text then self:SetText(box.text); self:HighlightText() end
  end)
  box.edit:SetScript("OnMouseUp", function(self) self:HighlightText() end)
  box.edit:SetScript("OnEscapePressed", function() box:Hide() end)
  box.edit:SetScript("OnEnterPressed", function() box:Hide() end)
  box.close = CreateFrame("Button", nil, box)
  box.close:SetSize(52, 20)
  box.close:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -10, 8)
  bg(box.close, C.bar)
  box.close.text = box.close:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  box.close.text:SetPoint("CENTER", box.close, "CENTER", 0, 0)
  box.close.text:SetText("Done")
  local h = box.close:CreateTexture(nil, "HIGHLIGHT")
  h:SetAllPoints(box.close)
  h:SetColorTexture(1, 1, 1, 0.12)
  box.close:SetScript("OnClick", function() box:Hide() end)
  if UISpecialFrames then table.insert(UISpecialFrames, "LvlsShareFrame") end
end

-- What the box says over the string.
function SH.Body(s)
  return ("Ctrl+C copies it (%s characters). Paste it at %s. It holds where you met npcs and objects and what counted for your quests: no names, no realm."):format(
    tostring(#s), ns.Gather.URL)
end

-- Show the string, selected. False when there is no UI (tests without frames).
function SH.Show(s)
  if not CreateFrame or not ns.Viewer or not ns.Viewer.COLORS then return false end
  if not box then create() end
  box.text = s
  box.body:SetText(SH.Body(s))
  box:Show()
  box.edit:SetText(s)
  box.edit:SetFocus()
  box.edit:HighlightText()
  return true
end

-- The item bar: a movable row of buttons for the items to use now (Engine/UseItems):
-- an item that starts a quest, the quest log's item for a quest (use it on an npc,
-- a corpse, at a place), items a quest gives you that have a use. Click to use;
-- key bindings for the first four (Bindings.xml: Key Bindings -> AddOns -> Lvls!).
-- Drag a button to move the bar (unless locked: /lvls items lock).
--
-- The buttons are secure (SecureActionButtonTemplate, type "item"): the client
-- refuses to change them in combat, so a change waits until the fight is over.
-- API (wow-ui-source branch forever): C_Item.GetItemIconByID / GetItemCount /
-- IsItemInRange, C_Container.GetItemCooldown, GameTooltip:SetItemByID,
-- InCombatLockdown, GetBindingKey, TEXTURE_ITEM_QUEST_BANG.
local _, ns = ...
local IB = ns:NewModule("ItemBar")

IB.SIZE, IB.GAP = 36, 4
IB.list, IB.key = {}, nil
IB.pending = false -- a change waits for the end of combat
local bar
local buttons = {}

local function combat() return InCombatLockdown and InCombatLockdown() end

local function binding(i)
  local key = GetBindingKey and GetBindingKey("CLICK LvlsItemButton" .. i .. ":LeftButton")
  if not key then return "" end
  if GetBindingText then key = GetBindingText(key, true) or key end
  return key
end

local function tooltip(b)
  local it = b.item
  if not it or not GameTooltip then return end
  GameTooltip:SetOwner(b, "ANCHOR_TOP")
  if GameTooltip.SetItemByID then GameTooltip:SetItemByID(it.id) end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(it.text, 0.25, 0.75, 1)
  if not (ns.db and ns.db.settings.lockItemBar) then
    GameTooltip:AddLine("Drag to move (/lvls items lock)", 0.6, 0.6, 0.6)
  end
  GameTooltip:Show()
end

local function savePosition()
  local point, _, rel, x, y = bar:GetPoint(1)
  if point and ns.db then ns.db.itemBarPos = { point, rel or point, x or 0, y or 0 } end
end

local function place()
  bar:ClearAllPoints()
  local p = ns.db and ns.db.itemBarPos
  if type(p) == "table" and p[1] then
    bar:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  else
    bar:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
  end
end

local function newButton(i)
  local b = CreateFrame("Button", "LvlsItemButton" .. i, bar, "SecureActionButtonTemplate")
  b:SetSize(IB.SIZE, IB.SIZE)
  b:SetPoint("LEFT", bar, "LEFT", (i - 1) * (IB.SIZE + IB.GAP), 0)
  b:RegisterForClicks("AnyUp", "AnyDown") -- the client acts on down or up (ActionButtonUseKeyDown)
  b:SetAttribute("type", "item")
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints(b)
  if b.icon.SetTexCoord then b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
  b.bang = b:CreateTexture(nil, "OVERLAY")
  b.bang:SetTexture(TEXTURE_ITEM_QUEST_BANG or "Interface\\ContainerFrame\\UI-Icon-QuestBang")
  b.bang:SetAllPoints(b)
  b.bang:Hide()
  b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
  b.hotkey = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
  b.hotkey:SetPoint("TOPRIGHT", b, "TOPRIGHT", -2, -2)
  b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
  b.cd:SetAllPoints(b)
  if b.SetPushedTexture then b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress") end
  if b.SetHighlightTexture then b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD") end
  b:RegisterForDrag("LeftButton")
  b:SetScript("OnDragStart", function()
    if not (ns.db and ns.db.settings.lockItemBar) and not combat() then bar:StartMoving() end
  end)
  b:SetScript("OnDragStop", function() bar:StopMovingOrSizing(); savePosition() end)
  b:SetScript("OnEnter", tooltip)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  b:Hide()
  return b
end

-- Count, cooldown, range and key: fine in combat (only the secure parts are not).
function IB.Paint()
  local target = UnitExists and UnitExists("target")
  for i, b in ipairs(buttons) do
    local it = b.item
    if it and b:IsShown() then
      local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(it.id)
      b.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
      if it.kind == "start" then b.bang:Show() else b.bang:Hide() end
      local n = C_Item and C_Item.GetItemCount and ns.Util.plain(C_Item.GetItemCount(it.id)) or 0
      b.count:SetText(n > 1 and tostring(n) or "")
      if C_Container and C_Container.GetItemCooldown then
        local start, duration = C_Container.GetItemCooldown(it.id)
        start, duration = ns.Util.plain(start), ns.Util.plain(duration)
        if start and duration and duration > 0 then b.cd:SetCooldown(start, duration) else b.cd:Clear() end
      end
      local inRange = true
      if target and C_Item and C_Item.IsItemInRange then
        local r = ns.Util.plain(C_Item.IsItemInRange(it.id, "target"))
        inRange = r ~= false
      end
      if inRange then b.icon:SetVertexColor(1, 1, 1) else b.icon:SetVertexColor(1, 0.3, 0.3) end
      b.hotkey:SetText(binding(i))
    end
  end
end

-- Put the list on the buttons (not in combat: then when it ends).
function IB.Apply()
  if not bar then return end
  if combat() then IB.pending = true return end
  IB.pending = false
  local on = ns.db and ns.db.settings.itemBar
  local list = on and IB.list or {}
  for i, b in ipairs(buttons) do
    local it = list[i]
    b.item = it
    b:SetAttribute("item", it and ("item:" .. it.id) or nil)
    if it then b:Show() else b:Hide() end
  end
  local n = math.min(#list, #buttons)
  bar:SetWidth(math.max(1, n * IB.SIZE + (n - 1) * IB.GAP))
  if n > 0 then bar:Show() else bar:Hide() end
  IB.Paint()
end

-- The items for the current step and the quest log; the bar changes only when they do.
function IB.Update()
  local ds = ns.ActiveDataset and ns.ActiveDataset()
  if not ds or not ns.char then return end
  IB.list = ns.UseItems.List(ds, ns.char, ns.steps, ns.stepIndex, ns.UseItems.MAX)
  local key = (ns.db and ns.db.settings.itemBar and "on:" or "off:") .. ns.UseItems.Key(IB.list)
  if key ~= IB.key or IB.pending then
    IB.key = key
    IB.Apply()
  else
    IB.Paint()
  end
end

function IB.Reset()
  if ns.db then ns.db.itemBarPos = nil end
  if bar and not combat() then place() end
end

local waitFrame
function IB.Attach()
  if bar or not CreateFrame then return end
  if combat() then -- loaded in a fight (/reload): secure buttons only after it
    waitFrame = waitFrame or CreateFrame("Frame")
    waitFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    waitFrame:SetScript("OnEvent", function(f) f:UnregisterAllEvents(); IB.Attach(); IB.Update() end)
    return
  end
  bar = CreateFrame("Frame", "LvlsItemBar", UIParent)
  bar:SetSize(IB.SIZE, IB.SIZE)
  bar:SetMovable(true)
  if bar.SetClampedToScreen then bar:SetClampedToScreen(true) end
  place()
  bar:Hide()
  for i = 1, ns.UseItems.MAX do buttons[i] = newButton(i) end
  bar:RegisterEvent("PLAYER_REGEN_ENABLED")
  bar:RegisterEvent("BAG_UPDATE_COOLDOWN")
  bar:RegisterEvent("UPDATE_BINDINGS")
  bar:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
      if IB.pending then IB.Apply() end
    else
      IB.Paint()
    end
  end)
  local acc = 0
  bar:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + (elapsed or 0)
    if acc >= 0.25 then acc = 0; IB.Paint() end -- range to the target
  end)
end
IB.buttons = buttons

-- Key Bindings -> AddOns -> Lvls! (Bindings.xml)
BINDING_HEADER_LVLS = "Lvls!"
for i = 1, 4 do _G["BINDING_NAME_CLICK LvlsItemButton" .. i .. ":LeftButton"] = "Use quest item " .. i end

ns.commands.items = function(arg)
  local s = ns.db.settings
  arg = (arg or ""):lower()
  if arg == "lock" or arg == "unlock" then
    s.lockItemBar = arg == "lock"
    ns.Log("info", "item buttons " .. (s.lockItemBar and "locked" or "unlocked: drag one to move them"))
  elseif arg == "reset" then
    IB.Reset()
    ns.Log("info", "item buttons back in their place")
  else
    s.itemBar = not s.itemBar
    ns.Log("info", "item buttons " .. (s.itemBar and "on" or "off"))
  end
  IB.Update()
end

ns.Events.On("LVLS_LOADED", function() IB.Attach() end)
ns.Events.On("LVLS_UPDATED", function() IB.Update() end)

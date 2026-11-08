-- Group sync, the messages: members of a group who run Lvls! tell each other their
-- quest state, ask to catch up, and the one catching up tells the ones helping
-- where they are going.
-- API (forever 1.60.1, wow-ui-source branch forever, ChatInfoDocumentation):
--   C_ChatInfo.RegisterAddonMessagePrefix(prefix)
--   C_ChatInfo.SendAddonMessage(prefix, message, chatType, target) -> result
--     (Enum.SendAddonMessageResult: 0 Success, 3 AddonMessageThrottle,
--      8 ChannelThrottle, 11 AddOnMessageLockdown: sent again later)
--   CHAT_MSG_ADDON(prefix, text, channel, sender, ...); messages up to 255 bytes
--
-- Messages (prefix "LvlsSync"):
--   R                        please send your state
--   S|id|i|n|chunk           state (Engine/Sync.State) in n chunks
--   Q|name|count             I want to catch up with name (count quests)
--   F|name|on / off          I follow name's route / not any more
--   P|step                   where I am going now (Engine/Sync.StepText)
--   X                        my catch-up is over
local _, ns = ...
local GS = ns:NewModule("GroupSync")
local Sy = ns.Sync

GS.PREFIX = "LvlsSync"
GS.CHUNK = 220          -- characters of state per message
GS.PER_SECOND = 4       -- messages sent per second at most
GS.STATE_DELAY = 3      -- seconds to gather changes before the state goes out

GS.peers = {}           -- name -> { state, at, version = "ok" | reason }
GS.helpers = {}         -- names following my catch-up
GS.requests = {}        -- name -> count: members asking to catch up with me

local queue = {}
local incoming = {}     -- sender -> { id, n, parts = {} }
local stateDue          -- time the next state broadcast goes out
local lastStep          -- the step last sent to the members who follow
local sendId = 0

local function has(t, k) return type(t) == "table" and type(t[k]) == "function" end
local function now() return GetTime and GetTime() or 0 end

local function me() return UnitName and ns.Util.plain(UnitName("player")) or "?" end

local function short(name)
  if type(Ambiguate) == "function" then return Ambiguate(name, "none") end
  return (name or ""):match("^([^%-]+)") or name
end

local function channel()
  if type(IsInRaid) == "function" and IsInRaid() then return "RAID" end
  if type(IsInGroup) == "function" and IsInGroup() then return "PARTY" end
  return nil
end

function GS.Enabled() return ns.db and ns.db.settings.groupSync end

-- queue a message for the group; sent by GS.Flush
function GS.Send(msg)
  if not channel() then return end
  queue[#queue + 1] = msg
end

local RETRY = { [3] = true, [8] = true, [11] = true }
function GS.Flush()
  local ch = channel()
  if not ch then queue = {} return end
  if not has(C_ChatInfo, "SendAddonMessage") then return end
  for _ = 1, GS.PER_SECOND do
    local msg = queue[1]
    if not msg then return end
    local result = C_ChatInfo.SendAddonMessage(GS.PREFIX, msg, ch)
    if type(result) == "number" and RETRY[result] then return end -- throttled or locked down: later
    table.remove(queue, 1)
  end
end

-- my state, in chunks, soon
function GS.StateSoon() stateDue = now() + GS.STATE_DELAY end

function GS.SendState()
  local ds = ns.ActiveDataset()
  if not ds or not ns.char or not channel() then return end
  local s = Sy.State(ds, ns.char)
  sendId = sendId % 999 + 1
  local n = math.ceil(#s / GS.CHUNK)
  for i = 1, n do
    GS.Send(("S|%d|%d|%d|%s"):format(sendId, i, n, s:sub((i - 1) * GS.CHUNK + 1, i * GS.CHUNK)))
  end
end

-- members still in the group (others are forgotten)
function GS.Roster()
  local names = {}
  local n = type(GetNumGroupMembers) == "function" and GetNumGroupMembers() or 0
  local raid = type(IsInRaid) == "function" and IsInRaid()
  for i = 1, n do
    local unit = raid and ("raid" .. i) or ("party" .. i)
    local raw = UnitName and UnitName(unit)
    local name = ns.Util.plain(raw)
    if raw ~= nil and name == nil then return end -- names are secret now: nobody is dropped
    if name then names[short(name)] = true end
  end
  for name in pairs(GS.peers) do
    if not names[name] then GS.peers[name] = nil; GS.helpers[name] = nil; GS.requests[name] = nil; Sy.Forget(name) end
  end
  if ns.sync and not names[ns.sync.with] then
    ns.Log("info", ("%s left the group: sync over"):format(ns.sync.with))
    ns.SetSync(nil)
  end
end

local function onState(sender, id, i, n, chunk)
  local buf = incoming[sender]
  if not buf or buf.id ~= id then buf = { id = id, n = n, parts = {}, got = 0 }; incoming[sender] = buf end
  if not buf.parts[i] then buf.parts[i] = chunk; buf.got = buf.got + 1 end
  if buf.got < buf.n then return end
  incoming[sender] = nil
  local ds = ns.ActiveDataset()
  if not ds then return end
  local state, why = Sy.ParseState(ds, table.concat(buf.parts))
  local peer = GS.peers[sender] or {}
  GS.peers[sender] = peer
  peer.at = now()
  if not state then
    if peer.version ~= why then
      peer.version = why
      ns.Log("info", ("%s runs another version of Lvls! (%s differs): no sync with them until you both update"):format(sender, why))
    end
    peer.state = nil
    Sy.Forget(sender)
    return
  end
  peer.version, peer.state = "ok", state
  ns.Events.Fire("LVLS_PEERS", sender)
end

function GS.OnMessage(prefix, text, _, sender)
  if prefix ~= GS.PREFIX or not GS.Enabled() then return end
  sender = ns.Util.plain(sender)
  if type(sender) ~= "string" then return end
  sender = short(sender)
  if sender == me() then return end
  local kind, rest = text:match("^(%a)|?(.*)$")
  if kind == "R" then
    GS.StateSoon()
  elseif kind == "S" then
    local id, i, n, chunk = rest:match("^(%d+)|(%d+)|(%d+)|(.*)$")
    if id then onState(sender, tonumber(id), tonumber(i), tonumber(n), chunk) end
  elseif kind == "Q" then
    local who, count = rest:match("^([^|]+)|(%d+)$")
    if who == me() then
      GS.requests[sender] = tonumber(count)
      if ns.AskFollow then ns.AskFollow(sender, tonumber(count)) end
    end
  elseif kind == "F" then
    local who, on = rest:match("^([^|]+)|(%a+)$")
    if who == me() then
      GS.helpers[sender] = on == "on" or nil
      ns.Log("info", on == "on" and ("%s is helping you catch up"):format(sender) or ("%s stopped following"):format(sender))
      if on == "on" then lastStep = nil; if ns.Refresh then ns.Refresh() end end
    end
  elseif kind == "P" then
    if ns.sync and ns.sync.mode == "follow" and ns.sync.with == sender then
      ns.followStep = Sy.ParseStep(rest)
      if ns.Refresh then ns.Refresh(true) end
    end
  elseif kind == "X" then
    GS.requests[sender] = nil
    if ns.sync and ns.sync.mode == "follow" and ns.sync.with == sender then
      ns.Log("info", ("%s has caught up: back to your own route"):format(sender))
      ns.SetSync(nil)
    end
  end
end

-- what I am doing now, for the members who follow me (only when it changed)
function GS.SendStep(st)
  if not next(GS.helpers) then lastStep = nil return end
  local text = Sy.StepText(st)
  if text == lastStep then return end
  lastStep = text
  GS.Send("P|" .. text)
end

function GS.Tick()
  if not GS.Enabled() then return end
  if stateDue and now() >= stateDue then stateDue = nil; GS.SendState() end
  GS.Flush()
end

if CreateFrame then
  local f = CreateFrame("Frame")
  for _, e in ipairs({ "CHAT_MSG_ADDON", "GROUP_ROSTER_UPDATE", "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED",
    "PLAYER_LEVEL_UP", "PLAYER_LOGIN" }) do
    f:RegisterEvent(e)
  end
  f:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" and has(C_ChatInfo, "RegisterAddonMessagePrefix") then
      C_ChatInfo.RegisterAddonMessagePrefix(GS.PREFIX)
    end
    if not GS.Enabled() then return end
    if event == "CHAT_MSG_ADDON" then
      local ok, err = pcall(GS.OnMessage, ...)
      if not ok then ns.Log("debug", "sync: " .. tostring(err)) end
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_LOGIN" then
      GS.Roster()
      if channel() then GS.Send("R"); GS.StateSoon() end
    else
      GS.StateSoon()
    end
  end)
  local acc = 0
  f:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + (elapsed or 0)
    if acc >= 1 then acc = 0; GS.Tick() end
  end)
end

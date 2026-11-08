-- How a pin looks, and the tooltip lines for a quest. Shared by the world map and
-- the minimap. Atlases are the client's own (seen in the forever UI source).
local _, ns = ...
local S = ns:NewModule("Style")

S.PINS = {
  available = { atlas = "QuestNormal", size = 18 },
  low       = { atlas = "QuestNormal", size = 14, desaturate = true, alpha = 0.7 },
  trivial   = { atlas = "TrivialQuests", size = 14, alpha = 0.8 },
  turnin    = { atlas = "QuestTurnin", size = 18 },
  progress  = { atlas = "QuestTurnin", size = 14, desaturate = true, alpha = 0.8 },
  objective = { atlas = "ui-questtracker-objective-nub", size = 10 },
  route     = { atlas = "QuestNormal", size = 22 },
}

-- Distinct, readable colours for objective dots, by quest.
local PALETTE = {
  { 1, 0.82, 0 }, { 0.3, 0.8, 1 }, { 1, 0.45, 0.3 }, { 0.6, 1, 0.4 }, { 0.9, 0.5, 1 },
  { 1, 1, 1 }, { 0.4, 1, 0.9 }, { 1, 0.65, 0.8 },
}
function S.QuestColor(qid)
  return PALETTE[(qid % #PALETTE) + 1]
end

function S.Apply(tex, pin)
  local st = S.PINS[pin.type] or S.PINS.available
  if tex.SetAtlas then tex:SetAtlas(st.atlas) end
  if tex.SetDesaturated then tex:SetDesaturated(st.desaturate and true or false) end
  if tex.SetAlpha then tex:SetAlpha(st.alpha or 1) end
  if tex.SetVertexColor then
    if pin.type == "objective" then
      local c = S.QuestColor(pin.quest)
      tex:SetVertexColor(c[1], c[2], c[3])
    else
      tex:SetVertexColor(1, 1, 1)
    end
  end
  return st.size
end

local STATUS_TEXT = {
  available = "Available", low = "Not yet: ", trivial = "Grey (little experience)",
  turnin = "Ready to turn in", progress = "In progress", locked = "Locked: ",
}

-- Tooltip lines { text, r, g, b } for a pin. Pure: char and dataset handed in.
function S.TooltipLines(ds, char, pin)
  local q = ds.quests[pin.quest]
  if not q then return {} end
  local A = ns.Availability
  local lines = {}
  local diff = A.COLORS[A.Difficulty(q.l, char.level)]
  lines[#lines + 1] = { ("[%s] %s"):format(q.l or "?", q.n), diff[1], diff[2], diff[3] }
  if pin.type == "objective" then
    local o = q.obj and q.obj[pin.index]
    if o then
      local entry = char.active and char.active[pin.quest]
      local lo = ns.Quests.LogObjective(entry, o, pin.index)
      lines[#lines + 1] = { lo and lo.text or ((o.text or "?") .. (o.qty and o.qty > 1 and (" x" .. o.qty) or "")), 1, 1, 1 }
    end
    local rec = (pin.kind == "o" and ds.objects or ds.npcs)[pin.id]
    if rec and rec.n then
      local how = pin.vendor and "Sold by " or ""
      local pct = pin.pct and pin.pct > 0 and (" (%d%%)"):format(pin.pct) or ""
      lines[#lines + 1] = { how .. rec.n .. pct, 0.7, 0.7, 0.7 }
    end
    return lines
  end
  local st = pin.type
  local _, reason = A.Status(q, char)
  local text = STATUS_TEXT[st] or st
  if st == "low" then text = text .. "requires level " .. (q.r or "?") end
  lines[#lines + 1] = { text, 0.8, 0.8, 0.8 }
  if reason and st ~= "low" then lines[#lines + 1] = { reason, 0.6, 0.6, 0.6 } end
  local rec = (pin.kind == "o" and ds.objects or ds.npcs)[pin.id]
  if rec and rec.n then lines[#lines + 1] = { rec.n, 0.7, 0.7, 0.7 } end
  if q.xp and (st == "available" or st == "low" or st == "turnin" or st == "progress") then
    lines[#lines + 1] = { ("%d xp"):format(ns.Route.QuestXP(q, char.level)), 0.6, 0.8, 1 }
  end
  if q.kind then lines[#lines + 1] = { q.kind:gsub("^%l", string.upper), 1, 0.5, 0.25 } end
  return lines
end

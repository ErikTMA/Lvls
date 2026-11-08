-- In-process message bus (pure). Game events are bridged in by Adapters/Game.lua.
local _, ns = ...
local E = ns:NewModule("Events")

local handlers = {}

function E.On(msg, fn)
  handlers[msg] = handlers[msg] or {}
  table.insert(handlers[msg], fn)
  return fn
end

function E.Off(msg, fn)
  local list = handlers[msg]
  if not list then return end
  for i = #list, 1, -1 do
    if list[i] == fn then table.remove(list, i) end
  end
end

function E.Fire(msg, ...)
  local list = handlers[msg]
  if not list then return end
  for i = 1, #list do
    local ok, err = pcall(list[i], ...)
    if not ok and ns.Log then ns.Log("error", "handler for " .. msg .. ": " .. tostring(err)) end
  end
end

function E.Reset() handlers = {} end

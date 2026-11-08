-- Lvls! namespace. Every file receives (addonName, ns) from the client's loader.
local ADDON, ns = ...

ns.name = ADDON or "Lvls"
ns.displayName = "Lvls!"
ns.modules = ns.modules or {}
ns.commands = ns.commands or {} -- /lvls subcommands; UI modules add theirs at load

-- One global handle for slash commands, other addons and /dump debugging.
_G.Lvls = ns

function ns:NewModule(name)
  assert(type(name) == "string" and name ~= "", "module name required")
  assert(not self.modules[name], "duplicate module: " .. name)
  local m = { name = name }
  self.modules[name] = m
  self[name] = m
  return m
end

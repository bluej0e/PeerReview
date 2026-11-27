-- Minimal WoW client stand-in for logic tests.
NOW, CLOCK = 1000, 1795000000
function GetTime() return NOW end
function time() return CLOCK end
PRINTS = {}
local rawprint = print
function print(...) local t = {} for i = 1, select("#", ...) do t[#t+1] = tostring(select(i, ...)) end PRINTS[#PRINTS+1] = table.concat(t, " ") end
function LOG(...) rawprint(...) end
timers = {}
C_Timer = { After = function(d, f) timers[#timers+1] = { at = NOW + d, f = f } end,
  NewTicker = function(d, f) timers[#timers+1] = { at = NOW + d, f = f, every = d } end }
function Advance(secs, step)
  step = step or 1
  local stop = NOW + secs
  while NOW < stop do
    NOW = NOW + step; CLOCK = CLOCK + step
    local i = 1
    while i <= #timers do
      local t = timers[i]
      if t.at <= NOW then
        if t.every then t.at = t.at + t.every; i = i + 1 else table.remove(timers, i) end
        t.f()
      else i = i + 1 end
    end
  end
end
local widget = {}
widget.__index = function(t, k)
  if k == "GetUnit" then return nil end
  return function(self, ...)
    if k == "CreateFontString" or k == "CreateTexture" then return setmetatable({}, widget) end
    if k == "IsShown" then return rawget(self, "_shown") or false end
    if k == "Show" then rawset(self, "_shown", true) return end
    if k == "Hide" then rawset(self, "_shown", false) return end
    if k == "SetShown" then rawset(self, "_shown", (...) and true or false) return end
    if k == "SetScript" or k == "HookScript" then local n, f = ...; rawset(self, "_" .. n, f) return end
    if k == "GetParent" then return rawget(self, "_parent") end
    if k == "SetText" then rawset(self, "_text", (...)) return end
    if k == "GetPoint" then return "CENTER", nil, "CENTER", 0, 0 end
    if k == "GetWidth" then return 140 end
    if k == "GetCenter" then return 0, 0 end
    if k == "GetEffectiveScale" then return 1 end
    if k == "RegisterEvent" then EVENTS = EVENTS or {}; EVENTS[(...)] = EVENTS[(...)] or {}; table.insert(EVENTS[(...)], self) return end
  end
end
function CreateFrame(kind, name, parent) local f = setmetatable({ _parent = parent }, widget); if name then _G[name] = f end return f end
function Fire(event, ...) for _, f in ipairs((EVENTS or {})[event] or {}) do f._OnEvent(f, event, ...) end end
UIParent, Minimap, GameTooltip = CreateFrame("Frame"), CreateFrame("Frame"), CreateFrame("Frame")
UISpecialFrames = {}
SOUNDKIT = {}
function PlaySound() end
function InCombatLockdown() return COMBAT or false end
FIGHT = true
function UnitAffectingCombat() return FIGHT end
ERR_TRADE_COMPLETE = "Trade complete."
RAID_CLASS_COLORS = { MAGE = { r = .2, g = .8, b = 1 } }
-- world state
GROUP, INSTANCE, GUILDMATES, FRIENDS = {}, false, {}, {}
function IsInGroup() return #GROUP > 0 end
function IsInRaid() return false end
function IsInGuild() return true end
function GetNumGroupMembers() return #GROUP + 1 end
function UnitExists(u) if u == "player" then return true end local i = tonumber(u:match("^party(%d)$")); return i and GROUP[i] ~= nil or false end
function UnitFullName(u) if u == "player" then return "Rodrigo", "Azeroth" end local i = tonumber(u:match("^party(%d)$")); local g = i and GROUP[i]; if g then return g[1], g[2] end end
function UnitClass(u) return "Mage", "MAGE" end
function UnitGUID(u) local i = tonumber(u:match("^party(%d)$")); local g = i and GROUP[i]; return g and ("Player-1-" .. g[1]) end
function UnitIsInMyGuild(u) local i = tonumber(u:match("^party(%d)$")); local g = i and GROUP[i]; return g and GUILDMATES[g[1]] or false end
function UnitIsPlayer() return true end
function IsInInstance() return INSTANCE, INSTANCE and "party" or "none" end
function GetNormalizedRealmName() return "Azeroth" end
function GetChannelName() return 0 end
function JoinTemporaryChannel() end
SENT, IGNORED = {}, {}
C_ChatInfo = { SendAddonMessage = function(p, text, chan, target) SENT[#SENT+1] = { text = text, chan = chan, target = target } return 0 end,
  RegisterAddonMessagePrefix = function() return true end }
C_FriendList = { IsFriend = function(guid) return FRIENDS[guid] or false end, AddIgnore = function(n) IGNORED[#IGNORED+1] = n end }
function hooksecurefunc() end
SlashCmdList = {}

FILTERS = {}
function ChatFrame_AddMessageEventFilter(ev, f) FILTERS[ev] = FILTERS[ev] or {}; table.insert(FILTERS[ev], f) end
ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."

LEVELS, MYLEVEL = {}, 42
function UnitLevel(u) if u == "player" then return MYLEVEL end local i = tonumber(u:match("^party(%d)$")); local g = i and GROUP[i]; return g and (LEVELS[g[1]] or 40) or 0 end

REGIONAL, MYNAME = false, "Rodrigo"
function GetUnitName(u, showRealm)
  if u == "player" then return MYNAME end
  if u == "NPC" then return GROUP_NPC end
  local i = tonumber(u:match("^party(%d)$")); local g = i and GROUP[i]
  if not g then return nil end
  if REGIONAL then return g[1] end
  if showRealm and g[2] ~= "" then return g[1] .. "-" .. g[2] end
  return g[1]
end
function UnitName(u) return GetUnitName(u) end
function Leave() GROUP = {}; Fire("GROUP_ROSTER_UPDATE"); Advance(6) end

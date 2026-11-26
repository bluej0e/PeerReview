-- Peer Review: core (saved data, group tracking, votes, scores, events, slash commands)
local ADDON, ns = ...

-- The version comes from the .toc file; the constant is only a fallback.
ns.VERSION = "0.8.0"
do
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local ok, v = pcall(function() return get and get(ADDON, "Version") end)
  v = ok and type(v) == "string" and v:match("^v?(%d+%.%d+%.%d+)") or nil
  if v then ns.VERSION = v end
end
ns.PREFIX = "PeerReview"
ns.PROTO = 1
ns.EXPIRE = 180 * 86400   -- votes older than this stop counting
ns.MIN_RATERS = 3         -- community score stays hidden below this many voters
ns.MIN_LEVEL = 20         -- both the voter and the rated player must be at least this level
ns.STEPS = { 0, 5, 10, 15, 20, 30, 45, 60 }
ns.MAX_TAGS = 3
-- Reasons a voter can attach. Fixed lists only (no free text); each is sent as one letter a-f.
ns.TAGS = {
  [1] = { "Friendly", "Helpful", "Skilled", "Good leader", "Fair loot", "Fun" },
  [0] = { "Just okay", "Quiet", "Inexperienced", "Slow", "Bit rude", "Carried" },
  [-1] = { "Ninja", "Toxic", "Left early", "AFK", "Reckless", "Poor play" },
}
ns.LETTERS = "abcdef"
local I = "Interface\\Icons\\"
ns.TAG_ICONS = {
  [1] = { I .. "INV_Misc_Gift_01", I .. "Spell_Holy_LayOnHands", I .. "Ability_DualWield", I .. "INV_Crown_01",
    I .. "INV_Misc_Coin_01", I .. "INV_Drink_04" },
  [0] = { I .. "INV_Misc_QuestionMark", I .. "Spell_Holy_Silence", I .. "INV_Misc_Book_09",
    I .. "INV_Misc_PocketWatch_01", I .. "Ability_Creature_Cursed_02", I .. "INV_Misc_Bag_08" },
  [-1] = { I .. "Ability_Stealth", I .. "Spell_Nature_CorrosiveBreath", I .. "Spell_Arcane_Blink",
    I .. "Spell_Nature_Sleep", I .. "Ability_Warrior_Charge", I .. "INV_Misc_Bone_HumanSkull_01" },
}

local DEFAULTS = {
  settings = {
    minMinutes = 30,      -- time grouped with a player before they can be rated
    instanceOnly = false, -- only ask about players met inside a dungeon or raid
    bossCounts = true,    -- a boss kill together always qualifies
    reask = false,        -- ask again about players already rated
    skipFriends = true,   -- never ask about players on my friends list
    skipGuild = true,     -- never ask about guildmates
    sound = true, tooltip = true, warn = true,
    sync = true, channel = false,
    ignoreDown = false,   -- thumbs down also puts the player on the ignore list
  },
  my = {},        -- [key] = { v = 1|-1, t = time, name = "Name-Realm", class = "MAGE" }
  votes = {},     -- [targetKey] = { [raterKey] = { v = 1|-1, t = time } }
  raterMax = {},  -- [raterKey] = newest vote time held from that rater
  raterCount = {},
  muted = {},     -- [key] = true: "never ask me about this player"
  pending = {},   -- [key] = { name, class, secs, boss, t }: skipped in the popup, can be reopened for a day
  synced = {},    -- [raterKey] = last time we asked them for their votes
  lvl = {},       -- [key] = { l = level, t = time }: levels this client saw with its own eyes in a group
  seen = {},      -- [raterKey] = { t = time, n = "Name-Realm" }: Peer Review users heard from directly
  session = { mates = {}, t = 0 },
  minimapAngle = 195,
}

local function Merge(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      Merge(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end

function ns.Print(msg)
  print("|cff61d97aPeer Review|r: " .. tostring(msg))
end

function ns.IsSecret(v)
  return issecretvalue ~= nil and issecretvalue(v) == true
end

local function Str(v)
  if v == nil or ns.IsSecret(v) or type(v) ~= "string" or v == "" then return nil end
  return v
end

function ns.Realm()
  if ns.realm then return ns.realm end
  local r = GetNormalizedRealmName and Str(GetNormalizedRealmName())
  if not r and GetRealmName then
    r = Str(GetRealmName())
    if r then r = r:gsub("[%s%-]", "") end
  end
  if r and r ~= "" then ns.realm = r end
  return r or ""
end

-- WoW: Forever names players "First Last" and the name is unique across the region, so the
-- name alone identifies a player there. Other clients need "Name-Realm".
function ns.Regional()
  if type(RegionalUniqueNamesEnabled) ~= "function" then return false end
  local ok, on = pcall(RegionalUniqueNamesEnabled)
  return ok and on == true
end

-- Any spelling of a player name -> whisper form ("Name-Realm"), lookup key, bare name.
-- Handles "First Last", "First Last-Realm", "Name-Realm" and trailing ":id" suffixes.
function ns.Full(name, realm)
  name = Str(name)
  if not name then return nil end
  name = name:gsub(":.*$", "")
  name = name:gsub("%s*%(%*%)$", "")
  name = name:gsub("^%s+", "")
  name = name:gsub("%s+$", "")
  name = name:gsub("%s%s+", " ")
  local base, suffix = name:match("^(.-)%-([^%-]+)$")
  if base and base ~= "" then name, realm = base, suffix end
  if name == "" then return nil end
  realm = Str(realm)
  if realm then realm = realm:gsub("[%s%-]", "") end
  if not realm or realm == "" then realm = ns.Realm() end
  local full = realm ~= "" and (name .. "-" .. realm) or name
  if ns.Regional() then return full, name:lower(), name end
  if realm == "" then return nil end
  return full, full:lower(), name
end

-- Name shown to the player: realm suffix removed where it adds nothing.
function ns.Short(full)
  if type(full) ~= "string" then return "?" end
  local n, r = full:match("^(.-)%-([^%-]+)$")
  if not n or n == "" then return full end
  if ns.Regional() or r:lower() == ns.Realm():lower() then return n end
  return full
end

local function UnitFull(unit)
  if not UnitExists then return nil end
  local regional = ns.Regional()
  local name
  if GetUnitName then
    -- Forever: the plain call already returns the full "First Last" name.
    local ok, n
    if regional then ok, n = pcall(GetUnitName, unit) else ok, n = pcall(GetUnitName, unit, true) end
    if ok then name = Str(n) end
  end
  if not name and UnitName then
    local ok, first, second = pcall(UnitName, unit)
    if ok then
      first, second = Str(first), Str(second)
      if first and second then
        local seps = Constants and Constants.CharacterNameSeparatorConsts
        local sep = regional and (seps and seps.CHARACTERNAME_SURNAME_SEPARATOR or " ") or "-"
        name = first .. sep .. second
      else
        name = first
      end
    end
  end
  if not name or name == UNKNOWNOBJECT then return nil end
  return ns.Full(name)
end
ns.UnitFull = UnitFull

---------------------------------------------------------------- levels
local function Level(unit)
  if not UnitLevel then return nil end
  local ok, l = pcall(UnitLevel, unit)
  if not ok or ns.IsSecret(l) or type(l) ~= "number" or l < 1 then return nil end
  return l
end
function ns.MyLevel() return Level("player") end

-- Level seen first-hand within the last two weeks, or nil when unknown.
function ns.SeenLevel(key)
  local e = ns.db.lvl[key]
  if e and e.t >= time() - 14 * 86400 then return e.l end
  return nil
end

-- True only when this client has itself seen the player below the minimum level.
function ns.TooLow(key)
  local l = ns.SeenLevel(key)
  return l ~= nil and l < ns.MIN_LEVEL
end

---------------------------------------------------------------- votes and scores
-- A vote record is live when it is an up (1), neutral (0) or down (-1). A removed vote stays as
-- a marker (v = "x") so the removal can be passed on to players who already hold the old vote.
local function Live(r)
  return type(r) == "table" and (r.v == 1 or r.v == 0 or r.v == -1)
end
ns.Live = Live

function ns.Vote(key, v, info)
  if not key or (v ~= 1 and v ~= -1 and v ~= 0) then return end
  if info and info.fake then return end
  local db = ns.db
  local mine = ns.MyLevel()
  if mine and mine < ns.MIN_LEVEL then
    ns.Print(("votes count from level %d. You are level %d."):format(ns.MIN_LEVEL, mine))
    return
  end
  if ns.TooLow(key) then
    ns.Print(("players under level %d cannot be rated."):format(ns.MIN_LEVEL))
    return
  end
  db.my[key] = { v = v, t = time(), name = info and info.name or key, class = info and info.class or nil }
  db.pending[key] = nil
  ns.Sync.PublishVote(key)
  if v == -1 and db.settings.ignoreDown and C_FriendList and C_FriendList.AddIgnore then
    pcall(C_FriendList.AddIgnore, ns.Regional() and ns.Short(db.my[key].name) or db.my[key].name)
  end
  return true
end

-- Take a vote back. Other players drop it the next time they hear from you.
function ns.Unvote(key)
  local r = ns.db.my[key]
  if not Live(r) then return end
  ns.db.my[key] = { v = "x", t = time(), name = r.name, class = r.class }
  ns.Sync.PublishVote(key)
end

-- Your own live votes, newest first.
function ns.MyList()
  local list = {}
  for key, r in pairs(ns.db.my) do
    if Live(r) then list[#list + 1] = { key = key, name = r.name or key, class = r.class, v = r.v, g = r.g, t = r.t } end
  end
  table.sort(list, function(a, b) return a.t > b.t end)
  return list
end

-- "Friendly, Skilled" for a vote's reason letters.
function ns.ReasonText(v, letters)
  if not letters or not ns.TAGS[v] then return "" end
  local words = {}
  for ch in letters:gmatch("[a-f]") do words[#words + 1] = ns.TAGS[v][ns.LETTERS:find(ch, 1, true)] end
  return table.concat(words, ", ")
end

-- Attach up to three reason letters ("ace") to a vote already cast.
function ns.SetTags(key, letters)
  local r = ns.db.my[key]
  if not Live(r) or type(letters) ~= "string" then return end
  letters = letters:gsub("[^a-f]", ""):sub(1, ns.MAX_TAGS)
  if letters == (r.g or "") then return end
  r.g = letters ~= "" and letters or nil
  r.t = time()
  ns.Sync.PublishVote(key)
end

-- "Friendly 8, Skilled 5" style line built from the reasons on counted votes; nil when there are none.
-- A neutral or negative reason needs two voters to agree before it is shown, unless it is your own.
function ns.TagLine(key)
  if not key then return nil end
  local db, cutoff = ns.db, time() - ns.EXPIRE
  local count = { [1] = {}, [0] = {}, [-1] = {} }
  local own = {}
  local function add(r, mine)
    if not r.g or not Live(r) then return end
    for ch in r.g:gmatch("[a-f]") do
      local i = ns.LETTERS:find(ch, 1, true)
      count[r.v][i] = (count[r.v][i] or 0) + 1
      if mine then own[r.v .. ch] = true end
    end
  end
  local set = db.votes[key]
  if set then
    for rater, r in pairs(set) do
      if r.t >= cutoff and not ns.TooLow(rater) and not ns.Discounted(rater, r) then add(r) end
    end
  end
  local mine = db.my[key]
  if mine and mine.t >= cutoff then add(mine, true) end
  local parts = {}
  for _, v in ipairs({ 1, 0, -1 }) do
    local list = {}
    for i, n in pairs(count[v]) do
      if v == 1 or n >= 2 or own[v .. ns.LETTERS:sub(i, i)] then list[#list + 1] = { i = i, n = n } end
    end
    table.sort(list, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.i < b.i end)
    local words = {}
    for j = 1, math.min(#list, 3) do
      words[#words + 1] = ("|T%s:13:13:0:0:64:64:5:59:5:59|t %s %d"):format(ns.TAG_ICONS[v][list[j].i], ns.TAGS[v][list[j].i], list[j].n)
    end
    if #words > 0 then
      parts[#parts + 1] = (v == 1 and "|cff61d97a" or v == 0 and "|cffffd140" or "|cffff6154") .. table.concat(words, ", ") .. "|r"
    end
  end
  if #parts == 0 then return nil end
  return table.concat(parts, "  ")
end

-- Index of every received vote by rater, rebuilt only after new votes arrive.
local index
function ns.Dirty() index = nil end
local function Index()
  if index then return index end
  index = {}
  for _, set in pairs(ns.db.votes) do
    for rater, r in pairs(set) do
      local e = index[rater]
      if Live(r) then
        if not e then e = { up = 0, down = 0, list = {} }; index[rater] = e end
        if r.v == -1 then e.down = e.down + 1 else e.up = e.up + 1 end -- neutral counts as "not a thumbs down"
        e.list[#e.list + 1] = r
      end
    end
  end
  return index
end

-- A thumbs down is left out of the score when it looks like rage voting:
--   * the rater thumbed down 3 or more players within 10 minutes and nobody up (a whole group at once), or
--   * the rater has 8 or more votes and at least 85% of them are thumbs down.
function ns.Discounted(rater, r)
  if r.v ~= -1 then return false end
  local e = Index()[rater]
  if not e then return false end
  local total = e.up + e.down
  if total >= 8 and e.down / total >= 0.85 then return true end
  local near, praise = 0, false
  for _, o in ipairs(e.list) do
    if math.abs(o.t - r.t) <= 600 then
      if o.v == -1 then near = near + 1 else praise = true end
    end
  end
  return near >= 3 and not praise
end

-- up, down, myVote (1, 0, -1 or nil), neutral. Expired and rage votes are left out.
-- Neutral votes are counted on their own and never move the percentage.
function ns.Score(key)
  local db, up, down, mid = ns.db, 0, 0, 0
  local cutoff = time() - ns.EXPIRE
  local set = db.votes[key]
  if set then
    for rater, r in pairs(set) do
      if Live(r) and r.t >= cutoff and not ns.TooLow(rater) and not ns.Discounted(rater, r) then
        if r.v == 1 then up = up + 1 elseif r.v == -1 then down = down + 1 else mid = mid + 1 end
      end
    end
  end
  local mine = db.my[key]
  local mv = nil
  if Live(mine) and mine.t >= cutoff then
    mv = mine.v
    if mv == 1 then up = up + 1 elseif mv == -1 then down = down + 1 else mid = mid + 1 end
  end
  return up, down, mv, mid
end

-- Coloured one-line summary for tooltips and chat; nil when nothing is known.
function ns.Summary(key)
  if not key then return nil end
  local up, down, mv, mid = ns.Score(key)
  local total = up + down
  if total + mid == 0 then return nil end
  local parts = {}
  if total >= ns.MIN_RATERS then
    local pct = math.floor(up / total * 100 + 0.5)
    local col = pct >= 75 and "61d97a" or pct >= 50 and "ffd140" or "ff6154"
    parts[#parts + 1] = ("|cff%s%d%% would group again|r |cff9499a6(%d votes%s)|r"):format(col, pct, total,
      mid > 0 and (", " .. mid .. " neutral") or "")
  elseif not mv or total + mid > 1 then
    local all = total + mid
    parts[#parts + 1] = ("|cff9499a6%d vote%s so far, %d up or down needed for a score|r"):format(all, all == 1 and "" or "s", ns.MIN_RATERS)
  end
  if mv then
    parts[#parts + 1] = mv == 1 and "|cff61d97ayou: thumbs up|r" or mv == -1 and "|cffff6154you: thumbs down|r"
      or "|cffffd140you: neutral|r"
  end
  return table.concat(parts, "  ")
end

local function Prune()
  local db = ns.db
  local cutoff = time() - ns.EXPIRE
  local counts, maxes = {}, {}
  for target, set in pairs(db.votes) do
    local any = false
    for rater, r in pairs(set) do
      if type(r) ~= "table" or type(r.t) ~= "number" or r.t < cutoff then
        set[rater] = nil
      else
        any = true
        counts[rater] = (counts[rater] or 0) + 1
        if r.t > (maxes[rater] or 0) then maxes[rater] = r.t end
      end
    end
    if not any then db.votes[target] = nil end
  end
  db.raterCount, db.raterMax = counts, maxes
  ns.Dirty()
  for key, r in pairs(db.my) do
    if type(r) ~= "table" or type(r.t) ~= "number" or r.t < cutoff then db.my[key] = nil end
  end
  for key, e in pairs(db.pending) do
    if type(e) ~= "table" or type(e.t) ~= "number" or e.t < time() - 86400 then db.pending[key] = nil end
  end
  for key, e in pairs(db.lvl) do
    if type(e) ~= "table" or type(e.t) ~= "number" or e.t < time() - 14 * 86400 then db.lvl[key] = nil end
  end
  for key, e in pairs(db.seen) do
    if type(e) ~= "table" or type(e.t) ~= "number" or e.t < time() - 30 * 86400 then db.seen[key] = nil end
  end
  for key, t in pairs(db.synced) do
    if type(t) ~= "number" or t < time() - 30 * 86400 then db.synced[key] = nil end
  end
end

function ns.Mute(key)
  if key then ns.db.muted[key] = true; ns.db.pending[key] = nil end
end

-- Players skipped in the popup stay available for a day (/peer pending).
function ns.Park(it)
  if not it or it.fake or not it.key or Live(ns.db.my[it.key]) then return end
  ns.db.pending[it.key] = { name = it.name, class = it.class, secs = it.secs, boss = it.boss, t = time() }
end

function ns.PendingList()
  local list, cutoff = {}, time() - 86400
  for key, e in pairs(ns.db.pending) do
    if e.t >= cutoff and not Live(ns.db.my[key]) and not ns.db.muted[key] then
      list[#list + 1] = { key = key, name = e.name, class = e.class, secs = e.secs or 0, boss = e.boss }
    end
  end
  table.sort(list, function(a, b) return a.secs > b.secs end)
  return list
end

function ns.Counts()
  local mine, players = 0, 0
  for _, r in pairs(ns.db.my) do if Live(r) then mine = mine + 1 end end
  for _ in pairs(ns.db.votes) do players = players + 1 end
  return mine, players
end

---------------------------------------------------------------- group tracking
local T = { present = {}, warned = {} }
ns.Tracker = T

-- Home groups and instance (finder) groups are separate categories on this client; check both.
local function Check(fn, ...)
  if type(fn) ~= "function" then return false end
  local ok, v = pcall(fn, ...)
  return ok and not ns.IsSecret(v) and v and true or false
end
local function InRaid()
  return Check(IsInRaid) or (LE_PARTY_CATEGORY_INSTANCE ~= nil and Check(IsInRaid, LE_PARTY_CATEGORY_INSTANCE))
end
function ns.Grouped()
  return InRaid() or Check(IsInGroup) or (LE_PARTY_CATEGORY_INSTANCE ~= nil and Check(IsInGroup, LE_PARTY_CATEGORY_INSTANCE))
end

local function GroupUnits()
  local units = {}
  local raid = InRaid()
  if raid then
    local n = GetNumGroupMembers and GetNumGroupMembers() or 40
    if type(n) ~= "number" or n > 40 then n = 40 end
    for i = 1, n do units[#units + 1] = "raid" .. i end
  else
    for i = 1, 4 do units[#units + 1] = "party" .. i end
  end
  return units
end

-- Friends list (character or Battle.net) and guild membership, read while the player is in the group.
local function Relations(unit, m)
  local ok, guid = pcall(UnitGUID, unit)
  if ok and guid and not ns.IsSecret(guid) then
    local friend = false
    if C_FriendList and C_FriendList.IsFriend then
      local ok2, f = pcall(C_FriendList.IsFriend, guid)
      if ok2 and f == true then friend = true end
    end
    if not friend and C_BattleNet and C_BattleNet.GetAccountInfoByGUID then
      local ok2, info = pcall(C_BattleNet.GetAccountInfoByGUID, guid)
      if ok2 and type(info) == "table" and info.isFriend then friend = true end
    end
    m.friend = friend or nil
  end
  if UnitIsInMyGuild then
    local ok2, g = pcall(UnitIsInMyGuild, unit)
    if ok2 and not ns.IsSecret(g) then m.guild = g and true or nil end
  end
end

local function InDungeon()
  if not IsInInstance then return false end
  local ok, inside, kind = pcall(IsInInstance)
  if not ok or ns.IsSecret(inside) or ns.IsSecret(kind) then return false end
  return inside and (kind == "party" or kind == "raid" or kind == "scenario") or false
end

local function Eligible(key, m)
  local s = ns.db.settings
  if ns.db.muted[key] then return false end
  local mine = ns.MyLevel()
  if (mine and mine < ns.MIN_LEVEL) or ns.TooLow(key) then return false end
  if s.skipFriends and m.friend then return false end
  if s.skipGuild and m.guild then return false end
  if s.instanceOnly and (m.inst or 0) < 30 then return false end
  if not s.reask and Live(ns.db.my[key]) then return false end
  if (m.secs or 0) >= (s.minMinutes or 0) * 60 then return true end
  if s.bossCounts and m.boss then return true end
  return false
end
ns.Eligible = Eligible

-- Everyone from the current session as a list for the rating window.
function ns.SessionList(all)
  local list = {}
  for key, m in pairs(ns.db.session.mates) do
    if all or Eligible(key, m) then
      list[#list + 1] = { key = key, name = m.name, class = m.class, secs = m.secs or 0, boss = m.boss,
        friend = m.friend, guild = m.guild }
    end
  end
  table.sort(list, function(a, b) return a.secs > b.secs end)
  return list
end

local function Finish()
  local ses = ns.db.session
  local fresh = (time() - (ses.t or 0)) < 900
  local list = fresh and ns.SessionList(false) or {}
  ses.mates, ses.t = {}, 0
  T.present, T.warned = {}, {}
  if #list > 0 and ns.UI and ns.UI.ShowRate then ns.UI.ShowRate(list) end
end

local function Warn(key, m)
  if not ns.db.settings.warn or T.warned[key] then return end
  T.warned[key] = true
  local up, down, mv = ns.Score(key)
  local total = up + down
  local bad = mv == -1 or (mv ~= 1 and total >= ns.MIN_RATERS and up / total < 0.5)
  if bad then
    local why = ns.TagLine(key)
    ns.Print(("heads up, |cffffffff%s|r is in your group: %s%s"):format(ns.Short(m.name), ns.Summary(key) or "",
      why and ("  " .. why) or ""))
  end
end

function T.Scan()
  if not ns.db or not T.ready then return end
  local now = GetTime()
  local dt = math.min(now - (T.last or now), 15)
  T.last = now
  local ses = ns.db.session
  if ns.Grouped() then
    T.leftAt = nil
    local inst = InDungeon()
    local seen = {}
    for _, unit in ipairs(GroupUnits()) do
      if UnitExists(unit) then
        local full, key = UnitFull(unit)
        if key and key ~= ns.me then
          local m = ses.mates[key]
          if not m then
            local class
            local ok, _, file = pcall(UnitClass, unit)
            if ok then class = Str(file) end
            m = { name = full, class = class, secs = 0, inst = 0 }
            ses.mates[key] = m
            if ns.Sync.OnGroupChange then ns.Sync.OnGroupChange() end
          end
          if T.present[key] then
            m.secs = m.secs + dt
            if inst then m.inst = (m.inst or 0) + dt end
          end
          Relations(unit, m)
          local l = Level(unit)
          if l then ns.db.lvl[key] = { l = l, t = time() } end
          seen[key] = true
          Warn(key, m)
        end
      end
    end
    T.present = seen
    ses.t = time()
    T.was = true
  elseif T.was then
    -- Loading screens can report "not grouped" for a moment. Only believe it after 4 seconds.
    if not T.leftAt then
      T.leftAt = now
      C_Timer.After(4.2, function() pcall(T.Scan) end)
    end
    if now - T.leftAt >= 4 then
      T.was, T.leftAt = false, nil
      Finish()
    end
  elseif next(ses.mates) then
    Finish() -- a session left over from before a reload or disconnect
  end
end

local function BossDown()
  for key in pairs(T.present) do
    local m = ns.db.session.mates[key]
    if m then m.boss = true end
  end
end

---------------------------------------------------------------- events
local function InitDB()
  PeerReviewDB = PeerReviewDB or {}
  ns.db = PeerReviewDB
  Merge(ns.db, DEFAULTS)
  if type(ns.db.session.mates) ~= "table" then ns.db.session.mates = {} end
  if (ns.db.schema or 1) < 2 then ns.db.settings.channel = false; ns.db.schema = 2 end
  if ns.db.schema < 3 then
    -- 0.7 changed how player names are stored (Forever uses "First Last"); older test data cannot be matched.
    local db = ns.db
    db.my, db.votes, db.raterMax, db.raterCount, db.synced, db.seen = {}, {}, {}, {}, {}, {}
    db.lvl, db.muted, db.pending, db.session = {}, {}, {}, { mates = {}, t = 0 }
    db.schema = 3
  end
  Prune()
end

local function OnEvent(event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name == ADDON then InitDB() end
    if ns.UI and ns.UI.HookFinder and ns.db then ns.UI.HookFinder() end
  elseif event == "PLAYER_LOGIN" then
    if not ns.db then InitDB() end
    local _, key = UnitFull("player")
    ns.me = key
    ns.Sync.Init()
    ns.UI.Build()
    if not ns.db.welcomed then
      ns.db.welcomed = true
      C_Timer.After(6, function()
        ns.Print("installed. After a group you get a quick thumbs up / neutral / down for the players you spent time with.")
        ns.Print("Ratings are shared automatically with other Peer Review users. Type |cffffd140/peer test|r to see the popup, |cffffd140/peer|r for settings.")
        ns.Print("Vote on how the run went, not on the person. Nobody else ever sees a message from this addon.")
      end)
    end
    -- Group data arrives a moment after login; do not treat that gap as "left the group".
    C_Timer.After(8, function()
      if not ns.me then local _, k = UnitFull("player"); ns.me = k end
      T.ready, T.last = true, GetTime()
      T.Scan()
    end)
    C_Timer.NewTicker(5, function()
      local ok, err = pcall(T.Scan)
      if not ok and not T.err then T.err = true; ns.Print("|cffff5555error|r in tracker: " .. tostring(err)) end
    end)
  elseif not ns.db then
    return
  elseif event == "GROUP_ROSTER_UPDATE" or event == "GROUP_LEFT" or event == "GROUP_JOINED" then
    T.Scan()
  elseif event == "ENCOUNTER_END" then
    local success = select(5, ...)
    if not ns.IsSecret(success) and (success == 1 or success == true) then BossDown() end
  elseif event == "BOSS_KILL" then
    BossDown()
  elseif event == "PLAYER_REGEN_ENABLED" then
    if ns.UI.AfterCombat then ns.UI.AfterCombat() end
  end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "GROUP_ROSTER_UPDATE", "GROUP_LEFT", "GROUP_JOINED",
  "ENCOUNTER_END", "BOSS_KILL", "PLAYER_REGEN_ENABLED" }) do
  pcall(ev.RegisterEvent, ev, e) -- an event this client does not have is skipped
end
ev:SetScript("OnEvent", function(_, event, ...)
  local ok, err = pcall(OnEvent, event, ...)
  if not ok then ns.Print("|cffff5555error|r in " .. event .. ": " .. tostring(err)) end
end)

---------------------------------------------------------------- slash commands
SLASH_PEERREVIEW1 = "/peer"
SLASH_PEERREVIEW2 = "/peerreview"
SlashCmdList["PEERREVIEW"] = function(msg)
  if not ns.db then return end
  msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local cmd = msg:lower()
  if cmd == "" or cmd == "options" or cmd == "config" then
    ns.UI.ToggleOptions()
  elseif cmd == "rate" then
    ns.UI.RateNow()
  elseif cmd == "pending" then
    ns.UI.ShowPending()
  elseif cmd == "list" or cmd == "ratings" then
    ns.UI.ToggleList()
  elseif cmd == "test" then
    ns.UI.Test()
  elseif cmd == "sync" then
    for _, line in ipairs(ns.Sync.Diag()) do ns.Print(line) end
  elseif cmd == "help" then
    ns.Print("/peer (settings) | list (your ratings) | rate (current group) | pending (players you skipped today) | test (sample popup) | sync (status) | /peer Name (look someone up)")
  else
    local full, key = ns.Full(msg)
    local line = key and ns.Summary(key)
    local why = key and ns.TagLine(key)
    ns.Print(full and ((ns.Short(full)) .. ": " .. (line or "no votes yet") .. (why and ("  " .. why) or ""))
      or "could not read that name")
  end
end

-- Entry in the game's addon menu (the button next to the minimap).
function PeerReview_OnAddonCompartmentClick(_, button)
  if not ns.db or not ns.UI.options then return end
  if button == "RightButton" then ns.UI.ToggleOptions() else ns.UI.RateOrList() end
end

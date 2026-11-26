-- Peer Review: sync between addon users (no server).
-- Trust rule: a vote is only accepted from the player who cast it. The game stamps the sender
-- on every addon message, so nobody can submit votes in another player's name.
--   H~1                      hello, sent to guild / group / sync channel
--   Q~1~since                whisper: "send me your own votes newer than <since>"
--   H~1~version              (hello also carries the addon version)
--   V~1~target,u|n|d|x,time[,reasons];...   x = the sender took that vote back  the sender's own votes (reasons: up to 3 letters a-f)
--   D~1~Name-Realm;...       directory: other Peer Review users the sender has heard from
-- Databases are never copied between players. A directory only says who to ask; each listed
-- player is then asked directly for their own votes, so an edited file cannot plant votes.
local ADDON, ns = ...
local S = {}
ns.Sync = S

local PREFIX = ns.PREFIX
local CHANNEL = "PeerReviewSync"
S.queue, S.peers, S.chanOK, S.buckets, S.asked, S.answered = {}, {}, {}, {}, {}, {}
S.pull, S.pullSet, S.whispered, S.dirFrom = {}, {}, {}, {}
S.stats = { sent = 0, recv = 0, votes = 0, rejected = 0, pulls = 0 }
local SendFn
local MAX_PER_RATER = 3000

local function On() return ns.db and ns.db.settings.sync end

---------------------------------------------------------------- transports
function S.ChannelId()
  if not GetChannelName then return nil end
  local id = GetChannelName(CHANNEL)
  if type(id) == "number" and id > 0 then return id end
  return nil
end

function S.Channels()
  local list = {}
  local id = S.ChannelId()
  if id and S.chanOK.CHANNEL == true and ns.db.settings.channel then list[#list + 1] = { "CHANNEL", id } end
  if IsInGuild and IsInGuild() and S.chanOK.GUILD ~= false then list[#list + 1] = { "GUILD" } end
  if IsInRaid and IsInRaid() and S.chanOK.RAID ~= false then list[#list + 1] = { "RAID" }
  elseif IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE or 2) and S.chanOK.INSTANCE_CHAT ~= false then list[#list + 1] = { "INSTANCE_CHAT" }
  elseif IsInGroup and IsInGroup() and S.chanOK.PARTY ~= false then list[#list + 1] = { "PARTY" } end
  return list
end

local function HideChannel()
  for i = 1, (NUM_CHAT_WINDOWS or 10) do
    local cf = _G["ChatFrame" .. i]
    if cf and ChatFrame_RemoveChannel then pcall(ChatFrame_RemoveChannel, cf, CHANNEL) end
  end
end

-- The channel is only used once one of our own messages has come back through it.
local function Probe()
  if S.chanOK.CHANNEL ~= nil or not S.ChannelId() then return end
  S.probes = (S.probes or 0) + 1
  S.queue[#S.queue + 1] = { chan = "CHANNEL", text = "P~" .. ns.PROTO, tries = 0 }
  C_Timer.After(10, function()
    if S.chanOK.CHANNEL ~= nil then return end
    if S.probes < 2 then Probe() return end
    S.chanOK.CHANNEL = false
    S.stats.lastError = "sync channel does not carry addon messages on this client"
    S.LeaveChannel()
  end)
end

function S.JoinChannel()
  if not On() or not ns.db.settings.channel or S.chanOK.CHANNEL == false then return end
  if S.ChannelId() then HideChannel(); Probe() return end
  local now = GetTime()
  if S.lastJoin and now - S.lastJoin < 30 then return end
  S.lastJoin = now
  local ok = false
  if JoinTemporaryChannel then ok = pcall(JoinTemporaryChannel, CHANNEL) end
  if not ok and JoinChannelByName then pcall(JoinChannelByName, CHANNEL) end
  C_Timer.After(3, function() if S.ChannelId() then HideChannel(); Probe() end end)
end

function S.LeaveChannel()
  if S.ChannelId() and LeaveChannelByName then pcall(LeaveChannelByName, CHANNEL) end
end

---------------------------------------------------------------- outgoing
local function Enqueue(chan, target, text)
  if #S.queue >= 300 then return end
  S.queue[#S.queue + 1] = { chan = chan, target = target, text = text, tries = 0 }
end

-- One message a second, well under the game's limits. The value SendAddonMessage returns is not
-- dependable on the Forever client, so only a Lua error or an explicit false counts as a failure.
local function Pump()
  local q = S.queue
  if #q == 0 or not On() or not SendFn then return end
  if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
    local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
    if ok and locked == true then return end
  end
  local it = table.remove(q, 1)
  if it.chan == "CHANNEL" then
    it.target = S.ChannelId()
    if not it.target then return end
  end
  local ok, res = pcall(SendFn, PREFIX, it.text, it.chan, it.target)
  if not ok or res == false then
    S.stats.failed = (S.stats.failed or 0) + 1
    S.stats.lastError = it.chan .. ": " .. tostring(ok and "send refused" or res)
  else
    S.stats.sent = S.stats.sent + 1
  end
end

function S.Broadcast(text)
  if not On() then return end
  for _, c in ipairs(S.Channels()) do Enqueue(c[1], c[2], text) end
end

function S.Hello()
  local now = GetTime()
  if S.lastHello and now - S.lastHello < 60 then return end
  S.lastHello = now
  S.Broadcast("H~" .. ns.PROTO .. "~" .. ns.VERSION)
end

-- Tell the player once when two other users report a newer version.
local function VersionNumber(v)
  local a, b, c = tostring(v or ""):match("^(%d+)%.(%d+)%.(%d+)$")
  if not a then return nil end
  return tonumber(a) * 1000000 + tonumber(b) * 1000 + tonumber(c)
end
S.newer = {}
local function NoteVersion(sk, v)
  local theirs, mine = VersionNumber(v), VersionNumber(ns.VERSION)
  if not theirs or not mine or theirs <= mine or S.told then return end
  S.newer[sk] = v
  local n = 0
  for _ in pairs(S.newer) do n = n + 1 end
  if n >= 2 then
    S.told = true
    ns.Print(("a newer version (%s) is out. Update it in the CurseForge app."):format(v))
  end
end

function S.OnGroupChange()
  C_Timer.After(4, function() if On() then S.Hello() end end)
end

local function Item(key, r)
  local letter = r.v == 1 and "u" or r.v == 0 and "n" or r.v == -1 and "d" or "x"
  return ("%s,%s,%d%s"):format(key, letter, r.t, (r.g and letter ~= "x") and ("," .. r.g) or "")
end

-- A vote goes out 12 seconds after the last change, so thumb plus reasons travel as one message.
S.due = {}
function S.PublishVote(key)
  S.due[key] = GetTime() + 12
end
local function FlushVotes()
  local now = GetTime()
  for key, at in pairs(S.due) do
    if at <= now then
      S.due[key] = nil
      local r = ns.db.my[key]
      if r then S.Broadcast("V~" .. ns.PROTO .. "~" .. Item(key, r)) end
    end
  end
end

-- Whisper the names of up to 40 users heard from in the last week, most recent first.
local function SendDirectory(sender, sk)
  local list, cutoff = {}, time() - 7 * 86400
  for key, e in pairs(ns.db.seen) do
    if key ~= sk and e.t >= cutoff then list[#list + 1] = e end
  end
  if #list == 0 then return end
  table.sort(list, function(a, b) return a.t > b.t end)
  local head = "D~" .. ns.PROTO .. "~"
  local buf = head
  for i = 1, math.min(#list, 40) do
    local n = list[i].n
    if #buf + #n + 1 > 240 and buf ~= head then
      Enqueue("WHISPER", sender, buf)
      buf = head
    end
    buf = buf .. (buf == head and "" or ";") .. n
  end
  if buf ~= head then Enqueue("WHISPER", sender, buf) end
end

-- A directory from someone else: queue each unknown user to be asked directly.
local function StoreDirectory(body, sk)
  local now = GetTime()
  local d = S.dirFrom[sk]
  if not d or now - d.t > 600 then d = { t = now, n = 0 }; S.dirFrom[sk] = d end
  for name in body:gmatch("[^;]+") do
    if d.n >= 60 or #S.pull >= 200 then return end
    d.n = d.n + 1
    if #name >= 2 and #name <= 80 and not name:find("[,~|]") then
      local full, key = ns.Full(name)
      if key and key ~= ns.me and not S.peers[key] and not S.pullSet[key]
        and (ns.db.synced[key] or 0) < time() - 12 * 3600 then
        S.pullSet[key] = true
        S.pull[#S.pull + 1] = { key = key, name = full }
      end
    end
  end
end

-- One direct request every 20 seconds to a user learned from a directory.
local function PullNext()
  if not On() or #S.pull == 0 or #S.queue > 5 then return end
  local it = table.remove(S.pull, 1)
  S.pullSet[it.key] = nil
  local db = ns.db
  if S.peers[it.key] or (db.synced[it.key] or 0) > time() - 12 * 3600 then return end
  db.synced[it.key] = time()
  S.whispered[it.name:lower()] = GetTime()
  S.whispered[(it.name:match("^(.-)%-[^%-]+$") or it.name):lower()] = GetTime()
  S.stats.pulls = S.stats.pulls + 1
  Enqueue("WHISPER", it.name, ("Q~%d~%d"):format(ns.PROTO, db.raterMax[it.key] or 0))
end

-- Whisper my own votes newer than `since`, oldest first so the asker can resume where it stopped.
local function Answer(sender, sk, since)
  local now = GetTime()
  if S.answered[sk] and now - S.answered[sk] < 600 then return end
  S.window = S.window or { t = now, n = 0 }
  if now - S.window.t > 600 then S.window = { t = now, n = 0 } end
  if S.window.n >= 30 then return end
  S.window.n = S.window.n + 1
  S.answered[sk] = now
  SendDirectory(sender, sk)

  local list, cutoff = {}, time() - ns.EXPIRE
  for key, r in pairs(ns.db.my) do
    if r.t > since and r.t >= cutoff then list[#list + 1] = { key = key, v = r.v, t = r.t, g = r.g } end
  end
  if #list == 0 then return end
  table.sort(list, function(a, b) return a.t < b.t end)
  local head = "V~" .. ns.PROTO .. "~"
  local buf, sent = head, 0
  for _, r in ipairs(list) do
    local item = Item(r.key, r)
    if #buf + #item + 1 > 240 and buf ~= head then
      Enqueue("WHISPER", sender, buf)
      sent = sent + 1
      if sent >= 60 then return end
      buf = head
    end
    buf = buf .. (buf == head and "" or ";") .. item
  end
  if buf ~= head then Enqueue("WHISPER", sender, buf) end
end

---------------------------------------------------------------- incoming
local function MaybeAsk(sender, sk)
  local db = ns.db
  if S.asked[sk] or (db.synced[sk] or 0) > time() - 12 * 3600 then return end
  S.asked[sk] = true
  C_Timer.After(1 + math.random() * 5, function()
    if not On() then return end
    db.synced[sk] = time()
    Enqueue("WHISPER", sender, ("Q~%d~%d"):format(ns.PROTO, db.raterMax[sk] or 0))
  end)
end

local function StoreVotes(body, sk)
  local db, now, n = ns.db, time(), 0
  if ns.TooLow(sk) then S.stats.rejected = S.stats.rejected + 1 return end
  for item in body:gmatch("[^;]+") do
    local target, v, t, g = item:match("^([^,;~]+),([undx]),(%d+),?([a-f]*)$")
    t = tonumber(t)
    v = (v == "u") and 1 or (v == "n") and 0 or (v == "d") and -1 or "x"
    if v == "x" then g = nil end
    if g == "" or (g and #g > ns.MAX_TAGS) then g = nil end
    if target and t and #target >= 2 and #target <= 64 and target == target:lower()
      and not target:find("^%s") and not target:find("%s$") and target ~= sk then
      if t > now + 86400 then t = now end
      if t >= now - ns.EXPIRE then
        local set = db.votes[target]
        local cur = set and set[sk]
        if cur then
          if t > cur.t then cur.v, cur.t, cur.g = v, t, g; n = n + 1 end
        elseif (db.raterCount[sk] or 0) < MAX_PER_RATER then
          if not set then set = {}; db.votes[target] = set end
          set[sk] = { v = v, t = t, g = g }
          db.raterCount[sk] = (db.raterCount[sk] or 0) + 1
          n = n + 1
        end
        if t > (db.raterMax[sk] or 0) then db.raterMax[sk] = t end
      end
    else
      S.stats.rejected = S.stats.rejected + 1
    end
  end
  S.stats.votes = S.stats.votes + n
  if n > 0 then ns.Dirty() end
end

function S.OnMessage(prefix, text, channel, sender)
  if prefix ~= PREFIX or not On() then return end
  if ns.IsSecret(text) or ns.IsSecret(sender) then return end
  if type(text) ~= "string" or type(sender) ~= "string" or #text > 255 or #text < 3 then return end
  local full, sk = ns.Full(sender)
  if not sk then return end
  if sk == ns.me then
    if channel == "CHANNEL" and S.chanOK.CHANNEL == nil then S.chanOK.CHANNEL = true; S.Hello() end
    return
  end

  local now = GetTime()
  local b = S.buckets[sk]
  if not b or now - b.t > 60 then b = { t = now, n = 0 }; S.buckets[sk] = b end
  b.n = b.n + 1
  if b.n > 40 then S.stats.rejected = S.stats.rejected + 1 return end
  S.peers[sk] = now
  ns.db.seen[sk] = { t = time(), n = full }
  S.stats.recv = S.stats.recv + 1

  local typ, proto, body = text:match("^(%u)~(%d+)~?(.*)$")
  if not typ or tonumber(proto) ~= ns.PROTO then return end
  if typ == "H" then
    NoteVersion(sk, body)
  elseif typ == "V" then
    StoreVotes(body, sk)
  elseif typ == "Q" then
    Answer(full, sk, tonumber(body) or 0)
  elseif typ == "D" then
    StoreDirectory(body, sk)
  end
  MaybeAsk(full, sk)
end

---------------------------------------------------------------- status
function S.PeerCount()
  local n, now = 0, GetTime()
  for _, t in pairs(S.peers) do if now - t < 1800 then n = n + 1 end end
  return n
end

function S.Status()
  if not On() then return "Sharing is off" end
  local n = S.PeerCount()
  if n == 0 then return "Sharing on, no other Peer Review users seen yet" end
  return ("Sharing on, %d other user%s seen this session"):format(n, n == 1 and "" or "s")
end

function S.Diag()
  local out, chans = {}, {}
  for _, c in ipairs(S.Channels()) do chans[#chans + 1] = c[1] end
  out[#out + 1] = S.Status()
  out[#out + 1] = "Routes: " .. (#chans > 0 and table.concat(chans, ", ") or "none (join a guild or group, or wait for the sync channel)")
  out[#out + 1] = ("Sync channel: %s"):format(not ns.db.settings.channel and "off"
    or S.chanOK.CHANNEL == false and "not usable on this client"
    or S.chanOK.CHANNEL == true and "working" or S.ChannelId() and "joined, waiting for a test message to come back" or "not joined")
  out[#out + 1] = ("You are known as: %s"):format(tostring(ns.me))
  out[#out + 1] = ("Messages sent %d (%d refused), received %d, votes learned %d, rejected %d, queued %d"):format(
    S.stats.sent, S.stats.failed or 0, S.stats.recv, S.stats.votes, S.stats.rejected, #S.queue)
  local known = 0
  for _ in pairs(ns.db.seen) do known = known + 1 end
  out[#out + 1] = ("Peer Review users known %d, asked directly this session %d, waiting to be asked %d"):format(
    known, S.stats.pulls, #S.pull)
  if S.stats.lastError then out[#out + 1] = "Last problem: " .. S.stats.lastError end
  return out
end

---------------------------------------------------------------- init
function S.Init()
  SendFn = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
  local reg = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
  if reg then pcall(reg, PREFIX) end

  if ChatFrame_AddMessageEventFilter then
    local function filter(_, _, _, _, _, chanString, _, _, _, _, chanName)
      local ok, hide = pcall(function()
        return (type(chanName) == "string" and chanName:lower():find("peerreviewsync", 1, true) ~= nil)
          or (type(chanString) == "string" and chanString:lower():find("peerreviewsync", 1, true) ~= nil)
      end)
      return ok and hide or false
    end
    pcall(ChatFrame_AddMessageEventFilter, "CHAT_MSG_CHANNEL_NOTICE", filter)
    pcall(ChatFrame_AddMessageEventFilter, "CHAT_MSG_CHANNEL_NOTICE_USER", filter)
    pcall(ChatFrame_AddMessageEventFilter, "CHAT_MSG_CHANNEL", filter)

    -- Asking a user who has logged off makes the game print a "player not found / offline" line. Hide it.
    local pats = {}
    for _, g in ipairs({ ERR_CHAT_PLAYER_NOT_FOUND_S, ERR_PLAYER_OFFLINE_S }) do
      if type(g) == "string" then
        pats[#pats + 1] = "^" .. g:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"):gsub("%%s", "(.+)") .. "$"
      end
    end
    pcall(ChatFrame_AddMessageEventFilter, "CHAT_MSG_SYSTEM", function(_, _, msg)
      local ok, hide = pcall(function()
        if type(msg) ~= "string" then return false end
        for _, p in ipairs(pats) do
          local who = msg:match(p)
          local t = who and S.whispered[who:lower()]
          if t and GetTime() - t < 60 then return true end
        end
        return false
      end)
      return ok and hide or false
    end)
  end

  local f = CreateFrame("Frame")
  f:RegisterEvent("CHAT_MSG_ADDON")
  f:SetScript("OnEvent", function(_, _, ...) pcall(S.OnMessage, ...) end)

  C_Timer.NewTicker(1, function() pcall(Pump) end)
  C_Timer.NewTicker(20, function() pcall(PullNext) end)
  C_Timer.NewTicker(3, function() pcall(FlushVotes) end)
  -- Join after the default channels so their numbers do not shift.
  C_Timer.After(15, function() pcall(S.JoinChannel) end)
  C_Timer.After(22, function() if On() then S.Hello() end end)
  C_Timer.NewTicker(120, function() if On() and not S.ChannelId() then pcall(S.JoinChannel) end end)
  C_Timer.NewTicker(1800, function() if On() then S.Hello() end end)
end

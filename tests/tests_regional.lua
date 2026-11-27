-- WoW: Forever naming: "First Last", unique per region, senders arrive as "First Last-Realm".
local ns = NS
local fails = 0
local function check(name, cond, extra) if cond then LOG("ok   " .. name) else fails = fails + 1; LOG("FAIL " .. name .. " " .. tostring(extra or "")) end end
local function sent(pat) for _, m in ipairs(SENT) do if m.text:find(pat) then return m end end end
local function recv(text, sender, chan) Fire("CHAT_MSG_ADDON", "PeerReview", text, chan or "PARTY", sender) end
REGIONAL, MYNAME = true, "Rod Tester"
function RegionalUniqueNamesEnabled() return true end

Fire("ADDON_LOADED", "PeerReview"); Fire("PLAYER_LOGIN"); Advance(10)
check("my key is the full name, no realm", ns.me == "rod tester", ns.me)

GROUP = { { "Good Guy", "" }, { "Mean Person", "" } }
Fire("GROUP_ROSTER_UPDATE"); Advance(31 * 60, 5)
local m = ns.db.session.mates
check("mates keyed by full name", m["good guy"] ~= nil and m["mean person"] ~= nil)
check("whisper form carries the realm", m["good guy"].name == "Good Guy-Azeroth", m["good guy"] and m["good guy"].name)
check("display name drops the realm", ns.Short(m["good guy"].name) == "Good Guy", ns.Short(m["good guy"].name))

-- loading-screen blip: ungrouped for 2 seconds must not end the session
local saved = GROUP; GROUP = {}; Fire("GROUP_ROSTER_UPDATE"); Advance(2); GROUP = saved; Fire("GROUP_ROSTER_UPDATE"); Advance(6)
check("2 second ungrouped blip does not open the popup", not ns.UI.rate:IsShown() and ns.db.session.mates["good guy"] ~= nil)

Leave()
check("popup after really leaving", ns.UI.rate:IsShown() and #ns.UI.queue == 2, #ns.UI.queue)

SENT = {}
ns.Vote("good guy", 1, ns.UI.queue[1].key == "good guy" and ns.UI.queue[1] or ns.UI.queue[2]); Advance(20)
check("vote goes out keyed by full name", sent("^V~1~good guy,u,%d+$") ~= nil, SENT[1] and SENT[1].text)

-- close with one player left: parked, reopenable
ns.UI.Drop("good guy"); ns.UI.rate.close._OnClick(ns.UI.rate.close)
check("skipped player parked", ns.db.pending["mean person"] ~= nil and not ns.UI.rate:IsShown())
ns.UI.ShowPending()
check("pending reopens the popup", ns.UI.rate:IsShown() and ns.UI.queue[1].key == "mean person")
ns.Vote("mean person", -1, ns.UI.queue[1]); ns.UI.Drop("mean person")
check("voting clears pending", ns.db.pending["mean person"] == nil)

-- incoming: sender with realm suffix and with an id suffix resolve to the same player
recv("V~1~some target,u," .. CLOCK, "Alice Smith-Azeroth")
recv("V~1~some target,d," .. (CLOCK + 5), "Alice Smith-Azeroth:9113:1")
local set = ns.db.votes["some target"]
local n = 0; for _ in pairs(set or {}) do n = n + 1 end
check("sender spellings map to one voter", n == 1 and set["alice smith"] and set["alice smith"].v == -1)
recv("V~1~rod tester,d," .. CLOCK, "Rod Tester-Azeroth")
check("own echo ignored with realm suffix", ns.db.votes["rod tester"] == nil)
recv("V~1~alice smith,u," .. CLOCK, "Alice Smith-Azeroth")
check("self vote rejected", ns.db.votes["alice smith"] == nil)

SENT = {}; Advance(10)
local q = sent("^Q~1~")
check("asks the voter back using the Name-Realm whisper form", q and q.chan == "WHISPER" and q.target == "Alice Smith-Azeroth", q and q.target)

SENT = {}
recv("Q~1~0", "Bob Jones-Azeroth", "WHISPER"); Advance(8)
local a, d = sent("^V~1~"), sent("^D~1~")
check("answer whispered to Name-Realm", a and a.target == "Bob Jones-Azeroth" and a.text:find("good guy,u,") ~= nil, a and a.text)
check("directory lists whisper names", d and d.text:find("Alice Smith%-Azeroth") ~= nil, d and d.text)
recv("D~1~Zed Zed-Azeroth;Rod Tester-Azeroth;Alice Smith-Azeroth", "Bob Jones-Azeroth", "WHISPER")
check("directory with spaces accepted, self and known skipped", #ns.Sync.pull == 1 and ns.Sync.pull[1].name == "Zed Zed-Azeroth", #ns.Sync.pull)

-- channel is unused until our own probe echoes back
ns.db.settings.channel = true
function GetChannelName() return 5 end
check("channel not a route before the echo", (function() for _, c in ipairs(ns.Sync.Channels()) do if c[1] == "CHANNEL" then return false end end return true end)())
ns.Sync.JoinChannel(); SENT = {}; Advance(3)
check("probe sent on the channel", sent("^P~1$") ~= nil and sent("^P~1$").chan == "CHANNEL")
recv("P~1", "Rod Tester-Azeroth", "CHANNEL")
check("channel becomes a route after the echo", (function() for _, c in ipairs(ns.Sync.Channels()) do if c[1] == "CHANNEL" then return true end end return false end)())

-- send results: numeric codes are not failures, false is
local real = C_ChatInfo.SendAddonMessage
C_ChatInfo.SendAddonMessage = function(...) real(...) return 9 end
ns.Sync.Init(); SENT = {}; ns.Sync.Broadcast("H~1"); Advance(8)
check("non-zero result code still counts as sent, no resend", #SENT >= 1 and (ns.Sync.stats.failed or 0) == 0, #SENT)

for _, p in ipairs(PRINTS) do if p:find("error") then LOG("PRINTED: " .. p); fails = fails + 1 end end
LOG(fails == 0 and "ALL PASSED" or (fails .. " FAILED"))

-- ===== v0.8 =====
fails = 0
local before = #ns.MyList()
check("my list holds live votes, newest first", before == 2 and ns.MyList()[1].key == "mean person", before)
check("reason text", ns.ReasonText(1, "ac") == "Friendly, Skilled")
ns.UI.ToggleList(); ns.UI.RefreshList()
check("list window opens", ns.UI.list:IsShown() and ns.UI.list.rows[1].item ~= nil)
-- remove a vote
SENT = {}
local row = ns.UI.list.rows[1]
row.remove._OnClick(row.remove); Advance(20)
check("removed vote leaves my list", #ns.MyList() == 1 and ns.db.my["mean person"].v == "x")
check("removal is broadcast as x", sent("^V~1~mean person,x,%d+$") ~= nil, SENT[1] and SENT[1].text)
check("removed vote no longer counts for me", select(3, ns.Score("mean person")) == nil)
-- change a vote through the list
row = ns.UI.list.rows[1]
row.change._OnClick(row.change)
check("change opens the popup for that player", ns.UI.rate:IsShown() and ns.UI.queue[1].key == "good guy")
ns.UI.queue = {}; ns.UI.RefreshRate()
-- incoming removal
recv("V~1~other one,d," .. CLOCK, "Carl Voter-Azeroth")
check("vote stored", select(2, ns.Score("other one")) == 1)
recv("V~1~other one,x," .. (CLOCK + 10), "Carl Voter-Azeroth")
check("incoming removal drops the vote from the score", select(2, ns.Score("other one")) == 0)
recv("V~1~other one,d," .. (CLOCK + 5), "Carl Voter-Azeroth")
check("an older copy cannot bring a removed vote back", select(2, ns.Score("other one")) == 0)
-- removed votes are asked about again
check("removed player can be asked about again", ns.Eligible("mean person", { secs = 4000, act = true }) == true)
-- version notice needs two peers
PRINTS = {}
recv("H~1~9.9.9", "Peer One-Azeroth")
local function told() for _, p in ipairs(PRINTS) do if p:find("newer version") then return true end end return false end
check("one peer on a newer version: no notice", not told())
recv("H~1~9.9.9", "Peer Two-Azeroth")
check("two peers on a newer version: notice once", told())
recv("H~1~not-a-version", "Peer Three-Azeroth"); recv("H~1~0.1.0", "Peer Four-Azeroth")
-- hello carries our version
SENT = {}; ns.Sync.lastHello = nil; ns.Sync.Hello(); Advance(5)
check("hello carries the version", sent("^H~1~" .. ns.VERSION:gsub("%.", "%%.") .. "$") ~= nil, SENT[1] and SENT[1].text)
PRINTS = {}; SlashCmdList.PEERREVIEW("version")
check("/peer version prints the version", (PRINTS[1] or ""):find("version " .. ns.VERSION, 1, true) ~= nil, PRINTS[1])
-- minimap click with nobody to rate opens the list
ns.UI.list:Hide(); ns.UI.RateOrList()
check("nothing to rate: click opens my ratings", ns.UI.list:IsShown())
-- peer marker
ns.UI.ShowRate({ { key = "alice smith", name = "Alice Smith-Azeroth", class = "MAGE", secs = 2000 } })
check("row marks players who use the addon", (ns.UI.rate.rows[1].info._text or ""):find("uses Peer Review") ~= nil, ns.UI.rate.rows[1].info._text)
for _, p in ipairs(PRINTS) do if p:find("error") then LOG("PRINTED: " .. p); fails = fails + 1 end end
LOG(fails == 0 and "ALL PASSED v0.8" or (fails .. " FAILED v0.8"))

-- ===== v0.8.2 =====
fails = 0
PRINTS = {}; SlashCmdList.PEERREVIEW("me")
check("/peer me with no votes", (PRINTS[1] or ""):find("no votes yet", 1, true) ~= nil, PRINTS[1])
for i, who in ipairs({ "Ann One", "Ben Two", "Cat Three", "Dan Four" }) do
  recv("V~1~rod tester," .. (i == 4 and "d" or "u") .. "," .. (CLOCK + i * 4000) .. ",a", who .. "-Azeroth")
end
local line = ns.MyRating()
check("own rating from other players' votes", (line or ""):find("75%% would group again") ~= nil and (line or ""):find("4 votes") ~= nil, line)
ns.UI.list:Hide(); ns.UI.ToggleList()
check("my ratings shows own score", (ns.UI.list.mine.text._text or ""):find("75%%") ~= nil, ns.UI.list.mine.text._text)
ns.UI.queue = {}; ns.UI.RefreshRate()
SlashCmdList.PEERREVIEW("preview")
check("/peer preview opens sample rows", ns.UI.rate:IsShown() and #ns.UI.queue == 4 and ns.UI.queue[1].fake == true)
local before = 0; for _ in pairs(ns.db.my) do before = before + 1 end
ns.UI.rate.rows[1].up._OnClick(ns.UI.rate.rows[1].up)
local after = 0; for _ in pairs(ns.db.my) do after = after + 1 end
check("preview votes are never saved", before == after)
ns.UI.queue = {}; ns.UI.RefreshRate()
SlashCmdList.PEERREVIEW("feedback"); ns.UI.feedback._OnShow()
check("feedback window opens with a report line", ns.UI.feedback:IsShown() and (ns.UI.feedback.info.value or ""):find("Peer Review " .. ns.VERSION, 1, true) ~= nil, ns.UI.feedback.info.value)
check("log records activity", type(ns.db.log) == "table" and #ns.db.log > 5)
local found = false; for _, l in ipairs(ns.db.log) do if l:find("login: v") then found = true end end
check("log has the login line", found)
for i = 1, 400 do ns.Log("x" .. i) end
check("log is capped at 250 lines", #ns.db.log == 250)
PRINTS = {}; SlashCmdList.PEERREVIEW("help")
check("help no longer mentions test or sync", not (PRINTS[1] or ""):find("test") and not (PRINTS[1] or ""):find("sync"))
for _, p in ipairs(PRINTS) do if p:find("error") then LOG("PRINTED: " .. p); fails = fails + 1 end end
LOG(fails == 0 and "ALL PASSED v0.8.2" or (fails .. " FAILED v0.8.2"))

-- someone leaves while I stay in the group: asked about them right away
ns.UI.queue = {}; ns.UI.RefreshRate()
GROUP = { { "Early Leaver", "" }, { "Stays Here", "" } }
Fire("GROUP_ROSTER_UPDATE"); Advance(31 * 60, 5)
GROUP = { { "Stays Here", "" } }
Fire("GROUP_ROSTER_UPDATE"); Advance(2)
check("leaver not asked within 2 seconds", #ns.UI.queue == 0, #ns.UI.queue)
Advance(8)
check("leaver asked about while still grouped", #ns.UI.queue == 1 and ns.UI.queue[1].key == "early leaver" and ns.UI.queue[1].left == true, #ns.UI.queue)
check("header names the leaver", ns.UI.rate.sub._text == "Early Leaver just left. Group with them again?", tostring(ns.UI.rate.sub._text))
local row = ns.UI.rate.rows[1]
row.skip._OnClick(row.skip)
check("skip parks the player without a vote", ns.db.pending["early leaver"] ~= nil and ns.db.my["early leaver"] == nil and #ns.UI.queue == 0)
Leave()
check("leaver not asked twice at the end", #ns.UI.queue == 1 and ns.UI.queue[1].key == "stays here", #ns.UI.queue)
ns.UI.queue = {}; ns.UI.RefreshRate()

-- server hops, trades, crafts: under 5 minutes never shows anywhere, boss kill or not
ns.UI.queue = {}; ns.UI.RefreshRate()
GROUP = { { "Hop Bot", "" } }
Fire("GROUP_ROSTER_UPDATE"); Advance(180, 5)
Fire("BOSS_KILL")
check("short group hidden from rate-now list", #ns.SessionList(true) == 0, #ns.SessionList(true))
Leave()
check("no popup for a 3 minute group", #ns.UI.queue == 0 and ns.db.pending["hop bot"] == nil, #ns.UI.queue)

-- someone who only sat in the party (no combat, no instance, no trade) is ignored
FIGHT = false
GROUP = { { "Bag Guest", "" }, { "Trade Pal", "" } }
Fire("GROUP_ROSTER_UPDATE"); Advance(40 * 60, 5)
check("idle guest not eligible after 40 minutes", ns.Eligible("bag guest", ns.db.session.mates["bag guest"]) == false)
GROUP_NPC = "Trade Pal"; Fire("TRADE_SHOW"); Fire("UI_INFO_MESSAGE", 1, ERR_TRADE_COMPLETE)
check("completed trade counts as activity", ns.db.session.mates["trade pal"].act == true)
Leave()
check("popup only for the player something happened with", #ns.UI.queue == 1 and ns.UI.queue[1].key == "trade pal", #ns.UI.queue)
ns.UI.queue = {}; ns.UI.RefreshRate(); FIGHT = true
LOG(fails == 0 and "ALL PASSED" or (fails .. " FAILED"))

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
check("removed player can be asked about again", ns.Eligible("mean person", { secs = 4000 }) == true)
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
check("hello carries the version", sent("^H~1~0%.8%.0$") ~= nil, SENT[1] and SENT[1].text)
-- minimap click with nobody to rate opens the list
ns.UI.list:Hide(); ns.UI.RateOrList()
check("nothing to rate: click opens my ratings", ns.UI.list:IsShown())
-- peer marker
ns.UI.ShowRate({ { key = "alice smith", name = "Alice Smith-Azeroth", class = "MAGE", secs = 2000 } })
check("row marks players who use the addon", (ns.UI.rate.rows[1].info._text or ""):find("uses Peer Review") ~= nil, ns.UI.rate.rows[1].info._text)
for _, p in ipairs(PRINTS) do if p:find("error") then LOG("PRINTED: " .. p); fails = fails + 1 end end
LOG(fails == 0 and "ALL PASSED v0.8" or (fails .. " FAILED v0.8"))

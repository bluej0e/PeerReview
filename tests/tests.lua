local ns = NS
local fails = 0
local function check(name, cond, extra) if cond then LOG("ok   " .. name) else fails = fails + 1; LOG("FAIL " .. name .. " " .. tostring(extra or "")) end end
local function errors() for _, p in ipairs(PRINTS) do if p:find("error") then return p end end end
local function sent(pat) for _, m in ipairs(SENT) do if m.text:find(pat) then return m end end end

Fire("ADDON_LOADED", "PeerReview")
Fire("PLAYER_LOGIN")
check("db created", ns.db and ns.db.settings.minMinutes == 30)
check("me key", true)
Advance(10)
check("me key set", ns.me == "rodrigo-azeroth", ns.me)
check("no popup at login", not ns.UI.rate:IsShown())

-- 35 min dungeon group with 4 people; one joins for the last 2 minutes
GROUP = { { "Brother", "" }, { "Goodguy", "" }, { "Guildie", "" } }
FRIENDS["Player-1-Brother"] = true; GUILDMATES.Guildie = true
INSTANCE = true
Fire("GROUP_ROSTER_UPDATE")
Advance(33 * 60, 5)
GROUP[4] = { "Latecomer", "Stormrage" }
Fire("GROUP_ROSTER_UPDATE")
Advance(120, 5)
local m = ns.db.session.mates
check("time tracked ~35m", m["goodguy-azeroth"] and math.abs(m["goodguy-azeroth"].secs - 35 * 60) < 30, m["goodguy-azeroth"] and m["goodguy-azeroth"].secs)
check("latecomer ~2m", m["latecomer-stormrage"] and m["latecomer-stormrage"].secs < 150)
check("friend flagged", m["brother-azeroth"].friend == true)
check("guild flagged", m["guildie-azeroth"].guild == true)
check("hello broadcast on group", sent("^H~1~") ~= nil)
Leave()
check("popup shown", ns.UI.rate:IsShown())
check("only Goodguy asked (friend, guildie, latecomer skipped)", #ns.UI.queue == 1 and ns.UI.queue[1].key == "goodguy-azeroth", #ns.UI.queue)
check("session cleared", next(ns.db.session.mates) == nil)

-- vote
SENT = {}
ns.Vote("goodguy-azeroth", 1, ns.UI.queue[1]); ns.UI.Drop("goodguy-azeroth")
check("popup closed after last vote", not ns.UI.rate:IsShown())
Advance(3)
check("vote not sent instantly (waits for reasons)", sent("^V~") == nil)
ns.SetTags("goodguy-azeroth", "ac"); Advance(20)
check("vote broadcast once, with reasons", sent("^V~1~goodguy%-azeroth,u,%d+,ac$") ~= nil and #SENT == 1, SENT[1] and SENT[1].text)
check("guild route used", SENT[1] and SENT[1].chan == "GUILD")

-- boss kill qualifies a short group; rated players are not re-asked
GROUP = { { "Goodguy", "" }, { "Speedy", "" } }
Fire("GROUP_ROSTER_UPDATE"); Advance(300, 5)
Fire("ENCOUNTER_END", 1, "Boss", 1, 5, 1)
Leave()
check("boss kill qualifies, rated player skipped", #ns.UI.queue == 1 and ns.UI.queue[1].key == "speedy-azeroth", #ns.UI.queue)
ns.Mute("speedy-azeroth"); ns.UI.Drop("speedy-azeroth")

-- 10-second group: nothing
GROUP = { { "Drive", "By" } }; Fire("GROUP_ROSTER_UPDATE"); Advance(10, 5); Leave()
check("10 second group: no popup", not ns.UI.rate:IsShown())

-- muted player never asked
GROUP = { { "Speedy", "" } }; Fire("GROUP_ROSTER_UPDATE"); Advance(40 * 60, 5); Leave()
check("never-ask respected", not ns.UI.rate:IsShown())

-- combat defers the popup
GROUP = { { "Fighter", "" } }; Fire("GROUP_ROSTER_UPDATE"); Advance(31 * 60, 5)
COMBAT = true; Leave()
check("popup held during combat", not ns.UI.rate:IsShown() and #ns.UI.queue == 1)
COMBAT = false; Fire("PLAYER_REGEN_ENABLED")
check("popup after combat", ns.UI.rate:IsShown())
ns.UI.queue = {}; ns.UI.RefreshRate()

-- incoming votes: trust, forging, scores
local function recv(text, sender) Fire("CHAT_MSG_ADDON", "PeerReview", text, "GUILD", sender) end
recv("V~1~target-azeroth,u," .. CLOCK, "Alice-Azeroth")
recv("V~1~target-azeroth,u," .. CLOCK, "Bob-Azeroth")
recv("V~1~target-azeroth,d," .. CLOCK, "Carl-Azeroth")
local up, down = ns.Score("target-azeroth")
check("3 votes counted", up == 2 and down == 1, up .. "/" .. down)
check("summary shows 67%", (ns.Summary("target-azeroth") or ""):find("67%% would group again") ~= nil, ns.Summary("target-azeroth"))
recv("V~1~target-azeroth,d," .. (CLOCK + 5), "Alice-Azeroth")
up, down = ns.Score("target-azeroth")
check("changed vote replaces, not adds", up == 1 and down == 2, up .. "/" .. down)
recv("V~1~alice-azeroth,u," .. CLOCK, "Alice-Azeroth")
check("self vote rejected", ns.db.votes["alice-azeroth"] == nil)
recv("V~1~Bad Name,u,12;x-y,q,1;" .. string.rep("a", 70) .. "-b,u,5", "Alice-Azeroth")
check("garbage rejected", ns.db.votes["x-y"] == nil)
recv("V~1~rodrigo-azeroth,d," .. CLOCK, "Rodrigo-Azeroth")
check("own echo ignored", ns.db.votes["rodrigo-azeroth"] == nil)
check("one vote: no score shown", (ns.Summary("goodguy-azeroth") or ""):find("you: thumbs up") and not (ns.Summary("goodguy-azeroth") or ""):find("%%"), ns.Summary("goodguy-azeroth"))

-- rage voter: 4 thumbs down in one minute do not count
for i, n in ipairs({ "p1", "p2", "p3", "p4" }) do recv(("V~1~%s-azeroth,d,%d"):format(n, CLOCK + i), "Rager-Azeroth") end
up, down = ns.Score("p1-azeroth")
check("rage batch discounted", up == 0 and down == 0, up .. "/" .. down)
-- honest mixed voter: one down among ups still counts
recv(("V~1~p1-azeroth,d,%d;p2-azeroth,u,%d;p3-azeroth,u,%d"):format(CLOCK, CLOCK + 1, CLOCK + 2), "Fair-Azeroth")
up, down = ns.Score("p1-azeroth")
check("fair voter's single down counts", down == 1, up .. "/" .. down)


-- reasons: wire format, aggregation, negative needs two voters
recv("V~1~tagged-azeroth,u," .. CLOCK .. ",ac", "Alice-Azeroth")
recv("V~1~tagged-azeroth,u," .. CLOCK .. ",a", "Bob-Azeroth")
recv("V~1~tagged-azeroth,d," .. CLOCK .. ",a", "Carl-Azeroth")
check("reason counts", (ns.TagLine("tagged-azeroth") or ""):find("Friendly 2,") ~= nil and (ns.TagLine("tagged-azeroth") or ""):find("Skilled 1") ~= nil, ns.TagLine("tagged-azeroth"))
check("single negative reason hidden", not (ns.TagLine("tagged-azeroth") or ""):find("Ninja"))
recv("V~1~tagged-azeroth,d," .. CLOCK .. ",ab", "Dana-Azeroth")
check("negative reason shown once two agree", (ns.TagLine("tagged-azeroth") or ""):find("Ninja 2") ~= nil and not (ns.TagLine("tagged-azeroth") or ""):find("Toxic"), ns.TagLine("tagged-azeroth"))
recv("V~1~tagged2-azeroth,u," .. CLOCK .. ",abcd", "Alice-Azeroth")
check("more than 3 reasons dropped, vote kept", ns.db.votes["tagged2-azeroth"]["alice-azeroth"].g == nil)
recv("V~1~tagged3-azeroth,u," .. CLOCK .. ",zz", "Alice-Azeroth")
check("unknown reason letters rejected", ns.db.votes["tagged3-azeroth"] == nil)
check("own reasons in line", (ns.TagLine("goodguy-azeroth") or ""):find("Friendly 1,") ~= nil and (ns.TagLine("goodguy-azeroth") or ""):find("Skilled 1") ~= nil, ns.TagLine("goodguy-azeroth"))
-- popup flow: thumb -> reasons -> done
ns.UI.ShowRate({ { key = "flow-azeroth", name = "Flow-Azeroth", class = "MAGE", secs = 2000 } })
local row = ns.UI.rate.rows[1]
row.up._OnClick(row.up)
check("thumb saves the vote and opens reasons", ns.db.my["flow-azeroth"] and ns.db.my["flow-azeroth"].v == 1 and ns.UI.queue[1].mode == 1 and ns.UI.rate:IsShown())
row.chips[1]._OnClick(row.chips[1]); row.chips[6]._OnClick(row.chips[6])
row.done._OnClick(row.done)
check("done stores reasons and closes row", ns.db.my["flow-azeroth"].g == "af" and #ns.UI.queue == 0 and not ns.UI.rate:IsShown(), ns.db.my["flow-azeroth"].g)
ns.UI.ShowRate({ { key = "flow2-azeroth", name = "Flow2-Azeroth", class = "MAGE", secs = 2000 } })
row.down._OnClick(row.down)
for _, c in ipairs({ 1, 2, 3 }) do row.chips[c]._OnClick(row.chips[c]) end
check("third reason finishes the row", ns.db.my["flow2-azeroth"].g == "abc" and ns.db.my["flow2-azeroth"].v == -1 and #ns.UI.queue == 0)
ns.UI.ShowRate({ { key = "flow3-azeroth", name = "Flow3-Azeroth", class = "MAGE", secs = 2000 } })
row.up._OnClick(row.up); ns.UI.rate.close._OnClick(ns.UI.rate.close)
check("closing mid-reasons keeps the vote", ns.db.my["flow3-azeroth"] and ns.db.my["flow3-azeroth"].g == nil)

-- sync handshake: hearing a new peer triggers a Q whisper; answering a Q sends only my own votes
SENT = {}; Advance(10)
local q = sent("^Q~1~%d+$")
check("asks new peers for their votes by whisper", q and q.chan == "WHISPER", q and q.chan)
SENT = {}
recv("Q~1~0", "Newbie-Azeroth"); Advance(5)
local a = sent("^V~1~goodguy%-azeroth,u,")
check("answers Q with own votes only", a and a.chan == "WHISPER" and a.target == "Newbie-Azeroth" and not a.text:find("target%-azeroth"), a and a.text)
SENT = {}
recv("Q~1~" .. (CLOCK + 10), "Newbie2-Azeroth"); Advance(5)
check("nothing newer: no answer", sent("^V~") == nil)


-- neutral votes
recv("V~1~mid-azeroth,u," .. CLOCK, "Alice-Azeroth"); recv("V~1~mid-azeroth,u," .. CLOCK, "Bob-Azeroth")
recv("V~1~mid-azeroth,d," .. CLOCK, "Evan-Azeroth")
recv("V~1~mid-azeroth,n," .. CLOCK .. ",ce", "Dana-Azeroth"); recv("V~1~mid-azeroth,n," .. CLOCK .. ",c", "Fair-Azeroth")
local u2, d2, _, n2 = ns.Score("mid-azeroth")
check("neutral counted separately", u2 == 2 and d2 == 1 and n2 == 2, u2 .. "/" .. d2 .. "/" .. tostring(n2))
check("neutral does not move the percentage", (ns.Summary("mid-azeroth") or ""):find("67%% would group again") and (ns.Summary("mid-azeroth") or ""):find("3 votes, 2 neutral"), ns.Summary("mid-azeroth"))
check("neutral reasons need two voters", (ns.TagLine("mid-azeroth") or ""):find("Inexperienced 2") and not (ns.TagLine("mid-azeroth") or ""):find("Bit rude"), ns.TagLine("mid-azeroth"))
ns.UI.ShowRate({ { key = "meh-azeroth", name = "Meh-Azeroth", class = "MAGE", secs = 2000 } })
row.mid._OnClick(row.mid); row.chips[1]._OnClick(row.chips[1]); row.done._OnClick(row.done)
check("neutral vote with reason saved", ns.db.my["meh-azeroth"] and ns.db.my["meh-azeroth"].v == 0 and ns.db.my["meh-azeroth"].g == "a")
check("my neutral shows", (ns.Summary("meh-azeroth") or ""):find("you: neutral") ~= nil, ns.Summary("meh-azeroth"))
SENT = {}; Advance(20)
check("neutral sent as n", sent("^V~1~meh%-azeroth,n,%d+,a$") ~= nil)

-- directory gossip: names only, votes always pulled from their owner
SENT = {}
recv("Q~1~0", "Dana-Azeroth"); Advance(8)
local d = sent("^D~1~")
check("directory sent with Q answer", d and d.chan == "WHISPER" and d.target == "Dana-Azeroth" and d.text:find("Alice%-Azeroth") and not d.text:find("Dana%-Azeroth"), d and d.text)
check("directory carries no votes", d and not d.text:find(",[ud],"))
SENT = {}
recv("D~1~Zed-Azeroth;Yan-Stormrage;Alice-Azeroth;x;Rodrigo-Azeroth", "Dana-Azeroth")
check("2 unknown users queued (known, self, garbage skipped)", #ns.Sync.pull == 2, #ns.Sync.pull)
Advance(50)
local q1, q2 = nil, nil
for _, m in ipairs(SENT) do if m.text:find("^Q~1~0$") and m.target == "Zed-Azeroth" then q1 = m end; if m.text:find("^Q~1~0$") and m.target == "Yan-Stormrage" then q2 = m end end
check("listed users asked directly by whisper", q1 and q2 and q1.chan == "WHISPER")
recv("V~1~p9-azeroth,u," .. CLOCK, "Zed-Azeroth")
check("their answer is stored under their own name", ns.db.votes["p9-azeroth"] and ns.db.votes["p9-azeroth"]["zed-azeroth"] ~= nil)
recv("V~1~p9-azeroth,d," .. CLOCK, "Dana-Azeroth")
check("a relayer can only ever add one vote: their own", (function() local n = 0 for _ in pairs(ns.db.votes["p9-azeroth"]) do n = n + 1 end return n end)() == 2)
local function hidden(msg) for _, f in ipairs(FILTERS.CHAT_MSG_SYSTEM or {}) do if f(nil, "CHAT_MSG_SYSTEM", msg) then return true end end return false end
check("offline notice hidden for users we asked", hidden("No player named 'Yan-Stormrage' is currently playing.") and hidden("No player named 'Zed' is currently playing."))
check("other offline notices untouched", not hidden("No player named 'Somebodyelse' is currently playing."))
check("sync channel on by default", ns.db.settings.channel == true)

-- level 20 gate
LEVELS.Lowbie = 12; LEVELS.Altvoter = 5
GROUP = { { "Lowbie", "" }, { "Highbie", "" }, { "Altvoter", "" } }; Fire("GROUP_ROSTER_UPDATE"); Advance(31 * 60, 5); Leave()
check("under-20 player not offered for rating", #ns.UI.queue == 1 and ns.UI.queue[1].key == "highbie-azeroth", #ns.UI.queue)
ns.UI.queue = {}; ns.UI.RefreshRate()
ns.Vote("lowbie-azeroth", -1, { name = "Lowbie-Azeroth" })
check("cannot vote on under-20 player", ns.db.my["lowbie-azeroth"] == nil)
recv("V~1~p9-azeroth,u," .. CLOCK, "Altvoter-Azeroth")
check("vote from a level 5 alt rejected", ns.db.votes["p9-azeroth"]["altvoter-azeroth"] == nil)
MYLEVEL = 14
GROUP = { { "Someone", "" } }; Fire("GROUP_ROSTER_UPDATE"); Advance(31 * 60, 5); Leave()
check("no popup while I am under 20", not ns.UI.rate:IsShown())
ns.Vote("highbie-azeroth", 1, { name = "Highbie-Azeroth" })
check("my vote blocked while under 20", ns.db.my["highbie-azeroth"] == nil)
MYLEVEL = 42
-- flood limit
for i = 1, 60 do recv("H~1", "Spammer-Azeroth") end
check("flood limited", ns.Sync.stats.rejected >= 20, ns.Sync.stats.rejected)

-- thumbs down + ignore option
ns.db.settings.ignoreDown = true
ns.Vote("jerk-azeroth", -1, { name = "Jerk-Azeroth", class = "MAGE" })
check("ignore on thumbs down", IGNORED[1] == "Jerk-Azeroth")
ns.Vote("fake-none", 1, { name = "x", fake = true })
check("test rows cast no vote", ns.db.my["fake-none"] == nil)

-- warning when a badly rated player joins
PRINTS = {}
GROUP = { { "Jerk", "" } }; Fire("GROUP_ROSTER_UPDATE")
local warned = false
for _, p in ipairs(PRINTS) do if p:find("heads up") and p:find("Jerk") then warned = true end end
check("warns about thumbs-down player", warned)
Leave()

-- UI smoke
ns.UI.Test(); check("sample popup", ns.UI.rate:IsShown() and #ns.UI.queue == 4)
ns.UI.ToggleOptions(); ns.UI.options._OnShow(); ns.UI.options.acc = 0; ns.UI.options._OnUpdate(ns.UI.options, 2)
SlashCmdList.PEERREVIEW("sync"); SlashCmdList.PEERREVIEW("Target"); SlashCmdList.PEERREVIEW("help")
check("no runtime errors printed", errors() == nil, errors())
LOG(fails == 0 and "ALL PASSED" or (fails .. " FAILED"))

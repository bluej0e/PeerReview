-- Peer Review: interface (rating popup, settings window, minimap button, tooltip lines)
local ADDON, ns = ...
local UI = { queue = {} }
ns.UI = UI

-- Dark leather and gold: the game's own tooltip frame, with flat cards inside it.
local C = {
  bg = { .06, .045, .03, 1 }, edge = { .80, .63, .28, 1 },
  card = { .13, .105, .075, 1 }, line = { .34, .27, .15, 1 }, input = { .04, .03, .02, 1 },
  text = { .96, .93, .86 }, dim = { .68, .62, .52 },
  good = { .38, .85, .48 }, bad = { 1, .38, .33 }, gold = { 1, .82, .25 },
}
-- Solid fill (the game's tooltip background is see-through), with the tooltip border around it.
local WINDOW = { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } }
local FLAT = { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }
local THUMBS = {
  [1] = "Interface\\AddOns\\PeerReview\\thumb_up",
  [0] = "Interface\\AddOns\\PeerReview\\thumb_mid",
  [-1] = "Interface\\AddOns\\PeerReview\\thumb_down",
}
local LOGO = "Interface\\AddOns\\PeerReview\\logo"
local ROWS, ROW_H, WIDTH, HEAD = 6, 48, 380, 54
local ROW_W = WIDTH - 16
local VOTE_COLOR = { [1] = C.good, [0] = C.gold, [-1] = C.bad }

---------------------------------------------------------------- widgets
local function Window(name)
  local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
  f:SetBackdrop(WINDOW)
  f:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], C.bg[4])
  f:SetBackdropBorderColor(C.edge[1], C.edge[2], C.edge[3], 1)
  f:SetFrameStrata("DIALOG")
  return f
end

local function Card(parent)
  local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  f:SetBackdrop(FLAT)
  f:SetBackdropColor(C.card[1], C.card[2], C.card[3], C.card[4])
  f:SetBackdropBorderColor(C.line[1], C.line[2], C.line[3], 1)
  return f
end

local function Label(parent, text, size, col)
  local font = size == "small" and "GameFontHighlightSmall" or size == "large" and "GameFontNormalLarge" or "GameFontHighlight"
  local fs = parent:CreateFontString(nil, "OVERLAY", font)
  fs:SetText(text or "")
  col = col or (size == "large" and C.gold or C.text)
  fs:SetTextColor(col[1], col[2], col[3])
  fs:SetJustifyH("LEFT")
  return fs
end

-- Title with the thumb mark and a thin gold rule under the header.
local function Header(f, sub)
  local mark = f:CreateTexture(nil, "ARTWORK")
  mark:SetSize(24, 24)
  mark:SetPoint("TOPLEFT", 11, -9)
  mark:SetTexture(LOGO)
  f.title = Label(f, "Peer Review", "large")
  f.title:SetPoint("TOPLEFT", 39, -11)
  f.sub = Label(f, sub or "", "small", C.dim)
  f.sub:SetPoint("TOPLEFT", 39, -30)
  local rule = f:CreateTexture(nil, "ARTWORK")
  rule:SetColorTexture(C.edge[1], C.edge[2], C.edge[3], .35)
  rule:SetHeight(1)
  rule:SetPoint("TOPLEFT", 10, -(HEAD - 6))
  rule:SetPoint("TOPRIGHT", -10, -(HEAD - 6))
end

local function Button(parent, text, w, h, fn)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(w, h or 22)
  b:SetBackdrop(FLAT)
  b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.label:SetPoint("CENTER")
  b.label:SetText(text or "")
  local function Paint(self)
    local hot = self.hover
    self:SetBackdropColor(hot and .30 or .20, hot and .21 or .145, hot and .10 or .08, 1)
    local br = hot and C.edge or C.line
    self:SetBackdropBorderColor(br[1], br[2], br[3], 1)
    local tc = hot and C.gold or C.text
    self.label:SetTextColor(tc[1], tc[2], tc[3])
  end
  b:SetScript("OnEnter", function(self) self.hover = true; Paint(self) end)
  b:SetScript("OnLeave", function(self) self.hover = false; Paint(self) end)
  if fn then b:SetScript("OnClick", fn) end
  Paint(b)
  return b
end

-- "Made by" line. A game window cannot open a web page, so the in-game version of a profile
-- link is a click that opens a whisper to the author.
local AUTHOR = "Rogar Thunderfury"
local function Credit(parent)
  local b = CreateFrame("Button", nil, parent)
  b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.label:SetPoint("CENTER")
  b.label:SetText("Made by " .. AUTHOR)
  b:SetSize(170, 14)
  local function Paint(self)
    if self.hover then self.label:SetTextColor(.62, .82, 1) else self.label:SetTextColor(.25, .61, 1) end
  end
  b:SetScript("OnEnter", function(self)
    self.hover = true; Paint(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(AUTHOR, .25, .61, 1)
    GameTooltip:AddLine("Click to whisper the author.", .8, .8, .8)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function(self) self.hover = false; Paint(self); GameTooltip:Hide() end)
  b:SetScript("OnClick", function()
    if ChatFrameUtil and ChatFrameUtil.SendTell then pcall(ChatFrameUtil.SendTell, AUTHOR)
    elseif ChatFrame_SendTell then pcall(ChatFrame_SendTell, AUTHOR) end
  end)
  Paint(b)
  return b
end

-- Small square button with a picture instead of a word.
local function IconButton(parent, texture, size, fn)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size, size)
  b.tex = b:CreateTexture(nil, "ARTWORK")
  b.tex:SetAllPoints()
  b.tex:SetTexture(texture)
  b.tex:SetAlpha(.75)
  b:SetScript("OnEnter", function(self) self.tex:SetAlpha(1) end)
  b:SetScript("OnLeave", function(self) self.tex:SetAlpha(.75) end)
  if fn then b:SetScript("OnClick", fn) end
  return b
end

local function Tip(widget, title, body)
  widget:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 1, 1)
    if body then GameTooltip:AddLine(body, .8, .8, .8, true) end
    GameTooltip:Show()
  end)
  widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Check(parent, text, key, after)
  local c = CreateFrame("Button", nil, parent)
  c:SetSize(18, 18)
  c.box = CreateFrame("Frame", nil, c, "BackdropTemplate")
  c.box:SetBackdrop(FLAT)
  c.box:SetBackdropColor(C.input[1], C.input[2], C.input[3], 1)
  c.box:SetBackdropBorderColor(C.line[1], C.line[2], C.line[3], 1)
  c.box:SetAllPoints()
  c.box:EnableMouse(false)
  c.mark = c.box:CreateTexture(nil, "OVERLAY")
  c.mark:SetPoint("TOPLEFT", 4, -4)
  c.mark:SetPoint("BOTTOMRIGHT", -4, 4)
  c.mark:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
  c.text = Label(c, text or "")
  c.text:SetPoint("LEFT", c, "RIGHT", 8, 0)
  c:SetHitRectInsets(0, -300, 0, 0) -- the label is clickable too
  function c.Load() c.mark:SetShown(ns.db.settings[key] and true or false) end
  c:SetScript("OnClick", function()
    ns.db.settings[key] = not ns.db.settings[key]
    c.Load()
    if after then after(ns.db.settings[key]) end
  end)
  return c
end

local function Movable(f, posKey)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint(1)
    ns.db[posKey] = { point, rel, x, y }
  end)
  local p = ns.db[posKey]
  f:ClearAllPoints()
  if type(p) == "table" and p[1] then
    f:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
    return true
  end
  return false
end

local function Sound(kit)
  if not ns.db.settings.sound or not PlaySound then return end
  pcall(PlaySound, kit)
end
local CLICK = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856

local function ClassColor(class)
  local tbl = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
  local c = class and tbl and tbl[class]
  if c then return c.r, c.g, c.b end
  return C.text[1], C.text[2], C.text[3]
end

local function SetClassIcon(tex, class)
  local co = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
  if co then
    tex:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
    tex:SetTexCoord(co[1], co[2], co[3], co[4])
  else
    tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    tex:SetTexCoord(.08, .92, .08, .92)
  end
end

local function Together(secs)
  local m = math.floor((secs or 0) / 60 + 0.5)
  if m < 1 then return "under a minute together" end
  if m >= 60 then return ("%dh %02dm together"):format(math.floor(m / 60), m % 60) end
  return m .. " min together"
end

---------------------------------------------------------------- rating popup
local THUMB_TIP = { [1] = "Would group again", [0] = "Neutral", [-1] = "Would not group again" }

local function ThumbButton(parent, v)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(32, 32)
  b.tex = b:CreateTexture(nil, "ARTWORK")
  b.tex:SetPoint("TOPLEFT", 1, -1)
  b.tex:SetPoint("BOTTOMRIGHT", -1, 1)
  b.tex:SetTexture(THUMBS[v])
  local col = VOTE_COLOR[v]
  local function Paint(self)
    local a = (self.hover or self.picked) and 1 or .85
    self.tex:SetVertexColor(1, 1, 1, a)
    self.tex:SetDesaturated(self.dim and not self.hover or false)
  end
  b.Paint = Paint
  b:SetScript("OnEnter", function(self)
    self.hover = true; Paint(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(THUMB_TIP[v], col[1], col[2], col[3])
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function(self) self.hover = false; Paint(self); GameTooltip:Hide() end)
  b:SetScript("OnClick", function(self)
    local it = self:GetParent().item
    if not it then return end
    Sound(CLICK)
    GameTooltip:Hide()
    -- The vote is saved right here. The reasons step that follows is optional.
    if not (it.fake or ns.Vote(it.key, v, it)) then UI.Drop(it.key) return end
    it.mode, it.picks = v, {}
    UI.RefreshRate()
  end)
  Paint(b)
  return b
end

-- Second step of a row: six reasons for the thumb just given, pick up to three, then Done.
local function FinishTags(it)
  local letters = ""
  for i = 1, 6 do if it.picks[i] then letters = letters .. ns.LETTERS:sub(i, i) end end
  if not it.fake then ns.SetTags(it.key, letters) end
  UI.Drop(it.key)
end

local CHIP_W, CHIP_H = 98, 19
local function Chip(row, i)
  local c = CreateFrame("Button", nil, row.tags, "BackdropTemplate")
  c:SetSize(CHIP_W, CHIP_H)
  c:SetBackdrop(FLAT)
  c.icon = c:CreateTexture(nil, "ARTWORK")
  c.icon:SetSize(15, 15)
  c.icon:SetPoint("LEFT", 2, 0)
  c.icon:SetTexCoord(.08, .92, .08, .92)
  c.label = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  c.label:SetPoint("LEFT", c.icon, "RIGHT", 4, 0)
  c.label:SetPoint("RIGHT", -2, 0)
  c.label:SetJustifyH("LEFT")
  c.label:SetWordWrap(false)
  function c.Paint(self)
    local it = row.item
    local on = it and it.picks and it.picks[i]
    local col = it and VOTE_COLOR[it.mode] or C.good
    if on then
      self:SetBackdropColor(col[1] * .16, col[2] * .16, col[3] * .16, 1)
      self:SetBackdropBorderColor(col[1], col[2], col[3], 1)
      self.label:SetTextColor(col[1], col[2], col[3])
      self.icon:SetDesaturated(false); self.icon:SetAlpha(1)
    else
      local hot = self.hover
      self:SetBackdropColor(hot and .26 or .17, hot and .19 or .125, hot and .10 or .07, 1)
      self:SetBackdropBorderColor(C.line[1], C.line[2], C.line[3], 1)
      self.label:SetTextColor(C.text[1], C.text[2], C.text[3])
      self.icon:SetDesaturated(not hot); self.icon:SetAlpha(hot and 1 or .8)
    end
  end
  c:SetScript("OnEnter", function(self) self.hover = true; self:Paint() end)
  c:SetScript("OnLeave", function(self) self.hover = false; self:Paint() end)
  c:SetScript("OnClick", function(self)
    local it = row.item
    if not it or not it.picks then return end
    local n = 0
    for _ in pairs(it.picks) do n = n + 1 end
    if it.picks[i] then it.picks[i] = nil
    elseif n < ns.MAX_TAGS then it.picks[i] = true; n = n + 1
    else return end
    Sound(CLICK)
    if it.picks[i] and n >= ns.MAX_TAGS then FinishTags(it) return end
    for _, chip in ipairs(row.chips) do chip:Paint() end
  end)
  return c
end

local function BuildRow(f, i)
  local r = Card(f)
  r:SetSize(ROW_W, ROW_H - 4)
  r:SetPoint("TOPLEFT", 8, -HEAD - (i - 1) * ROW_H)
  r.stripe = r:CreateTexture(nil, "ARTWORK")
  r.stripe:SetWidth(3)
  r.stripe:SetPoint("TOPLEFT", 1, -1)
  r.stripe:SetPoint("BOTTOMLEFT", 1, 1)

  -- step 1: who, and the three thumbs
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(30, 30)
  r.icon:SetPoint("LEFT", 10, 0)
  r.never = IconButton(r, "Interface\\Buttons\\UI-GroupLoot-Pass-Up", 20, function(self)
    local it = self:GetParent().item
    if not it then return end
    if not it.fake then ns.Mute(it.key) end
    GameTooltip:Hide()
    UI.Drop(it.key)
  end)
  r.never:SetPoint("RIGHT", -7, 0)
  Tip(r.never, "Never ask me about this player", "No vote is cast. Undo it in the settings.")
  r.skip = IconButton(r, "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up", 24, function(self)
    local it = self:GetParent().item
    if not it then return end
    ns.Park(it)
    GameTooltip:Hide()
    UI.Drop(it.key)
  end)
  r.skip:SetPoint("RIGHT", r.never, "LEFT", -3, 0)
  Tip(r.skip, "Skip for now", "No vote is cast. You can still rate them later today from the minimap button.")
  r.down = ThumbButton(r, -1)
  r.down:SetPoint("RIGHT", r.skip, "LEFT", -5, 0)
  r.mid = ThumbButton(r, 0)
  r.mid:SetPoint("RIGHT", r.down, "LEFT", -4, 0)
  r.up = ThumbButton(r, 1)
  r.up:SetPoint("RIGHT", r.mid, "LEFT", -4, 0)
  r.name = Label(r, "")
  r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, -1)
  r.name:SetPoint("RIGHT", r.up, "LEFT", -6, 0)
  r.name:SetWordWrap(false)
  r.info = Label(r, "", "small", C.dim)
  r.info:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, 1)
  r.info:SetPoint("RIGHT", r.up, "LEFT", -6, 0)
  r.info:SetWordWrap(false)

  -- step 2: reasons
  r.tags = CreateFrame("Frame", nil, r)
  r.tags:SetAllPoints()
  r.tags:Hide()
  r.chips = {}
  for c = 1, 6 do
    local chip = Chip(r, c)
    local col, line = (c - 1) % 3, math.floor((c - 1) / 3)
    chip:SetPoint("TOPLEFT", 8 + col * (CHIP_W + 3), -2 - line * (CHIP_H + 2))
    r.chips[c] = chip
  end
  r.done = Button(r.tags, "Done", 46, CHIP_H * 2 + 2, function(self)
    local it = self:GetParent():GetParent().item
    if it then FinishTags(it) end
  end)
  r.done:SetPoint("TOPRIGHT", -5, -2)
  Tip(r.done, "Done", "Pick up to three reasons, or none.")

  r:EnableMouse(true)
  r:SetScript("OnEnter", function(self)
    if not self.item or self.item.mode then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(ns.Short(self.item.name), ClassColor(self.item.class))
    GameTooltip:AddLine(ns.Summary(self.item.key) or "No votes yet", .8, .8, .8)
    local why = ns.TagLine(self.item.key)
    if why then GameTooltip:AddLine(why) end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return r
end

local function BuildRate()
  local f = Window("PeerReviewRateFrame")
  UI.rate = f
  f:SetWidth(WIDTH)
  if not Movable(f, "ratePos") then f:SetPoint("CENTER", UIParent, "CENTER", 0, 180) end
  f:Hide()
  Header(f, "Would you group with them again?")
  f.close = Button(f, "x", 20, 20, function()
    for _, it in ipairs(UI.queue) do ns.Park(it) end
    UI.queue = {}
    UI.RefreshRate()
  end)
  f.close:SetPoint("TOPRIGHT", -10, -10)
  Tip(f.close, "Close", "Votes already cast are kept. Skipped players stay under /peer pending for a day.")
  f.rows = {}
  for i = 1, ROWS do f.rows[i] = BuildRow(f, i) end
  f.more = Label(f, "", "small", C.dim)
  f.more:SetPoint("BOTTOMLEFT", 14, 11)
end

function UI.RefreshRate()
  local f = UI.rate
  if not f then return end
  local q = UI.queue
  if #q == 0 then f:Hide() return end
  local shown = math.min(#q, ROWS)
  for i = 1, ROWS do
    local r, it = f.rows[i], q[i]
    r.item = it
    if it then
      local tagging = it.mode ~= nil
      local cr, cg, cb = ClassColor(it.class)
      local sc = tagging and VOTE_COLOR[it.mode] or nil
      if sc then r.stripe:SetColorTexture(sc[1], sc[2], sc[3], 1) else r.stripe:SetColorTexture(cr, cg, cb, 1) end
      r.icon:SetShown(not tagging); r.name:SetShown(not tagging); r.info:SetShown(not tagging)
      r.up:SetShown(not tagging); r.mid:SetShown(not tagging); r.down:SetShown(not tagging)
      r.never:SetShown(not tagging); r.skip:SetShown(not tagging)
      r.tags:SetShown(tagging)
      if tagging then
        for c, chip in ipairs(r.chips) do
          chip.label:SetText(ns.TAGS[it.mode][c])
          chip.icon:SetTexture(ns.TAG_ICONS[it.mode][c])
          chip:Paint()
        end
      else
        SetClassIcon(r.icon, it.class)
        r.name:SetText(ns.Short(it.name))
        r.name:SetTextColor(cr, cg, cb)
        local info = it.note or (it.boss and (Together(it.secs) .. ", boss kill") or Together(it.secs))
        if it.left then
          local sum = ns.Summary(it.key)
          info = sum and ("just left  " .. sum) or ("just left, " .. info)
        end
        if not it.fake and (ns.Sync.peers[it.key] or ns.db.seen[it.key]) then
          info = info .. "  |cffcca147uses Peer Review|r"
        end
        r.info:SetText(info)
        local mine = ns.db.my[it.key]
        r.up.picked = mine and mine.v == 1 or false
        r.mid.picked = mine and mine.v == 0 or false
        r.down.picked = mine and mine.v == -1 or false
        local live = ns.Live(mine)
        r.up.dim = live and mine.v ~= 1 or false
        r.mid.dim = live and mine.v ~= 0 or false
        r.down.dim = live and mine.v ~= -1 or false
        r.up:Paint(); r.mid:Paint(); r.down:Paint()
      end
      r:Show()
    else
      r:Hide()
    end
  end
  local first = q[1]
  if #q == 1 and first.left then
    f.sub:SetText(ns.Short(first.name) .. " just left. Group with them again?")
  else
    f.sub:SetText("Would you group with them again?")
  end
  local extra = #q - shown
  f.more:SetText(extra > 0 and ("+" .. extra .. " more after these") or "")
  f:SetHeight(HEAD + shown * ROW_H + (extra > 0 and 28 or 8))
  f:Show()
end

function UI.Drop(key)
  for i, it in ipairs(UI.queue) do
    if it.key == key then table.remove(UI.queue, i) break end
  end
  UI.RefreshRate()
  if UI.list and UI.list:IsShown() then UI.RefreshList() end
end

-- Adds players to the popup. Waits for combat to end before showing.
function UI.ShowRate(list)
  if #list > 0 then ns.Log(("popup: %d player(s)%s"):format(#list, list[1].fake and " (preview)" or "")) end
  local have = {}
  for _, it in ipairs(UI.queue) do have[it.key] = true end
  for _, it in ipairs(list) do
    if not have[it.key] then UI.queue[#UI.queue + 1] = it; have[it.key] = true end
  end
  if #UI.queue == 0 then return end
  if InCombatLockdown and InCombatLockdown() then UI.waiting = true return end
  local was = UI.rate and UI.rate:IsShown()
  UI.RefreshRate()
  if not was then Sound(SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_OPEN or 875) end
end

function UI.AfterCombat()
  if UI.waiting then UI.waiting = false; UI.ShowRate({}) end
end

-- Manual rating of whoever is in the current group, ignoring the time rules.
function UI.RateNow()
  ns.Tracker.Scan()
  local list = ns.SessionList(true)
  if #list == 0 then list = ns.PendingList() end
  if #list == 0 then ns.Print("nobody to rate. This lists your current group, or players you skipped today.") return false end
  UI.ShowRate(list)
  return true
end

-- Minimap click: rate if there is someone to rate, otherwise show your ratings.
function UI.RateOrList()
  ns.Tracker.Scan()
  if #ns.SessionList(true) > 0 or #ns.PendingList() > 0 then UI.RateNow() else UI.ToggleList() end
end

function UI.ShowPending()
  local list = ns.PendingList()
  if #list == 0 then ns.Print("no skipped players from the last day.") return end
  UI.ShowRate(list)
end

-- Sample rows so players can see the popup and drag it where they want it. Nothing is saved.
function UI.Preview()
  UI.ShowRate({
    { key = "test1-none", name = "Thrallson-Test", class = "SHAMAN", secs = 2520, boss = true, fake = true },
    { key = "test2-none", name = "Stabbymcstab-Test", class = "ROGUE", secs = 2460, boss = true, fake = true },
    { key = "test3-none", name = "Healbot-Test", class = "PRIEST", secs = 1900, fake = true },
    { key = "test4-none", name = "Ninjalooter-Test", class = "HUNTER", secs = 640, fake = true },
  })
end

UI.Test = UI.Preview

---------------------------------------------------------------- my ratings
local LIST_ROWS, LIST_H, LIST_W, ME_H = 10, 30, 480, 32
local VOTE_WORD = { [1] = "up", [0] = "neutral", [-1] = "down" }

local function BuildList()
  local f = Window("PeerReviewListFrame")
  UI.list = f
  f:SetSize(LIST_W, HEAD + ME_H + LIST_ROWS * LIST_H + 44)
  if not Movable(f, "listPos") then f:SetPoint("CENTER", UIParent, "CENTER", 0, 40) end
  f:Hide()
  if UISpecialFrames then table.insert(UISpecialFrames, "PeerReviewListFrame") end
  Header(f, "")
  local close = Button(f, "x", 20, 20, function() f:Hide() end)
  close:SetPoint("TOPRIGHT", -10, -10)
  -- your own score, as other players have rated you
  f.mine = Card(f)
  f.mine:SetSize(LIST_W - 16, ME_H - 5)
  f.mine:SetPoint("TOPLEFT", 8, -HEAD)
  f.mine:SetBackdropBorderColor(C.edge[1], C.edge[2], C.edge[3], .6)
  f.mine.text = Label(f.mine, "")
  f.mine.text:SetPoint("LEFT", 10, 0)
  f.mine.text:SetPoint("RIGHT", -10, 0)
  f.mine.text:SetWordWrap(false)
  f.mine:EnableMouse(true)
  f.mine:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Your rating", 1, .82, .25)
    GameTooltip:AddLine("Built from votes other Peer Review users have shared with you. A score appears once 3 players have rated you.", .8, .8, .8, true)
    local _, why = ns.MyRating()
    if why then GameTooltip:AddLine(why) end
    GameTooltip:Show()
  end)
  f.mine:SetScript("OnLeave", function() GameTooltip:Hide() end)

  f.page = 1
  f.rows = {}
  for i = 1, LIST_ROWS do
    local r = Card(f)
    r:SetSize(LIST_W - 16, LIST_H - 3)
    r:SetPoint("TOPLEFT", 8, -HEAD - ME_H - (i - 1) * LIST_H)
    r.stripe = r:CreateTexture(nil, "ARTWORK")
    r.stripe:SetWidth(3)
    r.stripe:SetPoint("TOPLEFT", 1, -1)
    r.stripe:SetPoint("BOTTOMLEFT", 1, 1)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(20, 20)
    r.icon:SetPoint("LEFT", 9, 0)
    r.thumb = r:CreateTexture(nil, "ARTWORK")
    r.thumb:SetSize(16, 16)
    r.thumb:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.remove = Button(r, "Remove", 58, 20, function(self)
      local it = self:GetParent().item
      if it then ns.Unvote(it.key); UI.RefreshList() end
    end)
    r.remove:SetPoint("RIGHT", -5, 0)
    Tip(r.remove, "Remove my vote", "Takes your vote back. Other players drop it the next time they hear from you.")
    r.change = Button(r, "Change", 54, 20, function(self)
      local it = self:GetParent().item
      if it then UI.ShowRate({ { key = it.key, name = it.name, class = it.class, secs = 0, note = "changing your vote" } }) end
    end)
    r.change:SetPoint("RIGHT", r.remove, "LEFT", -4, 0)
    r.name = Label(r, "")
    r.name:SetPoint("LEFT", r.thumb, "RIGHT", 7, 0)
    r.name:SetWidth(132)
    r.name:SetWordWrap(false)
    r.why = Label(r, "", "small", C.dim)
    r.why:SetPoint("LEFT", r.name, "RIGHT", 6, 0)
    r.why:SetPoint("RIGHT", r.change, "LEFT", -6, 0)
    r.why:SetWordWrap(false)
    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self)
      if not self.item then return end
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:SetText(ns.Short(self.item.name), ClassColor(self.item.class))
      GameTooltip:AddLine(ns.Summary(self.item.key) or "No votes yet", .8, .8, .8)
      local why = ns.TagLine(self.item.key)
      if why then GameTooltip:AddLine(why) end
      GameTooltip:AddLine(date and date("Voted %d %b %Y", self.item.t) or "", .68, .62, .52)
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.rows[i] = r
  end
  f.empty = Label(f, "You haven't rated anyone yet. Ratings appear here after your first group.", nil, C.dim)
  f.empty:SetPoint("TOPLEFT", 16, -HEAD - ME_H - 10)
  f.empty:SetWidth(LIST_W - 32)
  f.pageText = Label(f, "", "small", C.dim)
  f.pageText:SetPoint("BOTTOM", 0, 26)
  local credit = Credit(f)
  credit:SetPoint("BOTTOM", 0, 8)
  f.prev = Button(f, "Newer", 64, 22, function() f.page = math.max(1, f.page - 1); UI.RefreshList() end)
  f.prev:SetPoint("BOTTOMLEFT", 10, 12)
  f.next = Button(f, "Older", 64, 22, function() f.page = f.page + 1; UI.RefreshList() end)
  f.next:SetPoint("BOTTOMRIGHT", -10, 12)
  f:SetScript("OnShow", function() f.page = 1; UI.RefreshList() end)
end

function UI.RefreshList()
  local f = UI.list
  if not f then return end
  local list = ns.MyList()
  local pages = math.max(1, math.ceil(#list / LIST_ROWS))
  f.page = math.min(f.page, pages)
  f.sub:SetText(#list == 1 and "You have rated 1 player." or ("You have rated " .. #list .. " players."))
  local mine = ns.MyRating()
  f.mine.text:SetText("|cffffd140Your rating|r   " .. (mine or "|cffada085no votes yet|r"))
  f.empty:SetShown(#list == 0)
  for i = 1, LIST_ROWS do
    local r, it = f.rows[i], list[(f.page - 1) * LIST_ROWS + i]
    r.item = it
    if it then
      local col = VOTE_COLOR[it.v]
      r.stripe:SetColorTexture(col[1], col[2], col[3], 1)
      SetClassIcon(r.icon, it.class)
      r.thumb:SetTexture(THUMBS[it.v])
      r.name:SetText(ns.Short(it.name))
      r.name:SetTextColor(ClassColor(it.class))
      local why = ns.ReasonText(it.v, it.g)
      r.why:SetText(why ~= "" and why or (it.v == 0 and "neutral" or ("thumbs " .. VOTE_WORD[it.v])))
      r:Show()
    else
      r:Hide()
    end
  end
  f.pageText:SetText(pages > 1 and ("page " .. f.page .. " of " .. pages) or "")
  f.prev:SetShown(f.page > 1)
  f.next:SetShown(f.page < pages)
end

function UI.ToggleList()
  if not UI.list then return end
  UI.list:SetShown(not UI.list:IsShown())
  if UI.list:IsShown() then UI.RefreshList() end
end

---------------------------------------------------------------- feedback
local LINKS = {
  { "Report a bug or suggest something (GitHub):", "https://github.com/bluej0e/PeerReview/issues/new" },
  { "Leave a comment (CurseForge):", "https://www.curseforge.com/wow/addons/peer-review-player-ratings" },
}

-- A game window cannot open a web page, so the links are shown ready to copy.
local function CopyBox(parent, text, width)
  local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
  e:SetSize(width, 22)
  e:SetBackdrop(FLAT)
  e:SetBackdropColor(C.input[1], C.input[2], C.input[3], 1)
  e:SetBackdropBorderColor(C.line[1], C.line[2], C.line[3], 1)
  e:SetFontObject("GameFontHighlightSmall")
  e:SetTextInsets(6, 6, 0, 0)
  e:SetAutoFocus(false)
  e.value = text
  e:SetText(text)
  e:SetCursorPosition(0)
  e:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  e:SetScript("OnMouseUp", function(self) self:SetFocus(); self:HighlightText() end)
  e:SetScript("OnTextChanged", function(self, user)
    if user then self:SetText(self.value); self:HighlightText() end
  end)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  return e
end

local function BuildFeedback()
  local f = Window("PeerReviewFeedbackFrame")
  UI.feedback = f
  f:SetWidth(430)
  if not Movable(f, "feedbackPos") then f:SetPoint("CENTER", UIParent, "CENTER", 0, 60) end
  f:Hide()
  if UISpecialFrames then table.insert(UISpecialFrames, "PeerReviewFeedbackFrame") end
  Header(f, "Click a link, press Ctrl+C, then paste it in your browser.")
  local close = Button(f, "x", 20, 20, function() f:Hide() end)
  close:SetPoint("TOPRIGHT", -10, -10)
  local y = -(HEAD + 4)
  for _, link in ipairs(LINKS) do
    local l = Label(f, link[1], "small", C.dim)
    l:SetPoint("TOPLEFT", 14, y)
    local box = CopyBox(f, link[2], 402)
    box:SetPoint("TOPLEFT", 14, y - 16)
    y = y - 48
  end
  local l = Label(f, "Reporting a bug? Copy this line into it:", "small", C.dim)
  l:SetPoint("TOPLEFT", 14, y)
  f.info = CopyBox(f, "", 402)
  f.info:SetPoint("TOPLEFT", 14, y - 16)
  y = y - 48
  f:SetHeight(-y + 8)
  f:SetScript("OnShow", function()
    local client = ""
    if type(GetBuildInfo) == "function" then
      local ok, v, b = pcall(GetBuildInfo)
      if ok then client = (" | game %s (%s)"):format(tostring(v), tostring(b)) end
    end
    local text = ("Peer Review %s%s | other users seen: %d"):format(ns.VERSION, client, ns.Sync.PeerCount())
    f.info.value = text
    f.info:SetText(text)
    f.info:SetCursorPosition(0)
  end)
end

function UI.ToggleFeedback()
  if not UI.feedback then return end
  UI.feedback:SetShown(not UI.feedback:IsShown())
end

---------------------------------------------------------------- settings window
local OPT_W = 460

local function Stepper(parent)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize(OPT_W - 28, 22)
  holder.text = Label(holder, "")
  holder.text:SetPoint("LEFT", 60, 0)
  local function Index()
    local cur, best = ns.db.settings.minMinutes or 0, 1
    for i, v in ipairs(ns.STEPS) do if v <= cur then best = i end end
    return best
  end
  function holder.Load()
    local v = ns.STEPS[Index()]
    holder.text:SetText(v == 0 and "Ask about anyone I grouped with"
      or ("Ask after |cffffd140%d min|r grouped with a player"):format(v))
  end
  local minus = Button(holder, "-", 24, 22, function()
    ns.db.settings.minMinutes = ns.STEPS[math.max(1, Index() - 1)]; holder.Load()
  end)
  minus:SetPoint("LEFT", 0, 0)
  local plus = Button(holder, "+", 24, 22, function()
    ns.db.settings.minMinutes = ns.STEPS[math.min(#ns.STEPS, Index() + 1)]; holder.Load()
  end)
  plus:SetPoint("LEFT", minus, "RIGHT", 4, 0)
  return holder
end

local function BuildOptions()
  local f = Window("PeerReviewOptionsFrame")
  UI.options = f
  f:SetWidth(OPT_W)
  if not Movable(f, "optPos") then f:SetPoint("CENTER") end
  f:Hide()
  if UISpecialFrames then table.insert(UISpecialFrames, "PeerReviewOptionsFrame") end
  Header(f, "Votes count from level " .. ns.MIN_LEVEL .. " and expire after 180 days.")
  local close = Button(f, "x", 20, 20, function() f:Hide() end)
  close:SetPoint("TOPRIGHT", -10, -10)

  f.items = {}
  local y = -(HEAD + 6)
  local function Head(text)
    local h = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h:SetText(text)
    h:SetPoint("TOPLEFT", 14, y)
    y = y - 20
  end
  local function Add(widget, step)
    widget:SetPoint("TOPLEFT", 14, y)
    f.items[#f.items + 1] = widget
    y = y - (step or 24)
  end

  Head("WHEN TO ASK")
  Add(Stepper(f), 28)
  Add(Check(f, "A boss kill together always counts", "bossCounts"))
  Add(Check(f, "Only ask about dungeon and raid groups", "instanceOnly"))
  Add(Check(f, "Ask again about players I already rated", "reask"))
  Add(Check(f, "Skip players on my friends list", "skipFriends"))
  Add(Check(f, "Skip my guildmates", "skipGuild"), 34)

  Head("WHAT TO SHOW")
  Add(Check(f, "Ratings in player tooltips", "tooltip"))
  Add(Check(f, "Chat warning when a badly rated player joins", "warn"))
  Add(Check(f, "Sound when the popup opens", "sound"))
  Add(Check(f, "Thumbs down also ignores the player", "ignoreDown"), 34)

  Head("SHARING")
  local share = Check(f, "Share my votes and receive others'", "sync", function(on)
    if on then ns.Sync.JoinChannel() else ns.Sync.LeaveChannel() end
  end)
  Tip(share, "Sharing", "Votes travel between Peer Review users through your guild, your group and a hidden realm-wide channel. Nothing is posted in chat.")
  Add(share, 32)

  f.status = Label(f, "", "small", C.dim)
  f.status:SetPoint("TOPLEFT", 14, y)
  f.status:SetWidth(OPT_W - 28)
  f.status:SetHeight(26)
  f.status:SetJustifyV("TOP")
  y = y - 34

  local mine = Button(f, "My ratings", 92, 22, function() UI.ToggleList() end)
  mine:SetPoint("TOPLEFT", 14, y)
  local now = Button(f, "Rate group", 88, 22, function() UI.RateNow() end)
  now:SetPoint("LEFT", mine, "RIGHT", 6, 0)
  local test = Button(f, "Preview popup", 100, 22, function() UI.Preview() end)
  Tip(test, "Preview the popup", "Shows the rating popup with sample players. Drag it where you want it; it opens there from now on. Nothing is saved.")
  test:SetPoint("LEFT", now, "RIGHT", 6, 0)
  f.unmute = Button(f, "", 128, 22, function()
    ns.db.muted = {}
    ns.Print("never-ask list cleared.")
  end)
  f.unmute:SetPoint("LEFT", test, "RIGHT", 6, 0)
  Tip(f.unmute, "Clear the never-ask list", "Players you marked \"never\" can show up in the popup again.")
  y = y - 30
  local fb = Button(f, "Feedback or report a bug", 190, 22, function() UI.ToggleFeedback() end)
  fb:SetPoint("TOPLEFT", 14, y)
  local credit = Credit(f)
  credit:SetPoint("TOPRIGHT", -14, y - 4)
  y = y - 22
  f:SetHeight(-y + 14)

  f:SetScript("OnShow", function()
    for _, w in ipairs(f.items) do if w.Load then w.Load() end end
  end)
  f:SetScript("OnUpdate", function(self, dt)
    self.acc = (self.acc or 1) + dt
    if self.acc < 1 then return end
    self.acc = 0
    local mine, players = ns.Counts()
    local muted = 0
    for _ in pairs(ns.db.muted) do muted = muted + 1 end
    self.unmute.label:SetText("Clear never list (" .. muted .. ")")
    self.status:SetText(("%s\nYou rated %d player%s. Votes from others cover %d player%s."):format(
      ns.Sync.Status(), mine, mine == 1 and "" or "s", players, players == 1 and "" or "s"))
  end)
end

function UI.ToggleOptions()
  if not UI.options then return end
  UI.options:SetShown(not UI.options:IsShown())
end

---------------------------------------------------------------- minimap button
local function BuildMinimap()
  if not Minimap then return end
  local b = CreateFrame("Button", "PeerReviewMinimapButton", Minimap)
  UI.mini = b
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  -- The logo is round with its own gold rim, so it needs no border art around it.
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetSize(26, 26)
  icon:SetTexture(LOGO)
  icon:SetPoint("CENTER", 0, 0)
  local function Place()
    local a = math.rad(ns.db.minimapAngle or 195)
    local r = (Minimap:GetWidth() or 140) / 2 + 5
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
  end
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      ns.db.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
      Place()
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  b:SetScript("OnClick", function(_, btn)
    if btn == "RightButton" then UI.ToggleOptions() else UI.RateOrList() end
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Peer Review", 1, .82, .25)
    GameTooltip:AddLine("Left click: rate my group, or my ratings", .8, .8, .8)
    GameTooltip:AddLine("Right click: settings", .8, .8, .8)
    GameTooltip:AddLine(ns.Sync.Status(), .68, .62, .52)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  Place()
end

---------------------------------------------------------------- tooltips
local function AddRating(tooltip, key)
  if not ns.db or not ns.db.settings.tooltip or not key then return end
  if tooltip.peerReviewKey == key then return end -- the game can run the hook more than once per tooltip
  local line = ns.Summary(key)
  if not line then return end
  tooltip.peerReviewKey = key
  tooltip:AddLine("|cffffd140Peer Review|r  " .. line)
  local why = ns.TagLine(key)
  if why then tooltip:AddLine(why) end
  return true
end

local function OnUnitTooltip(tooltip)
  if tooltip ~= GameTooltip or not tooltip.GetUnit then return end
  local _, unit = tooltip:GetUnit()
  if not unit or ns.IsSecret(unit) then unit = "mouseover" end
  if type(unit) ~= "string" or not UnitExists(unit) then return end
  -- In some fights the game hides who a unit is; leave those tooltips alone.
  if C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret then
    local ok, secret = pcall(C_Secrets.ShouldUnitIdentityBeSecret, unit)
    if not ok or secret then return end
  end
  local isPlayer = UnitIsPlayer(unit)
  if ns.IsSecret(isPlayer) or not isPlayer then return end
  local _, key = ns.UnitFull(unit)
  AddRating(tooltip, key)
end

local function HookTooltips()
  local safe = function(tooltip) pcall(OnUnitTooltip, tooltip) end
  if GameTooltip and GameTooltip.HookScript then
    pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipCleared", function(tip) tip.peerReviewKey = nil end)
  end
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType
    and Enum.TooltipDataType.Unit then
    pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit, safe)
  elseif GameTooltip and GameTooltip.HookScript then
    pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", safe)
  end
end

-- Group finder: leader rating on a listing, applicant rating on your own listing.
-- Best effort: these Blizzard functions are hooked only if this client has them.
function UI.HookFinder()
  if not UI.hookedSearch and type(LFGListUtil_SetSearchEntryTooltip) == "function" and hooksecurefunc then
    UI.hookedSearch = true
    hooksecurefunc("LFGListUtil_SetSearchEntryTooltip", function(tooltip, resultID)
      pcall(function()
        local info = C_LFGList.GetSearchResultInfo(resultID)
        local _, key = ns.Full(info and info.leaderName)
        if AddRating(tooltip, key) then tooltip:Show() end
      end)
    end)
  end
  if not UI.hookedApplicant and type(LFGListApplicantMember_OnEnter) == "function" and hooksecurefunc then
    UI.hookedApplicant = true
    hooksecurefunc("LFGListApplicantMember_OnEnter", function(self)
      pcall(function()
        local id = self:GetParent().applicantID
        local _, key = ns.Full((C_LFGList.GetApplicantMemberInfo(id, self.memberIdx)))
        if AddRating(GameTooltip, key) then GameTooltip:Show() end
      end)
    end)
  end
end

---------------------------------------------------------------- build
function UI.Build()
  BuildRate()
  BuildList()
  BuildFeedback()
  BuildOptions()
  BuildMinimap()
  HookTooltips()
  UI.HookFinder()
end

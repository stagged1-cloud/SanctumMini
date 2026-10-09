-- Sanctum / BuffWatch.lua
-- Self buff watch: a row of icons on your own bar (never party). Pick the buffs
-- from the Buff watch dropdown; an icon shows time left while the buff is up and
-- flashes red when it is missing or falls off.
-- 0.7.0: any entry can move to the alert panel instead (moveable, resizable,
-- lockable) with its mode button: flash when it is gone, or while it is on you.
-- Debuffs on you can be tracked too; they always use the panel.

local ADDON, ns = ...
local BW = {}
ns.BuffWatch = BW
local D, L, C = ns.Data, ns.Logic, ns.C

local GAP, MAX_ICONS = 3, 8
-- Total tracked entries (bar + panel). At most MAX_ICONS fit on the bar, so with this cap no mode
-- change can ever push an entry onto a bar that is already full (where it would be hidden).
local MAX_TRACKED = 8
local MENU_ROWS = 12
local PSIZE_MIN, PSIZE_MAX, PGAP, PPAD, PMAX = 24, 96, 4, 6, 12
local QMARK = "Interface\\Icons\\INV_Misc_QuestionMark"
local issecret = issecretvalue or function() return false end

local function db() return ns.cdb.buffWatch end
local function pdb() return ns.cdb.buffWatch.panel end
-- Bar icon size (0.7.0): picked from the Bar size dropdown, default 22.
function BW.BarSize() return L.ClampBuffIconSize(ns.cdb.buffWatch.barSize) end

---------------------------------------------------------------------------
-- Reading your buffs
---------------------------------------------------------------------------
-- Returns auras { [name] = { icon, expirationTime } } or nil when Forever blocked
-- the read (secret auras in combat), so the caller keeps the last known state.
-- filter: "HELPFUL" (default) or "HARMFUL".
function BW.ReadAuras(filter)
    local before = C.auraBlocked or 0
    local auras = {}
    local prev = (filter == "HARMFUL" and BW.lastHarmful or BW.lastAuras) or {}
    C.ForEachAura("player", filter or "HELPFUL", function(a)
        if issecret(a.name) then
            -- A secret name cannot be matched, so the list is incomplete: count it as blocked.
            C.auraBlocked = (C.auraBlocked or 0) + 1
        elseif a.name then
            local exp = a.expirationTime
            local estimated = false
            if issecret(exp) then
                -- Unknown expiry: keep the last known one while it is still ahead, else none.
                -- Flagged as an estimate: it may be from before a recast, so no warning is built on it.
                local old = prev[a.name] and prev[a.name].expirationTime
                exp = (old and old > GetTime()) and old or nil
                estimated = true
            end
            local icon = a.icon
            if issecret(icon) then icon = nil end
            auras[a.name] = { icon = icon, expirationTime = exp, estimated = estimated or nil }
        end
    end)
    if (C.auraBlocked or 0) > before then return nil end
    return auras
end

function BW.ReadWeapon()
    if not GetWeaponEnchantInfo then return nil end
    local ok, has, ms = pcall(GetWeaponEnchantInfo)
    if not ok then return nil end
    return { mainHand = has and true or false, mainHandMs = ms }
end

---------------------------------------------------------------------------
-- Icons
---------------------------------------------------------------------------
local function makeIcon(i)
    local b = CreateFrame("Frame", nil, BW.holder)
    local size = BW.BarSize()
    b:SetSize(size, size)
    b:SetPoint("LEFT", BW.holder, "LEFT", (i - 1) * (size + GAP), 0)
    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetPoint("TOPLEFT", -1, 1); b.border:SetPoint("BOTTOMRIGHT", 1, -1)
    b.border:SetColorTexture(0, 0, 0, 1)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.time = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.time:SetPoint("BOTTOM", b, "BOTTOM", 0, -1)
    b:EnableMouse(true)
    b:SetScript("OnEnter", function(self)
        if not self.state then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(self.state.label)
        if self.state.up then
            local r = L.FormatRemaining(self.state.remaining)
            GameTooltip:AddLine(r ~= "" and ("Up - " .. r .. " left") or "Up", 0.3, 1, 0.3)
        else
            GameTooltip:AddLine("Missing - recast it", 1, 0.25, 0.25)
        end
        GameTooltip:AddLine("Change tracked buffs: /sanc buffs", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    return b
end

-- Above your bar when it is the top bar (clear of the drag header when unlocked);
-- below it when "Me at top" is off and your bar is at the bottom of the stack.
function BW.Place()
    local h = BW.holder
    local F = ns.Frames
    local me = F and F.byUnit and F.byUnit.player
    if not h or not me then return end
    h:ClearAllPoints()
    if (me.pos or 1) == 1 then
        local lift = (ns.db.frames.locked and 0 or 16) + 3
        h:SetPoint("BOTTOMLEFT", me, "TOPLEFT", 0, lift)
    else
        h:SetPoint("TOPLEFT", me, "BOTTOMLEFT", 0, -3)
    end
end

function BW.Update()
    if not BW.holder then return end
    local tracked = db().list
    if #tracked == 0 or UnitIsDeadOrGhost("player") then BW.holder:Hide(); BW.UpdatePanel(nil); return end
    local auras = BW.ReadAuras()
    if auras then BW.lastAuras = auras end
    local wantHarmful = false
    for _, t in ipairs(tracked) do if t.harmful then wantHarmful = true end end
    local harmBlocked = false
    if wantHarmful then
        local harmful = BW.ReadAuras("HARMFUL")
        if harmful then BW.lastHarmful = harmful else harmBlocked = true end
    end
    local now = GetTime()
    -- A blocked read leaves the last known lists in use: hold their state (no expiry-based "missing").
    local states = L.BuffWatchState(tracked, BW.lastAuras or {}, now, BW.ReadWeapon(), BW.lastHarmful or {},
                                    { helpful = auras == nil, harmful = harmBlocked })
    local anyMissing = false
    local n = 0
    local barSize = BW.BarSize()
    local barEntries = 0
    for i, st in ipairs(states) do
        local b = BW.icons[i] or makeIcon(i)
        BW.icons[i] = b
        b.state = st
        local onBar = not L.IsPanelEntry(tracked[i])
        if onBar then barEntries = barEntries + 1 end
        -- Only the first MAX_ICONS bar entries are drawn (panel entries do not count towards it).
        if not onBar or barEntries > MAX_ICONS or (st.up and db().hideWhileUp) then
            b:Hide()
        else
            n = n + 1
            b:ClearAllPoints()
            b:SetSize(barSize, barSize)
            b:SetPoint("LEFT", BW.holder, "LEFT", (n - 1) * (barSize + GAP), 0)
            b.tex:SetTexture(st.icon or C.GetSpellIcon(st.key) or QMARK)
            b.tex:SetDesaturated(not st.up)
            b.time:SetText(st.up and L.FormatRemaining(st.remaining) or "")
            if st.up then b.border:SetColorTexture(0, 0, 0, 1) else b.border:SetColorTexture(1, 0.1, 0.1, 1) end
            b:SetAlpha(1)
            b:Show()
            if not st.up then anyMissing = true end
        end
    end
    for i = #states + 1, #BW.icons do BW.icons[i]:Hide(); BW.icons[i].state = nil end
    BW.holder:SetSize(math.max(1, n * (barSize + GAP)), barSize)
    BW.holder:SetShown(n > 0)
    BW.flashing = anyMissing
    BW.UpdatePanel(L.AlertState(tracked, states, L.ClampWarn(pdb().warnSecs)), states)
end

-- Flash: missing icons pulse between full and faint.
local function onUpdate(_, elapsed)
    BW.t = (BW.t or 0) + elapsed
    BW.acc = (BW.acc or 0) + elapsed
    -- UNIT_AURA only sets BW.dirty, so a burst of events costs one Update per frame.
    if BW.dirty or BW.acc >= 0.5 then BW.acc = 0; BW.dirty = false; BW.Update() end   -- timers tick down, imbues expire
    BW.PanelTick(elapsed)
    if not BW.flashing then return end
    local a = 0.3 + 0.7 * math.abs(math.sin(BW.t * 4))
    for _, b in ipairs(BW.icons) do
        if b.state and not b.state.up and b:IsShown() then b:SetAlpha(a) end
    end
end

---------------------------------------------------------------------------
-- Dropdown: tick the buffs to track.
---------------------------------------------------------------------------
local function currentBuffs()
    local cur = {}
    for name, a in pairs(BW.ReadAuras() or BW.lastAuras or {}) do cur[name] = a.icon or true end
    return cur
end

-- Buff rows first, then debuffs on you.
function BW.Candidates()
    local rows = L.BuffWatchCandidates(D.buffWatch[ns.class], ns.known, currentBuffs(), db().list)
    local cur = {}
    for name, a in pairs(BW.ReadAuras("HARMFUL") or BW.lastHarmful or {}) do cur[name] = a.icon or true end
    local dw = D.debuffWatch or {}
    for _, r in ipairs(L.DebuffWatchCandidates(dw[ns.class], dw.ALL, cur, db().list)) do rows[#rows + 1] = r end
    return rows
end

local function sameKind(a, b) return (a.harmful and true or false) == (b.harmful and true or false) end

function BW.SetTracked(row, on)
    local list = db().list
    for i = #list, 1, -1 do if list[i].key == row.key and sameKind(list[i], row) then table.remove(list, i) end end
    -- The cap is per place: 8 bar icons (panel entries do not count), and PMAX alert panel entries.
    local bar, panel = 0, 0
    for _, t in ipairs(list) do
        if L.IsPanelEntry(t) then panel = panel + 1 else bar = bar + 1 end
    end
    local toPanel = L.IsPanelEntry({ harmful = row.harmful, alert = L.DefaultAlertMode(row.harmful) })
    if on and #list >= MAX_TRACKED then
        ns.Print("buff watch is full (%d tracked): untick one before adding %s", MAX_TRACKED, row.label or row.key)
    elseif on and not toPanel and bar >= MAX_ICONS then
        ns.Print("buff watch bar is full (%d bar icons): untick one or move one to the panel before adding %s",
                 MAX_ICONS, row.label or row.key)
    elseif on and toPanel and panel >= PMAX then
        ns.Print("alert panel is full (%d entries): untick one before adding %s", PMAX, row.label or row.key)
    elseif on then
        list[#list + 1] = { key = row.key, label = row.label, accept = row.accept, weapon = row.weapon,
                            harmful = row.harmful, alert = L.DefaultAlertMode(row.harmful),
                            icon = row.icon or C.GetSpellIcon((row.accept and row.accept[1]) or row.key) }
        if row.harmful then BW.FirstPanelUse() end
    end
    BW.Update()
end

-- Buff watch window colours (0.7.0 restyle): dark slate, 1 px borders, gold headings.
local COL = {
    bg = { 0.067, 0.075, 0.094, 0.97 }, edge = { 0.30, 0.32, 0.38, 1 }, title = { 0.11, 0.12, 0.155, 1 },
    line = { 0.24, 0.26, 0.31, 1 }, stripe = { 1, 1, 1, 0.035 }, pick = { 0.35, 0.55, 0.85, 0.35 },
    btn = { 0.15, 0.165, 0.20, 1 }, btnHover = { 0.22, 0.24, 0.30, 1 },
    modeBar = { 0.18, 0.20, 0.25, 1 }, modeGone = { 0.50, 0.13, 0.13, 1 }, modeOn = { 0.55, 0.36, 0.06, 1 },
}
local function paint(tex, c) tex:SetColorTexture(c[1], c[2], c[3], c[4]) end

-- Fill with a 1 px border: the border colour sits underneath, the fill is inset over it.
local function skin(f, fill)
    local e = f:CreateTexture(nil, "BACKGROUND", nil, -8); e:SetAllPoints(); paint(e, COL.edge)
    local b = f:CreateTexture(nil, "BACKGROUND", nil, -7)
    b:SetPoint("TOPLEFT", 1, -1); b:SetPoint("BOTTOMRIGHT", -1, 1)
    paint(b, fill or COL.bg)
    f.fill = b
end

-- Flat button with hover. tip = text, or function(self) that fills GameTooltip.
local function styledButton(parent, w, h, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    skin(b, COL.btn)
    b.base = COL.btn
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.text:SetPoint("CENTER")
    b:SetScript("OnEnter", function(self)
        paint(self.fill, COL.btnHover)
        if tip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if type(tip) == "function" then tip(self) else GameTooltip:AddLine(tip, 1, 1, 1, true) end
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self) paint(self.fill, self.base); GameTooltip:Hide() end)
    return b
end

local function modeTip()
    GameTooltip:AddLine("Where this one shows")
    GameTooltip:AddLine("Bar: small icon on your bar (buffs only)", 1, 1, 1)
    GameTooltip:AddLine("Panel: gone - alert panel flashes red when it is NOT on you", 1, 1, 1)
    GameTooltip:AddLine("Panel: on - alert panel flashes red while it IS on you", 1, 1, 1)
    GameTooltip:AddLine("Click to change", 0.7, 0.7, 0.7)
end

local ROW_H, ROWS_TOP = 20, -54
local MENU_W, MENU_H = 360, 446

function BW.PlaceMenu()
    local m = BW.menu
    if not m then return end
    local pos = db().menuPos
    m:ClearAllPoints()
    if type(pos) == "table" and pos.point then
        m:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        m:SetPoint("CENTER", UIParent, "CENTER", 260, 40)
    end
end

local function buildMenu()
    local m = CreateFrame("Frame", "SanctumBuffWatchMenu", UIParent)
    m:SetSize(MENU_W, MENU_H)
    m:SetFrameStrata("DIALOG")
    m:SetToplevel(true)
    m:SetMovable(true)
    m:EnableMouse(true)
    m:EnableMouseWheel(true)
    m:SetClampedToScreen(true)
    skin(m, COL.bg)

    -- Title bar: drag to move; position is remembered per character.
    local tb = CreateFrame("Frame", nil, m)
    tb:SetPoint("TOPLEFT", 1, -1); tb:SetPoint("TOPRIGHT", -1, -1); tb:SetHeight(26)
    local tbg = tb:CreateTexture(nil, "BACKGROUND"); tbg:SetAllPoints(); paint(tbg, COL.title)
    local tline = tb:CreateTexture(nil, "ARTWORK"); tline:SetHeight(1)
    tline:SetPoint("BOTTOMLEFT"); tline:SetPoint("BOTTOMRIGHT"); paint(tline, COL.edge)
    tb:EnableMouse(true)
    tb:RegisterForDrag("LeftButton")
    tb:SetScript("OnDragStart", function() m:StartMoving() end)
    tb:SetScript("OnDragStop", function()
        m:StopMovingOrSizing()
        local point, _, relPoint, x, y = m:GetPoint()
        db().menuPos = { point = point or "CENTER", relPoint = relPoint or point or "CENTER",
                         x = math.floor((x or 0) + 0.5), y = math.floor((y or 0) + 0.5) }
    end)
    local t = tb:CreateFontString(nil, "OVERLAY", "GameFontNormal"); t:SetPoint("LEFT", 10, 0)
    t:SetText("Sanctum Buff Watch")
    local sub = tb:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); sub:SetPoint("LEFT", t, "RIGHT", 8, -1)
    sub:SetText("drag to move")
    m.titleBar = tb
    local close = CreateFrame("Button", nil, m, "UIPanelCloseButton"); close:SetSize(24, 24); close:SetPoint("TOPRIGHT", 0, 0)
    close:SetFrameLevel(tb:GetFrameLevel() + 2)

    local function section(text, y)
        local h = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); h:SetPoint("TOPLEFT", 12, y); h:SetText(text)
        local ln = m:CreateTexture(nil, "ARTWORK"); ln:SetHeight(1)
        ln:SetPoint("TOPLEFT", 10, y - 14); ln:SetPoint("TOPRIGHT", -10, y - 14); paint(ln, COL.line)
        return h
    end
    local function label(text, x, y)
        local fs = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); fs:SetPoint("TOPLEFT", x, y); fs:SetText(text)
        return fs
    end

    -- Tracked list
    section("Track buffs and debuffs on you", -34)
    m.countText = m:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); m.countText:SetPoint("TOPRIGHT", -12, -34)
    m.offset = 0
    m.rows = {}
    for i = 1, MENU_ROWS do
        local y = ROWS_TOP - (i - 1) * ROW_H
        local band = m:CreateTexture(nil, "BORDER")
        band:SetPoint("TOPLEFT", 8, y); band:SetPoint("TOPRIGHT", -8, y); band:SetHeight(ROW_H)
        paint(band, COL.stripe)
        local r = CreateFrame("CheckButton", nil, m, "UICheckButtonTemplate")
        r:SetSize(20, 20)
        r:SetPoint("TOPLEFT", 10, y)
        r:SetHitRectInsets(0, -200, 0, 0)            -- the name is clickable too
        r.band = band
        r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT", r, "RIGHT", 3, 0)
        r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
        r.text:SetWidth(200); r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(false)
        -- Mode pill (shown once ticked): Bar / Panel: gone / Panel: on
        local mb = styledButton(m, 84, 18, modeTip)
        mb:SetPoint("TOPRIGHT", m, "TOPRIGHT", -12, y - 1)
        mb:SetScript("OnClick", function() if r.row then BW.CycleMode(r.row); m:Fill() end end)
        mb:Hide()
        r.mode = mb
        r:SetScript("OnClick", function(self)
            if self.row then BW.SetTracked(self.row, self:GetChecked() and true or false); m:Fill() end
        end)
        m.rows[i] = r
    end

    -- Dropdowns open upwards from their button; only one is open at a time.
    m.lists = {}
    local function dropButton(w, x, y, tip)
        local b = styledButton(m, w, 20, tip)
        b:SetPoint("TOPLEFT", x, y)
        b.text:ClearAllPoints(); b.text:SetPoint("LEFT", 8, 0); b.text:SetPoint("RIGHT", -18, 0); b.text:SetJustifyH("LEFT")
        local arrow = b:CreateTexture(nil, "OVERLAY"); arrow:SetSize(16, 16); arrow:SetPoint("RIGHT", -2, 0)
        arrow:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
        arrow:SetTexCoord(0.2, 0.8, 0.25, 0.75)
        return b
    end
    local function dropdown(button, width, values, text, current, onPick)
        local wl = CreateFrame("Frame", nil, m)
        wl:SetSize(width, #values * 18 + 4)
        wl:SetPoint("BOTTOMLEFT", button, "TOPLEFT", 0, 2)
        wl:SetFrameLevel(m:GetFrameLevel() + 20)
        wl:EnableMouse(true)
        skin(wl, COL.title)
        wl.items = {}
        for i, v in ipairs(values) do
            local it = CreateFrame("Button", nil, wl)
            it:SetSize(width - 4, 18); it:SetPoint("TOPLEFT", 2, -2 - (i - 1) * 18)
            local hl = it:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); paint(hl, COL.pick)
            it.text = it:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); it.text:SetPoint("LEFT", 8, 0)
            it.text:SetText(text(v))
            it.value = v
            it:SetScript("OnClick", function() wl:Hide(); onPick(v); m:FillPanel(); BW.Update() end)
            wl.items[i] = it
        end
        wl:Hide()
        button:SetScript("OnClick", function()
            local show = not wl:IsShown()
            for _, l in ipairs(m.lists) do l:Hide() end
            if show then
                local cur = current()
                for _, it in ipairs(wl.items) do
                    if it.value == cur then it.text:SetTextColor(1, 0.82, 0) else it.text:SetTextColor(1, 1, 1) end
                end
                wl:Show()
            end
        end)
        m.lists[#m.lists + 1] = wl
        return wl
    end

    -- Bar icons
    section("Bar icons", -300)
    local hide = CreateFrame("CheckButton", nil, m, "UICheckButtonTemplate")
    hide:SetSize(20, 20); hide:SetPoint("TOPLEFT", 10, -320)
    hide:SetHitRectInsets(0, -200, 0, 0)            -- the label is clickable too
    local hl = hide:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); hl:SetPoint("LEFT", hide, "RIGHT", 2, 0)
    hl:SetText("Hide icons while the buff is up")
    hide:SetScript("OnShow", function(self) self:SetChecked(db().hideWhileUp) end)
    hide:SetScript("OnClick", function(self) db().hideWhileUp = self:GetChecked() and true or false; BW.Update() end)
    m.hideCheck = hide
    label("Size", 238, -324)
    local bar = dropButton(80, 268, -320, "Size of the small icons on your bar")
    m.barSizeButton = bar
    m.barSizeList = dropdown(bar, 80, L.BUFF_ICON_SIZES, function(v) return v .. " px" end,
        function() return BW.BarSize() end, function(v) db().barSize = v end)

    -- Alert panel
    section("Alert panel", -350)
    local lock = CreateFrame("CheckButton", nil, m, "UICheckButtonTemplate")
    lock:SetSize(20, 20); lock:SetPoint("TOPLEFT", 10, -370)
    lock:SetHitRectInsets(0, -260, 0, 0)            -- the label is clickable too
    local ll = lock:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); ll:SetPoint("LEFT", lock, "RIGHT", 2, 0)
    ll:SetText("Lock alert panel (untick to move and resize it)")
    lock:SetScript("OnClick", function(self) BW.SetPanelLocked(self:GetChecked() and true or false) end)
    m.lockCheck = lock
    label("Warn", 14, -401)
    local warn = dropButton(76, 46, -397, "Amber warning before a 'Panel: gone' buff runs out")
    m.warnButton = warn
    m.warnList = dropdown(warn, 90, L.WARN_CHOICES, function(v) return v == 0 and "Off" or (v .. " seconds") end,
        function() return L.ClampWarn(pdb().warnSecs) end, function(v) pdb().warnSecs = v end)
    label("Sound", 136, -401)
    local snd = dropButton(170, 178, -397, "Sound when an alert starts; each one plays when picked")
    m.soundButton = snd
    local soundKeys, soundLabels = {}, {}
    for _, x in ipairs(D.alertSounds) do soundKeys[#soundKeys + 1] = x.key; soundLabels[x.key] = x.label end
    m.soundList = dropdown(snd, 170, soundKeys, function(k) return soundLabels[k] end,
        function() return pdb().sound end, function(k) pdb().sound = k; BW.PlayAlert(true) end)

    local hint = m:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); hint:SetPoint("BOTTOMLEFT", 12, 10)
    hint:SetText("Scroll the list for more. Debuffs (red) always use the alert panel.")

    function m:FillPanel()
        local p = pdb()
        self.lockCheck:SetChecked(p.locked)
        local w = L.ClampWarn(p.warnSecs)
        self.warnButton.text:SetText(w == 0 and "Off" or (w .. " sec"))
        self.barSizeButton.text:SetText(BW.BarSize() .. " px")
        local name = "Off"
        for _, x in ipairs(D.alertSounds) do if x.key == p.sound then name = x.label end end
        self.soundButton.text:SetText(name)
        for _, l in ipairs(self.lists) do l:Hide() end
    end
    function m:Fill()
        local rows = BW.Candidates()
        self.items = rows
        local maxOff = math.max(0, #rows - MENU_ROWS)
        if self.offset > maxOff then self.offset = maxOff end
        self.countText:SetText(#rows > MENU_ROWS
            and ((self.offset + 1) .. "-" .. math.min(#rows, self.offset + MENU_ROWS) .. " of " .. #rows) or "")
        for i, r in ipairs(self.rows) do
            local row = rows[i + self.offset]
            r.row = row
            if row then
                r:SetChecked(row.checked)
                r.icon:SetTexture(row.icon or C.GetSpellIcon((row.accept and row.accept[1]) or row.key) or QMARK)
                r.text:SetText(row.harmful and ("|cffff7373" .. row.label .. "|r") or row.label)
                r:Show()
                r.band:SetShown(i % 2 == 0)
                local e = row.checked and BW.Entry(row)
                if e then
                    local mode = L.AlertMode(e)
                    r.mode.text:SetText(L.AlertModeLabel(mode))
                    r.mode.base = (mode == "missing" and COL.modeGone) or (mode == "present" and COL.modeOn) or COL.modeBar
                    paint(r.mode.fill, r.mode.base)
                    r.mode:Show()
                else
                    r.mode:Hide()
                end
            else
                r:Hide()
                r.mode:Hide()
                r.band:Hide()
            end
        end
        self:FillPanel()
    end
    m:SetScript("OnMouseWheel", function(self, delta)
        self.offset = math.max(0, self.offset - delta * 3)
        self:Fill()
    end)
    m:SetScript("OnShow", function(self) self:Fill() end)
    tinsert(UISpecialFrames, "SanctumBuffWatchMenu")
    m:Hide()
    return m
end

---------------------------------------------------------------------------
-- Alert panel (0.7.0): big icons that flash red when a buff falls off or a
-- debuff lands (set per entry). Move it, resize it from the corner, lock it.
---------------------------------------------------------------------------
function BW.Entry(row)
    for _, t in ipairs(db().list) do
        if t.key == row.key and sameKind(t, row) then return t end
    end
end

-- The first time anything goes to the panel, unlock it so it can be put somewhere sensible.
function BW.FirstPanelUse()
    local p = pdb()
    if p.placed or not p.locked then return end
    BW.SetPanelLocked(false)
    ns.Print("alert panel unlocked: drag it into place, resize it from the corner, then lock it (/sanc alert lock)")
end

function BW.CycleMode(row)
    local e = BW.Entry(row)
    if not e then return end
    e.alert = L.NextAlertMode(L.AlertMode(e), e.harmful)
    if L.IsPanelEntry(e) then BW.FirstPanelUse() end
    BW.Update()
end

local function makeAlertIcon(f)
    local b = CreateFrame("Frame", nil, f)
    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetPoint("TOPLEFT", -2, 2); b.border:SetPoint("BOTTOMRIGHT", 2, -2)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.glow = b:CreateTexture(nil, "OVERLAY")
    b.glow:SetAllPoints()
    b.glow:SetColorTexture(1, 0, 0, 0.6)
    b.time = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    b.time:SetPoint("CENTER")
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetPoint("TOP", b, "BOTTOM", 0, -3)
    b.label:SetWordWrap(false)
    b:Hide()
    return b
end

local function layoutPanel(list)
    local f, p = BW.panel, pdb()
    local size = math.max(PSIZE_MIN, math.min(PSIZE_MAX, tonumber(p.size) or 44))
    local n = 0
    f.flashing = false
    for i, a in ipairs(list) do
        if i > PMAX then break end
        n = i
        local b = f.icons[i] or makeAlertIcon(f)
        f.icons[i] = b
        b.alert = a
        b:SetSize(size, size)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", f, "TOPLEFT", PPAD + (i - 1) * (size + PGAP), -PPAD)
        b.tex:SetTexture(a.icon or (a.key and C.GetSpellIcon(a.key)) or QMARK)
        if a.level == "warn" then
            b.border:SetColorTexture(1, 0.65, 0, 1)
            b.glow:Hide()
            b.time:SetText(L.FormatRemaining(a.remaining))
        elseif a.level == "idle" then
            -- unlocked preview of an entry with nothing to report
            b.border:SetColorTexture(0.3, 0.3, 0.3, 1)
            b.glow:Hide()
            b.time:SetText(L.FormatRemaining(a.remaining))
        else
            b.border:SetColorTexture(1, 0.1, 0.1, 1)
            b.glow:Show()
            b.time:SetText("")
            f.flashing = true
        end
        b.tex:SetDesaturated(a.level == "idle")
        b.label:SetWidth(size + PGAP * 4)
        b.label:SetText(a.label or "")
        b:Show()
    end
    for i = n + 1, #f.icons do f.icons[i]:Hide(); f.icons[i].alert = nil end
    f.count = n
    f:SetSize(PPAD * 2 + math.max(1, n) * (size + PGAP) - PGAP, size + PPAD * 2 + 14)
    f:SetShown(n > 0)
end

-- alerts = L.AlertState(...) list, or nil when there is nothing to judge (dead, nothing tracked);
-- states = BuffWatchState list for the preview. Unlocked, the panel previews its entries so it
-- can be placed and sized: live alerts as they are, the rest dimmed, or left out when
-- "Hide icons while the buff is up" is ticked.
function BW.UpdatePanel(alerts, states)
    local f = BW.panel
    if not f then return end
    if alerts then
        local new, set = L.NewAlerts(BW.prevAlerts, alerts)
        BW.prevAlerts = set
        if new > 0 then BW.PlayAlert() end
    end
    local list = alerts or {}
    if not pdb().locked then
        local live = {}
        for _, a in ipairs(alerts or {}) do live[a.id] = a end
        local hideIdle = db().hideWhileUp
        local anyEntry = false
        list = {}
        for i, t in ipairs(db().list) do
            if L.IsPanelEntry(t) then
                anyEntry = true
                local id = (t.harmful and "-" or "+") .. t.key
                if live[id] then
                    list[#list + 1] = live[id]
                elseif not hideIdle then
                    local st = states and states[i]
                    list[#list + 1] = { id = id, key = t.key, label = t.label or t.key, level = "idle",
                                        icon = (st and st.icon) or t.icon, remaining = st and st.remaining }
                end
            end
        end
        if #list == 0 then
            list = { { label = anyEntry and "Alerts show here" or "No alerts set", icon = QMARK, level = "idle" } }
        end
    end
    BW.panelList = list
    layoutPanel(list)
end

-- Called every frame from the buff watch driver: resize drag and the red pulse.
function BW.PanelTick(elapsed)
    local f = BW.panel
    if not f then return end
    if BW.sizing then
        local x = GetCursorPosition()
        local s = UIParent:GetEffectiveScale() or 1
        local n = math.max(1, f.count or 1)
        local size = math.floor(BW.sizing.size + (x - BW.sizing.x) / s / n + 0.5)
        size = math.max(PSIZE_MIN, math.min(PSIZE_MAX, size))
        if size ~= pdb().size then pdb().size = size; layoutPanel(BW.panelList or {}) end
    end
    if f.flashing and f:IsShown() then
        BW.pt = (BW.pt or 0) + (elapsed or 0)
        local a = 0.1 + 0.9 * math.abs(math.sin(BW.pt * 5))
        for i = 1, f.count or 0 do
            local b = f.icons[i]
            if b.alert and b.alert.level == "alert" then b.glow:SetAlpha(a) end
        end
    end
end

function BW.PlacePanel()
    local f, p = BW.panel, pdb()
    if not f then return end
    f:ClearAllPoints()
    f:SetPoint(p.point or "CENTER", UIParent, p.relPoint or p.point or "CENTER", p.x or 0, p.y or 0)
end

function BW.ApplyPanelLock()
    local f = BW.panel
    if not f then return end
    local open = not pdb().locked
    f:EnableMouse(open)
    f.bg:SetShown(open); f.title:SetShown(open); f.grip:SetShown(open)
end

function BW.SetPanelLocked(v)
    local p = pdb()
    p.locked = v and true or false
    if p.locked then p.placed = true; BW.sizing = nil end
    BW.ApplyPanelLock()
    BW.Update()
    if BW.menu and BW.menu.FillPanel then BW.menu:FillPanel() end
end

function BW.BuildPanel()
    local f = CreateFrame("Frame", "SanctumAlertPanel", UIParent)
    f:SetFrameStrata("HIGH")
    f:SetSize(60, 60)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f.icons = {}
    f.bg = f:CreateTexture(nil, "BACKGROUND"); f.bg:SetAllPoints(); f.bg:SetColorTexture(0.02, 0.02, 0.05, 0.7)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.title:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 3)
    f.title:SetText("Sanctum alerts - drag to move, corner to resize, /sanc alert lock")
    f:SetScript("OnDragStart", function(self) if not pdb().locked then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        local p = pdb()
        p.point, p.relPoint = point or "CENTER", relPoint or point or "CENTER"
        p.x, p.y = math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5)
        p.placed = true
    end)
    local g = CreateFrame("Button", nil, f)
    g:SetSize(14, 14)
    g:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    g:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    g:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    g:SetScript("OnMouseDown", function() BW.sizing = { x = GetCursorPosition(), size = pdb().size or 44 } end)
    g:SetScript("OnMouseUp", function() BW.sizing = nil; pdb().placed = true end)
    f.grip = g
    f:Hide()
    BW.panel = f
    BW.PlacePanel()
    BW.ApplyPanelLock()
end

-- Sound, at most once every 2 s unless forced (forced = a preview, which also reports problems).
function BW.PlayAlert(force)
    local p = pdb()
    local now = GetTime()
    if not force and BW.lastSound and now - BW.lastSound < 2 then return end
    local kind, what = L.AlertSound(D.alertSounds, p.sound)
    if not kind then return end
    BW.lastSound = now
    if kind == "file" then
        local ok, willPlay = pcall(PlaySoundFile, what, "Master")
        if force and not (ok and willPlay) then
            ns.Print("could not play %s - if you just updated Sanctum Mini, restart the game", what)
        end
    else
        pcall(PlaySound, what, "Master")
    end
end

-- /sanc alert [lock|unlock|reset|test]
function BW.AlertCommand(msg)
    local cmd = (msg or ""):match("^%s*(%S*)")
    cmd = (cmd or ""):lower()
    local p = pdb()
    if cmd == "" then
        BW.SetPanelLocked(not p.locked)
    elseif cmd == "lock" or cmd == "unlock" then
        BW.SetPanelLocked(cmd == "lock")
    elseif cmd == "reset" then
        p.point, p.relPoint, p.x, p.y, p.size = "CENTER", "CENTER", 0, 180, 44
        BW.PlacePanel(); BW.Update()
        ns.Print("alert panel position and size reset")
        return
    elseif cmd == "test" then
        BW.PlayAlert(true)
        return
    else
        ns.Print("/sanc alert - lock or unlock the alert panel   /sanc alert reset - put it back in the middle")
        ns.Print("/sanc alert test - play the alert sound")
        return
    end
    ns.Print(pdb().locked and "alert panel locked" or "alert panel unlocked: drag to move, resize from the corner")
end

-- Opens or closes the Buff watch window. It is its own window: it opens where you last
-- dragged it, not on the Options button (the argument is kept for old callers and ignored).
function BW.ToggleMenu()
    BW.menu = BW.menu or buildMenu()
    local m = BW.menu
    if m:IsShown() then m:Hide(); return end
    BW.PlaceMenu()
    m.offset = 0
    m:Show()
    m:Fill()
end

-- One-time login warning when a saved list has more entries than can be drawn
-- (bar: MAX_ICONS bar entries; panel: PMAX panel entries). Nothing is deleted.
function BW.WarnOverflow()
    local bar, panel = 0, 0
    for _, t in ipairs(db().list) do
        if L.IsPanelEntry(t) then panel = panel + 1 else bar = bar + 1 end
    end
    local warned = false
    if bar > MAX_ICONS then
        ns.Print("buff watch: %d bar entries saved but only %d icons are drawn; untick some or move them to the alert panel", bar, MAX_ICONS)
        warned = true
    end
    if panel > PMAX then
        ns.Print("buff watch: %d alert panel entries saved but only %d are drawn; untick some", panel, PMAX)
        warned = true
    end
    if not warned and bar + panel > MAX_TRACKED then
        ns.Print("buff watch: %d buffs saved but the limit is %d; untick some (nothing was removed, but you cannot add more until you are under the limit)", bar + panel, MAX_TRACKED)
    end
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------
function BW.Init()
    local F = ns.Frames
    BW.holder = CreateFrame("Frame", "SanctumBuffWatch", F.anchor)
    BW.holder:SetSize(BW.BarSize(), BW.BarSize())
    BW.icons = {}
    pdb().warnSecs = L.ClampWarn(pdb().warnSecs)    -- Off or 10 to 30 s
    pdb().sound = L.ValidSound(D.alertSounds, pdb().sound)   -- test builds had an own-file option
    pdb().soundFile = nil
    BW.WarnOverflow()
    BW.BuildPanel()
    -- Follow the player bar when the frames are laid out again or (un)locked.
    for _, fn in ipairs({ "Layout", "UpdateLock" }) do
        local orig = F[fn]
        F[fn] = function(...)
            local r = orig(...)
            BW.Place()
            return r
        end
    end
    BW.Place()
    ns.On("UNIT_AURA", function(_, unit) if unit == "player" then BW.dirty = true end end)
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
                         "UNIT_INVENTORY_CHANGED", "PLAYER_REGEN_ENABLED" }) do
        ns.On(e, function() BW.Update() end)
    end
    -- No parent (not UIParent): the driver keeps running while the UI is hidden (Alt-Z).
    BW.driver = CreateFrame("Frame")
    BW.driver:SetScript("OnUpdate", onUpdate)
    BW.ready = true
    BW.Update()
end

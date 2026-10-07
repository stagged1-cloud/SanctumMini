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
local MENU_ROWS = 12
local MENU_EXTRA = 66                                   -- alert panel controls in the dropdown
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
    C.ForEachAura("player", filter or "HELPFUL", function(a)
        if a.name and not issecret(a.name) then
            local exp = a.expirationTime
            if issecret(exp) then exp = nil end
            local icon = a.icon
            if issecret(icon) then icon = nil end
            auras[a.name] = { icon = icon, expirationTime = exp }
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
    if wantHarmful then
        local harmful = BW.ReadAuras("HARMFUL")
        if harmful then BW.lastHarmful = harmful end
    end
    local now = GetTime()
    local states = L.BuffWatchState(tracked, BW.lastAuras or {}, now, BW.ReadWeapon(), BW.lastHarmful or {})
    local anyMissing = false
    local n = 0
    local barSize = BW.BarSize()
    for i, st in ipairs(states) do
        if i > MAX_ICONS then break end
        local b = BW.icons[i] or makeIcon(i)
        BW.icons[i] = b
        b.state = st
        if L.IsPanelEntry(tracked[i]) or (st.up and db().hideWhileUp) then
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
    if BW.acc >= 0.5 then BW.acc = 0; BW.Update() end   -- timers tick down, imbues expire
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
    if on then
        list[#list + 1] = { key = row.key, label = row.label, accept = row.accept, weapon = row.weapon,
                            harmful = row.harmful, alert = L.DefaultAlertMode(row.harmful),
                            icon = row.icon or C.GetSpellIcon((row.accept and row.accept[1]) or row.key) }
        if row.harmful then BW.FirstPanelUse() end
    end
    BW.Update()
end

local function buildMenu()
    local m = CreateFrame("Frame", "SanctumBuffWatchMenu", UIParent)
    m:SetSize(320, 74 + MENU_EXTRA + MENU_ROWS * 20)
    m:SetFrameStrata("FULLSCREEN_DIALOG")
    m:EnableMouse(true)
    m:EnableMouseWheel(true)
    m:SetClampedToScreen(true)
    local bg = m:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.02, 0.02, 0.05, 0.97)
    local edge = m:CreateTexture(nil, "BORDER"); edge:SetPoint("TOPLEFT", -1, 1); edge:SetPoint("BOTTOMRIGHT", 1, -1)
    edge:SetColorTexture(0.2, 0.5, 0.8, 1)
    local t = m:CreateFontString(nil, "OVERLAY", "GameFontNormal"); t:SetPoint("TOPLEFT", 8, -6)
    t:SetText("Buff watch - tick to track")
    local close = CreateFrame("Button", nil, m, "UIPanelCloseButton"); close:SetSize(20, 20); close:SetPoint("TOPRIGHT", 0, 0)
    m.offset = 0
    m.rows = {}
    for i = 1, MENU_ROWS do
        local r = CreateFrame("CheckButton", nil, m, "UICheckButtonTemplate")
        r:SetSize(20, 20)
        r:SetPoint("TOPLEFT", 8, -24 - (i - 1) * 20)
        r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT", r, "RIGHT", 2, 0)
        r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.text:SetPoint("LEFT", r.icon, "RIGHT", 5, 0)
        r.text:SetWidth(180); r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(false)
        -- Mode button (shown once ticked): Bar / Panel: gone / Panel: on
        local mb = CreateFrame("Button", nil, m)
        mb:SetSize(72, 18)
        mb:SetPoint("TOPRIGHT", m, "TOPRIGHT", -8, -25 - (i - 1) * 20)
        local mbg = mb:CreateTexture(nil, "BACKGROUND"); mbg:SetAllPoints(); mbg:SetColorTexture(0.15, 0.25, 0.4, 0.9)
        mb.text = mb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); mb.text:SetPoint("CENTER")
        mb:SetScript("OnClick", function() if r.row then BW.CycleMode(r.row); m:Fill() end end)
        mb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Where this one shows")
            GameTooltip:AddLine("Bar: small icon on your bar (buffs only)", 1, 1, 1)
            GameTooltip:AddLine("Panel: gone - alert panel flashes red when it is NOT on you", 1, 1, 1)
            GameTooltip:AddLine("Panel: on - alert panel flashes red while it IS on you", 1, 1, 1)
            GameTooltip:AddLine("Click to change", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        mb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        mb:Hide()
        r.mode = mb
        r:SetScript("OnClick", function(self)
            if self.row then BW.SetTracked(self.row, self:GetChecked() and true or false); m:Fill() end
        end)
        m.rows[i] = r
    end
    -- Alert panel controls (0.7.0), above the hide tick.
    local head = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); head:SetPoint("BOTTOMLEFT", 10, 94)
    head:SetText("Alert panel")
    local function smallButton(w, x, y, tip)
        local b = CreateFrame("Button", nil, m)
        b:SetSize(w, 18); b:SetPoint("BOTTOMLEFT", x, y)
        local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.15, 0.25, 0.4, 0.9)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.text:SetPoint("CENTER")
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(tip, 1, 1, 1, true); GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end
    -- Small dropdown list that opens upwards from a button. onPick(value) is called on a pick.
    local function dropdown(button, values, text, onPick, width)
        width = width or 84
        local wl = CreateFrame("Frame", nil, m)
        wl:SetSize(width, #values * 18 + 4)
        wl:SetPoint("BOTTOMLEFT", button, "TOPLEFT", 0, 2)
        wl:SetFrameLevel(m:GetFrameLevel() + 20)
        wl:EnableMouse(true)
        local wbg = wl:CreateTexture(nil, "BACKGROUND"); wbg:SetAllPoints(); wbg:SetColorTexture(0.05, 0.08, 0.15, 0.98)
        local wedge = wl:CreateTexture(nil, "BORDER"); wedge:SetPoint("TOPLEFT", -1, 1); wedge:SetPoint("BOTTOMRIGHT", 1, -1)
        wedge:SetColorTexture(0.2, 0.5, 0.8, 1)
        wl.items = {}
        for i, v in ipairs(values) do
            local it = CreateFrame("Button", nil, wl)
            it:SetSize(width - 4, 18); it:SetPoint("TOPLEFT", 2, -2 - (i - 1) * 18)
            local hl = it:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(0.3, 0.5, 0.8, 0.5)
            it.text = it:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); it.text:SetPoint("LEFT", 6, 0)
            it.text:SetText(text(v))
            it.value = v
            it:SetScript("OnClick", function() wl:Hide(); onPick(v); m:FillPanel(); BW.Update() end)
            wl.items[i] = it
        end
        wl:Hide()
        button:SetScript("OnClick", function() wl:SetShown(not wl:IsShown()) end)
        return wl
    end
    local warn = smallButton(80, 10, 71, "Amber warning before a 'Panel: gone' buff runs out. Click to choose 10 to 30 seconds.")
    m.warnButton = warn
    m.warnList = dropdown(warn, L.WARN_CHOICES, function(v) return v .. " seconds" end,
        function(v) pdb().warnSecs = v end)
    local bar = smallButton(76, 236, 27, "Size of the small icons on your bar. Click to choose.")
    m.barSizeButton = bar
    m.barSizeList = dropdown(bar, L.BUFF_ICON_SIZES, function(v) return v .. " px" end,
        function(v) db().barSize = v end)
    local snd = smallButton(160, 96, 71, "Sound when an alert starts. Click to choose; each one plays when picked.")
    m.soundButton = snd
    local soundKeys, soundLabels = {}, {}
    for _, s in ipairs(D.alertSounds) do soundKeys[#soundKeys + 1] = s.key; soundLabels[s.key] = s.label end
    m.soundList = dropdown(snd, soundKeys, function(k) return soundLabels[k] end,
        function(k) pdb().sound = k; BW.PlayAlert(true) end, 140)
    local lock = CreateFrame("CheckButton", nil, m, "UICheckButtonTemplate")
    lock:SetSize(20, 20); lock:SetPoint("BOTTOMLEFT", 8, 48)
    lock:SetHitRectInsets(0, -260, 0, 0)            -- the label is clickable too
    local ll = lock:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); ll:SetPoint("LEFT", lock, "RIGHT", 2, 0)
    ll:SetText("Lock alert panel (untick to move and resize it)")
    lock:SetScript("OnClick", function(self) BW.SetPanelLocked(self:GetChecked() and true or false) end)
    m.lockCheck = lock
    function m:FillPanel()
        local p = pdb()
        self.lockCheck:SetChecked(p.locked)
        self.warnButton.text:SetText("Warn: " .. L.ClampWarn(p.warnSecs) .. "s")
        self.warnList:Hide()
        self.barSizeButton.text:SetText("Bar: " .. BW.BarSize() .. " px")
        self.barSizeList:Hide()
        local label = "Off"
        for _, s in ipairs(D.alertSounds) do if s.key == p.sound then label = s.label end end
        self.soundButton.text:SetText("Sound: " .. label)
        self.soundList:Hide()
    end
    local hide = CreateFrame("CheckButton", nil, m, "UICheckButtonTemplate")
    hide:SetSize(20, 20); hide:SetPoint("BOTTOMLEFT", 8, 26)
    hide:SetHitRectInsets(0, -200, 0, 0)            -- the label is clickable too
    local hl = hide:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); hl:SetPoint("LEFT", hide, "RIGHT", 2, 0)
    hl:SetText("Hide icons while the buff is up")
    hide:SetScript("OnShow", function(self) self:SetChecked(db().hideWhileUp) end)
    hide:SetScript("OnClick", function(self) db().hideWhileUp = self:GetChecked() and true or false; BW.Update() end)
    m.hideCheck = hide
    local hint = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); hint:SetPoint("BOTTOMLEFT", 8, 8)
    hint:SetText("|cff999999Icons sit on your own bar and flash when missing|r")
    function m:Fill()
        local rows = BW.Candidates()
        self.items = rows
        local maxOff = math.max(0, #rows - MENU_ROWS)
        if self.offset > maxOff then self.offset = maxOff end
        for i, r in ipairs(self.rows) do
            local row = rows[i + self.offset]
            r.row = row
            if row then
                r:SetChecked(row.checked)
                r.icon:SetTexture(row.icon or C.GetSpellIcon((row.accept and row.accept[1]) or row.key) or QMARK)
                r.text:SetText(row.harmful and ("|cffff8080" .. row.label .. "|r") or row.label)
                r:Show()
                local e = row.checked and BW.Entry(row)
                if e then r.mode.text:SetText(L.AlertModeLabel(L.AlertMode(e))); r.mode:Show() else r.mode:Hide() end
            else
                r:Hide()
                r.mode:Hide()
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

-- anchor: the button it drops from (nil = screen centre).
function BW.ToggleMenu(anchor)
    BW.menu = BW.menu or buildMenu()
    local m = BW.menu
    if m:IsShown() then m:Hide(); return end
    m:ClearAllPoints()
    if anchor then m:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 4) else m:SetPoint("CENTER") end
    m.offset = 0
    m:Show()
    m:Fill()
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------
function BW.Init()
    local F = ns.Frames
    BW.holder = CreateFrame("Frame", "SanctumBuffWatch", F.anchor)
    BW.holder:SetSize(BW.BarSize(), BW.BarSize())
    BW.icons = {}
    pdb().warnSecs = L.ClampWarn(pdb().warnSecs)    -- 10 to 30 s (0.7.0 test builds allowed off and 60)
    pdb().sound = L.ValidSound(D.alertSounds, pdb().sound)   -- test builds had an own-file option
    pdb().soundFile = nil
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
    ns.On("UNIT_AURA", function(_, unit) if unit == "player" then BW.Update() end end)
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
                         "UNIT_INVENTORY_CHANGED", "PLAYER_REGEN_ENABLED" }) do
        ns.On(e, function() BW.Update() end)
    end
    BW.driver = CreateFrame("Frame", nil, UIParent)
    BW.driver:SetScript("OnUpdate", onUpdate)
    BW.ready = true
    BW.Update()
end

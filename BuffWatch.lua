-- Sanctum / BuffWatch.lua
-- Self buff watch: a row of icons on your own bar (never party). Pick the buffs
-- from the Buff watch dropdown; an icon shows time left while the buff is up and
-- flashes red when it is missing or falls off.

local ADDON, ns = ...
local BW = {}
ns.BuffWatch = BW
local D, L, C = ns.Data, ns.Logic, ns.C

local SIZE, GAP, MAX_ICONS = 22, 3, 8
local MENU_ROWS = 12
local QMARK = "Interface\\Icons\\INV_Misc_QuestionMark"
local issecret = issecretvalue or function() return false end

local function db() return ns.cdb.buffWatch end

---------------------------------------------------------------------------
-- Reading your buffs
---------------------------------------------------------------------------
-- Returns auras { [name] = { icon, expirationTime } } or nil when Forever blocked
-- the read (secret auras in combat), so the caller keeps the last known state.
function BW.ReadAuras()
    local before = C.auraBlocked or 0
    local auras = {}
    C.ForEachAura("player", "HELPFUL", function(a)
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
    b:SetSize(SIZE, SIZE)
    b:SetPoint("LEFT", BW.holder, "LEFT", (i - 1) * (SIZE + GAP), 0)
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
    if #tracked == 0 or UnitIsDeadOrGhost("player") then BW.holder:Hide(); return end
    local auras = BW.ReadAuras()
    if auras then BW.lastAuras = auras end
    local now = GetTime()
    local states = L.BuffWatchState(tracked, BW.lastAuras or {}, now, BW.ReadWeapon())
    local anyMissing = false
    local n = 0
    for i, st in ipairs(states) do
        if i > MAX_ICONS then break end
        local b = BW.icons[i] or makeIcon(i)
        BW.icons[i] = b
        b.state = st
        if st.up and db().hideWhileUp then
            b:Hide()
        else
            n = n + 1
            b:ClearAllPoints()
            b:SetPoint("LEFT", BW.holder, "LEFT", (n - 1) * (SIZE + GAP), 0)
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
    BW.holder:SetSize(math.max(1, n * (SIZE + GAP)), SIZE)
    BW.holder:SetShown(n > 0)
    BW.flashing = anyMissing
end

-- Flash: missing icons pulse between full and faint.
local function onUpdate(_, elapsed)
    BW.t = (BW.t or 0) + elapsed
    BW.acc = (BW.acc or 0) + elapsed
    if BW.acc >= 0.5 then BW.acc = 0; BW.Update() end   -- timers tick down, imbues expire
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

function BW.Candidates()
    return L.BuffWatchCandidates(D.buffWatch[ns.class], ns.known, currentBuffs(), db().list)
end

function BW.SetTracked(row, on)
    local list = db().list
    for i = #list, 1, -1 do if list[i].key == row.key then table.remove(list, i) end end
    if on then
        list[#list + 1] = { key = row.key, label = row.label, accept = row.accept, weapon = row.weapon,
                            icon = row.icon or C.GetSpellIcon((row.accept and row.accept[1]) or row.key) }
    end
    BW.Update()
end

local function buildMenu()
    local m = CreateFrame("Frame", "SanctumBuffWatchMenu", UIParent)
    m:SetSize(250, 74 + MENU_ROWS * 20)
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
        r:SetScript("OnClick", function(self)
            if self.row then BW.SetTracked(self.row, self:GetChecked() and true or false); m:Fill() end
        end)
        m.rows[i] = r
    end
    local hide = CreateFrame("CheckButton", nil, m, "UICheckButtonTemplate")
    hide:SetSize(20, 20); hide:SetPoint("BOTTOMLEFT", 8, 26)
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
                r.text:SetText(row.label)
                r:Show()
            else
                r:Hide()
            end
        end
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
    BW.holder:SetSize(SIZE, SIZE)
    BW.icons = {}
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

-- Sanctum / Frames.lua
-- Own party frames: player + party1-4 as SecureUnitButtons with click-casting.
-- Static unit slots (party units are always contiguous) + RegisterUnitWatch,
-- so nothing protected is touched in combat.

local ADDON, ns = ...
local F = {}
ns.Frames = F

local D, L, C = ns.Data, ns.Logic, ns.C
local UNITS = { "player", "party1", "party2", "party3", "party4" }
local TEX = "Interface\\TargetingFrame\\UI-StatusBar"
local MANA_H = 6

F.buttons, F.byUnit = {}, {}
F.canDispel, F.rangeSpell, F.report = {}, nil, {}

local FAKE = {
    party1 = { name = "Tankadin", class = "PALADIN", hp = 0.92, mana = 0.6, aggro = true },
    party2 = { name = "Stabbsy",  class = "ROGUE",   hp = 0.45, mana = 0.8, power = 3, debuff = "Poison" },
    party3 = { name = "Frostbyte", class = "MAGE",   hp = 0.18, mana = 0.3, debuff = "Magic" },
    party4 = { name = "Dotsworth", class = "WARLOCK", hp = 0,   mana = 0.5, dead = true },
}

local function abbrev(n)
    if n >= 10000 then return ("%.0fk"):format(n / 1000) end
    if n >= 1000 then return ("%.1fk"):format(n / 1000) end
    return tostring(math.floor(n))
end

local function classColour(class)
    local c = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class]) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
    if c then return c.r, c.g, c.b end
    return 0.2, 0.8, 0.2
end

-- Own power colours (Blizzard's mana blue is near-invisible at 6px).
local POWER_COLOURS = {
    [0] = { 0.25, 0.55, 1.0 },  -- mana
    [1] = { 0.9, 0.15, 0.15 },  -- rage
    [2] = { 1.0, 0.5, 0.25 },   -- focus
    [3] = { 1.0, 0.9, 0.2 },    -- energy
}
local function powerColour(pt)
    local c = POWER_COLOURS[pt or 0] or POWER_COLOURS[0]
    return c[1], c[2], c[3]
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------
local function makeBorder(b)
    local o = CreateFrame("Frame", nil, b)
    o:SetAllPoints()
    o:SetFrameLevel(b:GetFrameLevel() + 5)
    local t = {}
    for i = 1, 4 do t[i] = o:CreateTexture(nil, "OVERLAY") end
    t[1]:SetPoint("TOPLEFT"); t[1]:SetPoint("TOPRIGHT"); t[1]:SetHeight(2)
    t[2]:SetPoint("BOTTOMLEFT"); t[2]:SetPoint("BOTTOMRIGHT"); t[2]:SetHeight(2)
    t[3]:SetPoint("TOPLEFT"); t[3]:SetPoint("BOTTOMLEFT"); t[3]:SetWidth(2)
    t[4]:SetPoint("TOPRIGHT"); t[4]:SetPoint("BOTTOMRIGHT"); t[4]:SetWidth(2)
    b.borderTex = t
    b.overlay = o
end

local function setBorder(b, r, g, bl, a)
    for _, t in ipairs(b.borderTex) do t:SetColorTexture(r, g, bl, a or 1) end
end

-- Optional downrank zones: three secure child buttons per bar (left third = lowest rank,
-- middle = middle rank, right = highest). Created hidden and without attributes; shown and
-- configured only out of combat by F.ApplyZones, and only when the option is on.
local function zoneTooltip(z)
    local b = z.bar
    if UnitExists(b.unit) then
        GameTooltip_SetDefaultAnchor(GameTooltip, z)
        GameTooltip:SetUnit(b.unit)
        local label = ({ low = "Left third: lowest rank", mid = "Middle third: middle rank", max = "Right third: highest rank" })[z.zone]
        GameTooltip:AddLine(label, 0.7, 0.7, 0.7)
        -- Read-only: shows exactly what this zone's attributes will cast (safe in combat).
        local top = b.zones[#b.zones]
        for _, line in ipairs(L.ZoneTooltipLines(z.zone,
            function(k) return z:GetAttribute(k) end, function(k) return top:GetAttribute(k) end, D.clickSlots)) do
            GameTooltip:AddLine(line, 1, 1, 1)
        end
        GameTooltip:Show()
    end
end

local function createZones(b, i)
    b.zones = {}
    for n, key in ipairs(L.ZONES) do
        local z = CreateFrame("Button", "SanctumUnitButton" .. i .. "Zone" .. n, b, "SecureUnitButtonTemplate")
        z.bar, z.zone = b, key
        z:SetAttribute("unit", b.unit)
        z:RegisterForClicks(ns.ClickEdge())
        z:SetFrameLevel(b:GetFrameLevel() + 10)
        local hl = z:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.12)
        z:SetScript("OnEnter", zoneTooltip)
        z:SetScript("OnLeave", function() GameTooltip:Hide() end)
        z:Hide()
        b.zones[n] = z
    end
    -- Faint divider lines on the (non-secure) overlay so the zones are visible.
    b.zoneLines = {}
    for n = 1, 2 do
        local t = b.overlay:CreateTexture(nil, "OVERLAY")
        t:SetWidth(1)
        t:SetColorTexture(1, 1, 1, 0.25)
        t:Hide()
        b.zoneLines[n] = t
    end
end

local function createButton(i, unit)
    local db = ns.db.frames
    local b = CreateFrame("Button", "SanctumUnitButton" .. i, F.anchor, "SecureUnitButtonTemplate")
    b.unit = unit
    b:SetAttribute("unit", unit)
    b:RegisterForClicks(ns.ClickEdge())
    b:SetSize(db.width, db.height)

    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0, 0, 0, 0.75)

    b.health = CreateFrame("StatusBar", nil, b)
    b.health:SetStatusBarTexture(TEX)
    b.health:SetMinMaxValues(0, 1)

    b.predict = b.health:CreateTexture(nil, "ARTWORK")
    b.predict:SetTexture(TEX)
    b.predict:SetVertexColor(0.3, 1, 0.3, 0.45)
    b.predict:Hide()

    b.mana = CreateFrame("StatusBar", nil, b)
    b.mana:SetStatusBarTexture(TEX)
    b.mana:SetMinMaxValues(0, 1)
    b.mana:SetStatusBarColor(powerColour(0))
    local mbg = b.mana:CreateTexture(nil, "BACKGROUND")
    mbg:SetAllPoints()
    mbg:SetColorTexture(0.05, 0.1, 0.25, 1)

    makeBorder(b)
    local o = b.overlay

    b.nameText = o:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.nameText:SetPoint("TOPLEFT", 5, -5)
    b.nameText:SetJustifyH("LEFT")
    b.hpText = o:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.hpText:SetPoint("BOTTOMRIGHT", -4, MANA_H + 4)
    b.statusText = o:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.statusText:SetPoint("CENTER", 0, 2)

    -- Tracked-aura corner squares, top-right, growing left.
    b.ind = {}
    for k = 1, 4 do
        local t = o:CreateTexture(nil, "OVERLAY")
        t:SetSize(8, 8)
        t:SetPoint("TOPRIGHT", -3 - (k - 1) * 10, -3)
        t:Hide()
        b.ind[k] = t
    end
    -- Missing group buff dot, bottom-left.
    b.buffDot = o:CreateTexture(nil, "OVERLAY")
    b.buffDot:SetSize(6, 6)
    b.buffDot:SetPoint("BOTTOMLEFT", 4, MANA_H + 5)
    b.buffDot:SetColorTexture(0.7, 0.4, 1, 1)
    b.buffDot:Hide()
    -- Debuff icons, right side above hp text.
    b.debuffs = {}
    for k = 1, 2 do
        local t = o:CreateTexture(nil, "OVERLAY")
        t:SetSize(14, 14)
        t:SetPoint("RIGHT", -4 - (k - 1) * 16, 3)
        t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        t:Hide()
        b.debuffs[k] = t
    end

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.12)

    b:SetScript("OnEnter", function(self)
        if UnitExists(self.unit) then
            GameTooltip_SetDefaultAnchor(GameTooltip, self)
            GameTooltip:SetUnit(self.unit)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:HookScript("OnShow", function(self) F.UpdateUnit(self); F.UpdateAuras(self); F.PlaceGrip() end)
    b:HookScript("OnHide", function() F.PlaceGrip() end)

    createZones(b, i)
    F.LayoutButton(b)
    RegisterUnitWatch(b)
    return b
end

function F.LayoutButton(b)
    local db = ns.db.frames
    b:SetSize(db.width, db.height)
    local manaH = db.showMana and MANA_H or 0
    b.health:ClearAllPoints()
    b.health:SetPoint("TOPLEFT", 2, -2)
    b.health:SetPoint("BOTTOMRIGHT", -2, 2 + manaH)
    b.mana:ClearAllPoints()
    b.mana:SetPoint("BOTTOMLEFT", 2, 2)
    b.mana:SetPoint("BOTTOMRIGHT", -2, 2)
    b.mana:SetHeight(math.max(manaH, 1))
    b.mana:SetShown(db.showMana)
    b.nameText:SetWidth(db.width - 40)
    if b.zones then   -- downrank zones: equal thirds (sizes only change out of combat, like the bar itself)
        local third = db.width / 3
        for n, z in ipairs(b.zones) do
            z:ClearAllPoints()
            z:SetPoint("TOPLEFT", b, "TOPLEFT", (n - 1) * third, 0)
            z:SetSize(third, db.height)
        end
        for n, t in ipairs(b.zoneLines) do
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", b.overlay, "TOPLEFT", n * third, -4)
            t:SetPoint("BOTTOMLEFT", b.overlay, "BOTTOMLEFT", n * third, 4)
        end
    end
end

function F.Layout()
    local db = ns.db.frames
    for idx, b in ipairs(F.buttons) do
        local pos = db.showSelfFirst and idx or ((idx == 1) and #F.buttons or idx - 1)
        b.pos = pos
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", F.anchor, "TOPLEFT", 0, -((pos - 1) * (db.height + db.spacing)))
        F.LayoutButton(b)
    end
    F.anchor:SetSize(db.width, #F.buttons * (db.height + db.spacing))
    F.anchor:SetScale(db.scale)
    F.PlaceGrip()
end

-- Bars currently on screen, and the bottom-most one (the grip sits on it).
function F.VisibleBars()
    local n, last = 0, nil
    for _, b in ipairs(F.buttons) do
        if b:IsShown() then
            n = n + 1
            if not last or (b.pos or 0) > (last.pos or 0) then last = b end
        end
    end
    return n, last
end

function F.PlaceGrip()
    local g = F.grip
    if not g then return end
    local _, last = F.VisibleBars()
    g:ClearAllPoints()
    g:SetPoint("TOPLEFT", last or F.anchor, last and "BOTTOMRIGHT" or "TOPRIGHT", -6, 6)
end

function F.Reposition()
    local db = ns.db.frames
    F.anchor:ClearAllPoints()
    F.anchor:SetPoint(db.point, UIParent, db.point, db.x, db.y)
end

function F.UpdateLock()
    F.handle:SetShown(not ns.db.frames.locked)
    if F.grip then F.grip:SetShown(not ns.db.frames.locked) end
end

---------------------------------------------------------------------------
-- Resize grip (bottom-right, unlocked only). Drag right/left = bar width,
-- drag down/up = bar height. Out of combat only (bars are secure frames).
---------------------------------------------------------------------------
local function buildGrip()
    local db = ns.db.frames
    local g = CreateFrame("Button", nil, F.anchor)
    g:SetSize(16, 16)
    g:SetFrameLevel(F.anchor:GetFrameLevel() + 20)
    g:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    g:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    g:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    local sx, sy, sw, sh
    local function stop(self)
        self:SetScript("OnUpdate", nil)
        F.UpdateAll()
        ns.Print("bar size %d x %d", db.width, db.height)
    end
    g:SetScript("OnMouseDown", function(self)
        if InCombatLockdown() then ns.Print("can't resize in combat"); return end
        local s = F.anchor:GetEffectiveScale()
        sx, sy = GetCursorPosition(); sx, sy = sx / s, sy / s
        sw, sh = db.width, db.height
        local bars = math.max(1, (F.VisibleBars()))
        local acc = 0
        self:SetScript("OnUpdate", function(_, elapsed)
            if InCombatLockdown() then stop(self); return end
            local x, y = GetCursorPosition(); x, y = x / s, y / s
            local w, h = L.ClampBarSize(sw + (x - sx), sh + (sy - y) / bars)
            if w ~= db.width or h ~= db.height then
                db.width, db.height = w, h
                F.Layout()
                acc = acc + elapsed
                if acc > 0.1 then acc = 0; F.UpdateAll() end
            end
        end)
    end)
    g:SetScript("OnMouseUp", function(self) if self:GetScript("OnUpdate") then stop(self) end end)
    g:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Resize bars")
        GameTooltip:AddLine("Drag sideways for width, up/down for height.", 1, 1, 1)
        GameTooltip:Show()
    end)
    g:SetScript("OnLeave", function() GameTooltip:Hide() end)
    F.grip = g
end

-- Single entry point for lock changes (header button, minimap, options, slash).
function F.SetLocked(v)
    ns.db.frames.locked = v and true or false
    F.UpdateLock()
    if ns.db.frames.locked then
        ns.Print("frames locked - right-click the minimap icon or /sanc unlock to move them")
    else
        ns.Print("frames unlocked - drag the blue bar, click Lock when done")
    end
    if ns.Options and ns.Options.Refresh then ns.Options.Refresh() end
end

---------------------------------------------------------------------------
-- Click-casting
---------------------------------------------------------------------------
function F.ApplyBindings()
    if InCombatLockdown() then return ns.RunOOC("bindings", F.ApplyBindings) end
    local attrs, report = L.BuildClickAttributes(ns.cdb.bindings, D.clickSlots, ns.IsKnown)
    for _, b in ipairs(F.buttons) do
        for _, slot in ipairs(D.clickSlots) do
            for _, k in ipairs(L.SlotAttributeKeys(slot)) do b:SetAttribute(k, nil) end
        end
        for k, v in pairs(attrs) do b:SetAttribute(k, v) end
    end
    F.report = report
    F.rangeSpell = attrs["spell1"]
    F.canDispel = L.DispelTypes(D.dispelSpells, ns.IsKnown)
    for _, b in ipairs(F.buttons) do F.UpdateAuras(b) end
    F.ApplyZones()
end

-- Downrank zones. Option off (default): every zone is hidden and has no attributes, so the
-- single bar behaves exactly as before. Option on: each zone gets the same bindings with the
-- rank chosen automatically from the ranks you know. Protected, so out of combat only.
function F.ApplyZones()
    if InCombatLockdown() then return ns.RunOOC("zones", F.ApplyZones) end
    local on = ns.db.frames.downrank == true
    local zattrs, info
    if on then
        zattrs, info = L.BuildZoneAttributes(ns.cdb.bindings, D.clickSlots, ns.IsKnown, ns.ranks, D.downrankable)
    end
    for _, b in ipairs(F.buttons) do
        if b.zones then
            for n, z in ipairs(b.zones) do
                for _, slot in ipairs(D.clickSlots) do
                    for _, k in ipairs(L.SlotAttributeKeys(slot)) do z:SetAttribute(k, nil) end
                end
                z:SetAttribute("type1", nil)
                if on then
                    for k, v in pairs(zattrs[z.zone]) do z:SetAttribute(k, v) end
                end
                z:SetShown(on)
            end
            for _, t in ipairs(b.zoneLines) do t:SetShown(on) end
        end
    end
    F.zoneInfo = info
end

function F.SyncClickEdge()
    for _, b in ipairs(F.buttons) do b:RegisterForClicks(ns.ClickEdge()) end
end

---------------------------------------------------------------------------
-- Updates
---------------------------------------------------------------------------
-- Secret values: WoW: Forever (like retail Midnight) returns some unit values
-- (confirmed: UnitPower) as "secret" numbers/booleans. Widgets accept them
-- (StatusBar:SetValue, SetAlphaFromBoolean, FontString:SetText), but addon Lua
-- may not do arithmetic, compare or branch on them. Every value is checked
-- with issecret() before maths; anything secret goes straight to a widget.
local issecret = issecretvalue or function() return false end
F.issecret = issecret

local function plain(v) if issecret(v) then return nil end return v end

local reported = {}
local function guarded(name, fn)
    return function(b)
        local ok, err = pcall(fn, b)
        if not ok then
            local key = name .. tostring(err)
            if not reported[key] then
                reported[key] = true
                ns.Print("|cffff4040%s error (reported once):|r %s", name, tostring(err))
            end
        end
    end
end

local function data(b)
    local unit = b.unit
    if UnitExists(unit) then
        local _, class = UnitClass(unit)
        local pt = UnitPowerType(unit)
        return {
            name = UnitName(unit), class = plain(class),
            hp = UnitHealth(unit), max = UnitHealthMax(unit),
            power = plain(pt) or 0, pow = UnitPower(unit, pt), pmax = UnitPowerMax(unit, pt),
            dead = plain(UnitIsDeadOrGhost(unit)), ghost = plain(UnitIsGhost(unit)),
            offline = plain(UnitIsConnected(unit)) == false,
            incoming = C.IncomingHeals(unit),
        }
    end
    local f = b.fake
    if f then
        return { name = f.name, class = f.class, hp = f.hp * 3000, max = 3000, power = f.power or 0,
                 pow = f.mana, pmax = 1, dead = f.dead, offline = false,
                 incoming = (f.hp > 0 and f.hp < 0.5) and 600 or 0 }
    end
end

local function updateUnit(b)
    local d = data(b)
    if not d then return end
    local db = ns.db.frames
    b.nameText:SetText(d.name or "?")

    -- Health bar: raw values straight into the widget (secret-safe).
    b.health:SetMinMaxValues(0, d.max or 1)
    if d.dead then b.health:SetValue(0) else b.health:SetValue(d.hp or 0) end

    -- Maths only when the numbers are plain.
    local hp, max = plain(d.hp), plain(d.max)
    local frac
    if hp and max and max > 0 then frac = math.min(hp / max, 1) end

    if d.offline or d.dead then
        b.health:SetStatusBarColor(0.35, 0.35, 0.35)
    elseif db.classColours and d.class then
        b.health:SetStatusBarColor(classColour(d.class))
    elseif frac then
        b.health:SetStatusBarColor(1 - frac, frac, 0)
    else
        b.health:SetStatusBarColor(0.2, 0.8, 0.2)
    end
    if d.offline then b.statusText:SetText("OFFLINE")
    elseif d.ghost then b.statusText:SetText("GHOST")
    elseif d.dead then b.statusText:SetText("DEAD")
    else b.statusText:SetText("") end

    if frac and not d.dead and not d.offline and max - hp > 0 then
        b.hpText:SetText("-" .. abbrev(max - hp))
    else
        b.hpText:SetText("")
    end

    -- Incoming heal overlay (plain numbers only).
    local inc = plain(d.incoming) or 0
    local w = b.health:GetWidth()
    if frac and inc > 0 and not d.dead and frac < 1 and w and w > 0 then
        local incFrac = math.min(inc / max, 1 - frac)
        b.predict:ClearAllPoints()
        b.predict:SetPoint("TOPLEFT", b.health, "TOPLEFT", w * frac, 0)
        b.predict:SetPoint("BOTTOMLEFT", b.health, "BOTTOMLEFT", w * frac, 0)
        b.predict:SetWidth(math.max(w * incFrac, 1))
        b.predict:Show()
    else
        b.predict:Hide()
    end

    if db.showMana then
        b.mana:SetMinMaxValues(0, d.pmax or 1)
        b.mana:SetValue(d.pow or 0)
        b.mana:SetStatusBarColor(powerColour(d.power))
    end
    F.UpdateBorder(b)
end
F.UpdateUnit = guarded("UpdateUnit", updateUnit)

local function updateAuras(b)
    local unit = b.unit
    for _, t in ipairs(b.ind) do t:Hide() end
    for _, t in ipairs(b.debuffs) do t:Hide() end
    b.buffDot:Hide()
    b.dispel = nil

    if not UnitExists(unit) then
        local f = b.fake
        if f and f.debuff and F.canDispel[f.debuff] then
            b.dispel = f.debuff
            b.debuffs[1]:SetTexture("Interface\\Icons\\Spell_Holy_DispelMagic"); b.debuffs[1]:Show()
        end
        F.UpdateBorder(b)
        return
    end

    -- Tracked aura indicators. Secret aura fields are skipped, never compared.
    local tracked = D.trackedAuras[ns.class] or {}
    local slot = 0
    for _, ta in ipairs(tracked) do
        local found = false
        C.ForEachAura(unit, ta.filter, function(a)
            local name, src = plain(a.name), plain(a.sourceUnit)
            if name == ta.name and (not ta.mine or src == "player") then found = true; return true end
        end)
        if found then
            slot = slot + 1
            local t = b.ind[slot]
            if t then t:SetColorTexture(ta.colour[1], ta.colour[2], ta.colour[3], 1); t:Show() end
        end
    end

    -- Debuffs: dispellable first. Icons are passed through even if secret.
    local debuffs = {}
    C.ForEachAura(unit, "HARMFUL", function(a)
        debuffs[#debuffs + 1] = { icon = a.icon, dispelName = plain(a.dispelName) }
    end)
    b.dispel = L.PickDispel(debuffs, F.canDispel)
    table.sort(debuffs, function(x, y)
        local dx = x.dispelName and F.canDispel[x.dispelName] and 1 or 0
        local dy = y.dispelName and F.canDispel[y.dispelName] and 1 or 0
        return dx > dy
    end)
    for k = 1, math.min(2, #debuffs) do
        b.debuffs[k]:SetTexture(debuffs[k].icon)
        b.debuffs[k]:Show()
    end

    -- Missing group buff (only when you know it, out of combat, unit alive).
    local gb = D.groupBuff[ns.class]
    if gb and ns.IsKnown(gb[1]) and not InCombatLockdown() and plain(UnitIsDeadOrGhost(unit)) == false then
        local has = false
        C.ForEachAura(unit, "HELPFUL", function(a)
            local name = plain(a.name)
            for _, n in ipairs(gb) do if name == n then has = true; return true end end
        end)
        b.buffDot:SetShown(not has)
    end
    F.UpdateBorder(b)
end
F.UpdateAuras = guarded("UpdateAuras", updateAuras)

local function updateBorder(b)
    local unit = b.unit
    if b.dispel then
        local c = D.dispelColours[b.dispel] or { 1, 1, 1 }
        setBorder(b, c[1], c[2], c[3], 1)
        return
    end
    local aggro = false
    if UnitExists(unit) then
        local s = UnitThreatSituation and plain(UnitThreatSituation(unit))
        aggro = s ~= nil and s >= 2
    elseif b.fake then
        aggro = b.fake.aggro
    end
    local isTarget = false
    if UnitExists(unit) and UnitExists("target") then
        local g1, g2 = plain(UnitGUID(unit)), plain(UnitGUID("target"))
        isTarget = g1 ~= nil and g1 == g2
    end
    if aggro then setBorder(b, 1, 0.1, 0.1, 1)
    elseif isTarget then setBorder(b, 1, 1, 1, 0.9)
    else setBorder(b, 0, 0, 0, 1) end
end
F.UpdateBorder = guarded("UpdateBorder", updateBorder)

-- Range: secret booleans go to SetAlphaFromBoolean, plain ones are branched on.
local function applyRange(b, r)
    if issecret(r) then
        if b.SetAlphaFromBoolean then b:SetAlphaFromBoolean(r, 1, 0.4) else b:SetAlpha(1) end
        return true
    end
    if r == nil then return false end
    b:SetAlpha(r and 1 or 0.4)
    return true
end

local function updateRange(b)
    local unit = b.unit
    if not UnitExists(unit) or unit == "player" then b:SetAlpha(1); return end
    if F.rangeSpell and applyRange(b, C.IsSpellInRange(F.rangeSpell, unit)) then return end
    if UnitInRange then
        local r, checked = UnitInRange(unit)
        if issecret(r) then applyRange(b, r); return end
        if plain(checked) and r ~= nil then b:SetAlpha(r and 1 or 0.4); return end
    end
    b:SetAlpha(1)
end
F.UpdateRange = guarded("UpdateRange", updateRange)

function F.UpdateAll()
    for _, b in ipairs(F.buttons) do
        if b:IsShown() then F.UpdateUnit(b); F.UpdateAuras(b); F.UpdateRange(b) end
    end
end

---------------------------------------------------------------------------
-- Test mode
---------------------------------------------------------------------------
function F.ToggleTest()
    if InCombatLockdown() then ns.Print("not in combat"); return end
    F.test = not F.test
    for _, b in ipairs(F.buttons) do
        if b.unit ~= "player" then
            if F.test then
                b.fake = FAKE[b.unit]
                UnregisterUnitWatch(b)
                b:Show()
            else
                b.fake = nil
                RegisterUnitWatch(b)
            end
        end
    end
    F.UpdateAll()
    ns.Print("test mode %s", F.test and "on" or "off")
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------
function F.Init()
    local db = ns.db.frames
    local anchor = CreateFrame("Frame", "SanctumPartyAnchor", UIParent)
    anchor:SetMovable(true)
    anchor:SetClampedToScreen(true)
    F.anchor = anchor
    F.Reposition()

    local h = CreateFrame("Frame", nil, anchor)
    h:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 2)
    h:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 2)
    h:SetHeight(14)
    h:EnableMouse(true)
    h:RegisterForDrag("LeftButton")
    local ht = h:CreateTexture(nil, "BACKGROUND"); ht:SetAllPoints(); ht:SetColorTexture(0.11, 0.12, 0.155, 0.9)
    local hs = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); hs:SetPoint("LEFT", 4, 0); hs:SetText("Sanctum - drag")
    -- Lock button on the header.
    local lb = CreateFrame("Button", nil, h)
    lb:SetSize(36, 14)
    lb:SetPoint("RIGHT", -1, 0)
    local lbg = lb:CreateTexture(nil, "ARTWORK"); lbg:SetAllPoints(); lbg:SetColorTexture(0.15, 0.165, 0.20, 1)
    local lt = lb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); lt:SetPoint("CENTER"); lt:SetText("Lock")
    local lhl = lb:CreateTexture(nil, "HIGHLIGHT"); lhl:SetAllPoints(); lhl:SetColorTexture(1, 1, 1, 0.2)
    lb:SetScript("OnClick", function() F.SetLocked(true) end)
    lb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Lock frames")
        GameTooltip:AddLine("Unlock again: right-click the minimap icon,", 1, 1, 1)
        GameTooltip:AddLine("the Options window, or /sanc unlock", 1, 1, 1)
        GameTooltip:Show()
    end)
    lb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    h:SetScript("OnDragStart", function() if not InCombatLockdown() then anchor:StartMoving() end end)
    h:SetScript("OnDragStop", function()
        anchor:StopMovingOrSizing()
        local p, _, _, x, y = anchor:GetPoint()
        db.point, db.x, db.y = p, x, y
    end)
    F.handle = h
    buildGrip()
    F.PlaceGrip()

    for i, unit in ipairs(UNITS) do
        local b = createButton(i, unit)
        F.buttons[i] = b
        F.byUnit[unit] = b
    end
    F.Layout()
    F.UpdateLock()
    F.ApplyBindings()

    local function unitEvent(_, unit)
        local b = unit and F.byUnit[unit]
        if b and b:IsShown() then F.UpdateUnit(b) end
    end
    for _, e in ipairs({ "UNIT_HEALTH", "UNIT_HEALTH_FREQUENT", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT",
                         "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_CONNECTION", "UNIT_NAME_UPDATE",
                         "UNIT_HEAL_PREDICTION", "UNIT_THREAT_SITUATION_UPDATE" }) do
        ns.On(e, unitEvent)
    end
    ns.On("UNIT_AURA", function(_, unit)
        local b = unit and F.byUnit[unit]
        if b and b:IsShown() then F.UpdateAuras(b) end
    end)
    ns.On("GROUP_ROSTER_UPDATE", F.UpdateAll)
    ns.On("PLAYER_ENTERING_WORLD", F.UpdateAll)
    ns.On("PLAYER_REGEN_DISABLED", F.UpdateAll)
    ns.On("PLAYER_REGEN_ENABLED", F.UpdateAll)
    ns.On("PLAYER_TARGET_CHANGED", function() for _, b in ipairs(F.buttons) do F.UpdateBorder(b) end end)

    local acc = 0
    anchor:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < 0.2 then return end
        acc = 0
        for _, b in ipairs(F.buttons) do
            if b:IsShown() then F.UpdateRange(b); F.UpdateBorder(b) end
        end
    end)
    F.ready = true
    F.UpdateAll()
end

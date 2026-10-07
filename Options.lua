-- Sanctum / Options.lua
-- One window: click-cast bindings (left), display toggles (bottom-left),
-- sequence editor (right). /sanc opens it.

local ADDON, ns = ...
local O = {}
ns.Options = O
local D, L = ns.Data, ns.Logic

local W, H = 780, 560

local function label(parent, text, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    fs:SetText(text)
    fs:SetJustifyH("LEFT")
    return fs
end

local function editBox(parent, w)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetSize(w, 20)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    return eb
end

local function multiBox(parent, w, h)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(w, h)
    local bg = holder:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.5)
    local sf = CreateFrame("ScrollFrame", nil, holder, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 4, -4)
    sf:SetPoint("BOTTOMRIGHT", -24, 4)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(w - 30)
    eb:SetHeight(h - 8)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    sf:SetScrollChild(eb)
    holder:EnableMouse(true)
    holder:SetScript("OnMouseDown", function() eb:SetFocus() end)
    return eb, holder
end

local function checkbox(parent, text, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    local fs = label(cb, text)
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb:SetScript("OnShow", function(self) self:SetChecked(get()) end)
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    return cb
end


---------------------------------------------------------------------------
-- Spell picker popup: searchable list of castable spells from your spellbook.
-- Click = set binding. Shift-click = add as a fallback (A|B priority list).
---------------------------------------------------------------------------
local PICK_ROWS = 14
local SPECIAL = {
    { name = "Target unit", value = "@target", icon = "Interface\\Icons\\Ability_Hunter_SniperShot" },
    { name = "Unit menu",   value = "@menu",   icon = "Interface\\Icons\\INV_Misc_Note_01" },
    { name = "Clear binding", value = "",      icon = "Interface\\Buttons\\UI-GroupLoot-Pass-Up" },
}

local function buildPicker()
    local p = CreateFrame("Frame", "SanctumSpellPicker", UIParent)
    p:SetSize(250, 46 + PICK_ROWS * 20)
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:EnableMouse(true)
    p:EnableMouseWheel(true)
    p:SetClampedToScreen(true)
    -- 1 px grey border underneath, dark fill inset over it (the old blue edge sat on top and hid the fill)
    local edge = p:CreateTexture(nil, "BACKGROUND", nil, -8); edge:SetAllPoints(); edge:SetColorTexture(0.30, 0.32, 0.38, 1)
    local bg = p:CreateTexture(nil, "BACKGROUND", nil, -7); bg:SetPoint("TOPLEFT", 1, -1); bg:SetPoint("BOTTOMRIGHT", -1, 1)
    bg:SetColorTexture(0.067, 0.075, 0.094, 0.97)
    p.title = label(p, "Pick a spell", "GameFontNormal"); p.title:SetPoint("TOPLEFT", 8, -6)
    local close = CreateFrame("Button", nil, p, "UIPanelCloseButton"); close:SetSize(20, 20); close:SetPoint("TOPRIGHT", 0, 0)
    local hint = label(p, "|cff999999type to filter - shift-click adds a fallback|r"); hint:SetPoint("BOTTOMLEFT", 8, 4)
    p.filter = editBox(p, 220); p.filter:SetPoint("TOPLEFT", 12, -22)
    p.offset = 0
    p.rows = {}
    for i = 1, PICK_ROWS do
        local r = CreateFrame("Button", nil, p)
        r:SetSize(230, 20)
        r:SetPoint("TOPLEFT", 10, -44 - (i - 1) * 20)
        r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(18, 18); r.icon:SetPoint("LEFT")
        r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.text = label(r, ""); r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
        local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.15)
        r:SetScript("OnClick", function(self)
            if self.item and p.onPick then p.onPick(self.item, IsShiftKeyDown()) end
        end)
        p.rows[i] = r
    end
    function p:Fill()
        local f = L.Trim(self.filter:GetText()):lower()
        local items = {}
        if not self.noSpecials then
            for _, it in ipairs(SPECIAL) do
                if f == "" or it.name:lower():find(f, 1, true) then items[#items + 1] = it end
            end
        end
        for _, sp in ipairs(ns.spellList or {}) do
            if f == "" or sp.name:lower():find(f, 1, true) then
                items[#items + 1] = { name = sp.name, value = sp.name, icon = sp.icon, spell = true }
            end
        end
        self.items = items
        local maxOff = math.max(0, #items - PICK_ROWS)
        if self.offset > maxOff then self.offset = maxOff end
        for i, r in ipairs(self.rows) do
            local it = items[i + self.offset]
            r.item = it
            if it then
                r.icon:SetTexture(it.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                r.text:SetText(it.name)
                r:Show()
            else
                r:Hide()
            end
        end
    end
    p.filter:SetScript("OnTextChanged", function() p.offset = 0; p:Fill() end)
    p.filter:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    p:SetScript("OnMouseWheel", function(self, delta)
        self.offset = math.max(0, self.offset - delta * 3)
        self:Fill()
    end)
    tinsert(UISpecialFrames, "SanctumSpellPicker")
    p:Hide()
    return p
end

function O.OpenPicker(anchor, title, onPick, noSpecials)
    O.picker = O.picker or buildPicker()
    local p = O.picker
    p.onPick = onPick
    p.noSpecials = noSpecials
    p.title:SetText(title)
    p.filter:SetText("")
    p.offset = 0
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
    p:Fill()
    p:Show()
end

local function resolvedIcon(value)
    local kind, spell = L.ResolveBinding(value, ns.IsKnown)
    if kind == "target" then return SPECIAL[1].icon end
    if kind == "menu" then return SPECIAL[2].icon end
    if spell then
        for _, sp in ipairs(ns.spellList or {}) do if sp.name == spell then return sp.icon end end
        return ns.C.GetSpellIcon(spell)
    end
    return nil
end

local function statusText(r)
    if not r then return "" end
    if r.kind == "none" then return "|cff808080unbound|r" end
    if r.kind == "target" then return "|cff00ff00target unit|r" end
    if r.kind == "menu" then return "|cff00ff00unit menu|r" end
    if r.spell then return "|cff00ff00> " .. r.spell .. "|r" end
    return "|cffff4040not known yet|r"
end

function O.Refresh()
    local f = O.frame
    if not f or not f:IsShown() then return end
    local byKey = {}
    for _, r in ipairs(ns.Frames.report or {}) do byKey[r.slot.key] = r end
    for _, row in ipairs(f.rows) do
        if not row.edit:HasFocus() then row.edit:SetText(ns.cdb.bindings[row.slot.key] or "") end
        row.status:SetText(statusText(byKey[row.slot.key]))
        local icon = resolvedIcon(ns.cdb.bindings[row.slot.key])
        row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.icon:SetDesaturated(icon == nil)
    end
    local seq = ns.cdb.sequence
    if not f.seqName:HasFocus() then f.seqName:SetText(seq.name or "") end
    if not f.keyPress:HasFocus() then f.keyPress:SetText(table.concat(seq.keyPress or {}, "\n")) end
    if f.textMode and not f.steps:HasFocus() then f.steps:SetText(table.concat(seq.steps or {}, "\n")) end
    O.RefreshSteps()
    if not f.post:HasFocus() then f.post:SetText(table.concat(seq.postMacro or {}, "\n")) end
    local waiting = ns.Sequence.waiting or {}
    f.seqInfo:SetText(("Key: |cffffffff%s|r   Steps active: |cffffffff%d|r%s"):format(
        ns.cdb.seqKey or "none", ns.Sequence.count or 0,
        #waiting > 0 and ("\n|cffffbf20" .. #waiting .. " spell(s) not usable yet - hover their icons|r") or ""))
    for _, c in ipairs(f.checks or {}) do c.cb:SetChecked(c.get()) end
    if f.modeButton then f.modeButton:SetText(ns.cdb.sequence.mode == "priority" and "Mode: Priority" or "Mode: In turn") end
    if not f.enchLvl:HasFocus() then f.enchLvl:SetText(tostring(ns.db.goals.enchantFromLevel)) end
end

local function saveBinding(row)
    local v = L.Trim(row.edit:GetText())
    if (ns.cdb.bindings[row.slot.key] or "") == v then return end
    ns.cdb.bindings[row.slot.key] = v
    if InCombatLockdown() then ns.Print("binding saved - applies when combat ends") end
    ns.Frames.ApplyBindings()
    O.Refresh()
end


---------------------------------------------------------------------------
-- Sequence step rows: [spell icon picker] [name] [target mode] [up][down][x]
---------------------------------------------------------------------------
local STEP_ROWS = 7

local function spellIcon(name)
    for _, sp in ipairs(ns.spellList or {}) do if sp.name == name then return sp.icon end end
    return ns.C.GetSpellIcon(name)
end

local function rebuildSteps()
    ns.Sequence.Build()
    O.RefreshSteps()
    if ns.Talents.CheckAndNotify then ns.Talents.CheckAndNotify() end
    if O.frame and O.frame.seqInfo then C_Timer.After(0, O.Refresh) end
end

function O.RefreshSteps()
    local f = O.frame
    if not f or not f.stepRows then return end
    local steps = ns.cdb.sequence.steps or {}
    local maxOff = math.max(0, #steps - STEP_ROWS)
    if (f.stepOffset or 0) > maxOff then f.stepOffset = maxOff end
    for i, row in ipairs(f.stepRows) do
        local idx = i + (f.stepOffset or 0)
        local line = steps[idx]
        row.idx = idx
        if line then
            local spell, mode = L.ParseStep(line)
            row.spell, row.modeKey = spell, mode
            row.num:SetText(idx .. ".")
            if spell then
                local st = ns.Talents.SpellStatus(spell)
                local known = st.state == "known"
                row.status = st
                row.icon:SetTexture(spellIcon(spell) or "Interface\\Icons\\INV_Misc_QuestionMark")
                row.icon:SetDesaturated(not known)
                local warn = (st.state == "talent_notinbuild" or st.state == "talent_due" or st.state == "trainer")
                row.name:SetText(known and spell or (("|cff808080%s|r %s%s|r"):format(spell,
                    warn and "|cffff6040" or "|cffffbf20", L.SpellStatusShort(st))))
                row.mode:SetText(L.StepModeLabel(mode))
                row.mode:Enable()
            else
                row.status = nil
                row.icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
                row.icon:SetDesaturated(false)
                row.name:SetText("|cffaaaaaa" .. line .. "|r")
                row.mode:SetText("Custom")
                row.mode:Disable()
            end
            row:Show()
        else
            row:Hide()
        end
    end
    f.stepCount:SetText(("%d step%s%s"):format(#steps, #steps == 1 and "" or "s",
        #steps > STEP_ROWS and " - scroll for more" or ""))
end

local function buildStepRows(f, x, y)
    local holder = CreateFrame("Frame", nil, f)
    holder:SetPoint("TOPLEFT", x, y)
    holder:SetSize(285, STEP_ROWS * 22)
    holder:EnableMouseWheel(true)
    holder:SetScript("OnMouseWheel", function(_, d)
        f.stepOffset = math.max(0, (f.stepOffset or 0) - d)
        O.RefreshSteps()
    end)
    local bg = holder:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.5)
    f.stepHolder = holder
    f.stepRows = {}
    local function steps() return ns.cdb.sequence.steps end
    for i = 1, STEP_ROWS do
        local row = CreateFrame("Frame", nil, holder)
        row:SetSize(285, 22)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * 22)
        row.num = label(row, ""); row.num:SetPoint("LEFT", 2, 0); row.num:SetWidth(16)
        local pb = CreateFrame("Button", nil, row)
        pb:SetSize(18, 18); pb:SetPoint("LEFT", 18, 0)
        row.icon = pb:CreateTexture(nil, "ARTWORK"); row.icon:SetAllPoints(); row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local hl = pb:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.3)
        row.name = label(row, ""); row.name:SetPoint("LEFT", 40, 0); row.name:SetWidth(108)
        row.name:SetWordWrap(false)
        row.name:SetWidth(108)
        row.mode = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.mode:SetSize(86, 18); row.mode:SetPoint("LEFT", 150, 0)
        local fsm = row.mode:GetFontString(); if fsm then fsm:SetFontObject(GameFontHighlightSmall) end
        local function small(txt, xo, fn, tip)
            local b = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            b:SetSize(16, 18); b:SetPoint("LEFT", xo, 0); b:SetText(txt)
            b:SetScript("OnClick", fn)
            b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(tip); GameTooltip:Show() end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            return b
        end
        small("^", 238, function()
            local s, k = steps(), row.idx
            if k > 1 then s[k], s[k - 1] = s[k - 1], s[k]; rebuildSteps() end
        end, "Move up")
        small("v", 254, function()
            local s, k = steps(), row.idx
            if k < #s then s[k], s[k + 1] = s[k + 1], s[k]; rebuildSteps() end
        end, "Move down")
        small("x", 270, function()
            table.remove(steps(), row.idx); rebuildSteps()
        end, "Remove step")
        pb:SetScript("OnClick", function(self)
            O.OpenPicker(self, "Step " .. row.idx, function(item)
                local mode = L.DefaultStepMode(item.value, ns.IsHelpful(item.value))
                steps()[row.idx] = L.BuildStep(item.value, mode)
                O.picker:Hide()
                rebuildSteps()
            end, true)
        end)
        pb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if row.spell then GameTooltip:AddLine(row.spell) end
            if row.status and row.status.state ~= "known" then
                GameTooltip:AddLine(row.status.text, 1, 0.75, 0.25, true)
            end
            GameTooltip:AddLine("Click to pick a different spell", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        pb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.mode:SetScript("OnClick", function()
            if not row.spell then return end
            steps()[row.idx] = L.BuildStep(row.spell, L.NextStepMode(row.modeKey))
            rebuildSteps()
        end)
        row.mode:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Who the spell goes on - click to change")
            GameTooltip:AddLine("On enemy: your hostile target", 1, 1, 1)
            GameTooltip:AddLine("Enemy, once: once per target (DoTs)", 1, 1, 1)
            GameTooltip:AddLine("On me: always yourself", 1, 1, 1)
            GameTooltip:AddLine("Mouseover/me: friendly under the mouse, else you", 1, 1, 1)
            GameTooltip:Show()
        end)
        row.mode:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.stepRows[i] = row
    end
    local add = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    add:SetSize(90, 18); add:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", 0, -2); add:SetText("+ Add step")
    add:SetScript("OnClick", function(self)
        O.OpenPicker(self, "New step", function(item)
            local s = steps()
            s[#s + 1] = L.BuildStep(item.value, L.DefaultStepMode(item.value, ns.IsHelpful(item.value)))
            f.stepOffset = math.max(0, #s - STEP_ROWS)
            O.picker:Hide()
            rebuildSteps()
        end, true)
    end)
    f.stepAdd = add
    f.stepCount = label(f, ""); f.stepCount:SetPoint("LEFT", add, "RIGHT", 8, 0)
end

local function saveSequence()
    local f = O.frame
    local seq = ns.cdb.sequence
    seq.name = L.Trim(f.seqName:GetText())
    seq.keyPress = L.JoinContinuations(L.ParseLines(f.keyPress:GetText()))
    if f.textMode then seq.steps = L.JoinContinuations(L.ParseLines(f.steps:GetText())) end
    seq.postMacro = L.JoinContinuations(L.ParseLines(f.post:GetText()))
    if InCombatLockdown() then ns.Print("sequence saved - rebuilds when combat ends") end
    ns.Sequence.Build()
    C_Timer.After(0, O.Refresh)
    ns.Print("sequence saved (%d steps)", #seq.steps)
end

local function build()
    local f = CreateFrame("Frame", "SanctumOptionsFrame", UIParent)
    f:SetSize(W, H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "SanctumOptionsFrame")
    local edge = f:CreateTexture(nil, "BACKGROUND", nil, -8); edge:SetAllPoints(); edge:SetColorTexture(0.30, 0.32, 0.38, 1)
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -7); bg:SetPoint("TOPLEFT", 1, -1); bg:SetPoint("BOTTOMRIGHT", -1, 1)
    bg:SetColorTexture(0.067, 0.075, 0.094, 0.97)
    local top = f:CreateTexture(nil, "BORDER"); top:SetPoint("TOPLEFT", 1, -1); top:SetPoint("TOPRIGHT", -1, -1); top:SetHeight(26)
    top:SetColorTexture(0.11, 0.12, 0.155, 1)
    local topLine = f:CreateTexture(nil, "BORDER", nil, 1); topLine:SetHeight(1)
    topLine:SetPoint("TOPLEFT", 1, -27); topLine:SetPoint("TOPRIGHT", -1, -27); topLine:SetColorTexture(0.30, 0.32, 0.38, 1)
    local title = label(f, ("Sanctum %s"):format(ns.version), "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 10, -5)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    -- Click-casting
    local h1 = label(f, "Click-casting - click an icon to pick a spell", "GameFontNormal")
    h1:SetPoint("TOPLEFT", 12, -36)
    f.rows = {}
    for i, slot in ipairs(D.clickSlots) do
        local y = -58 - (i - 1) * 24
        local l = label(f, slot.label); l:SetPoint("TOPLEFT", 12, y - 4); l:SetWidth(86)
        local pb = CreateFrame("Button", nil, f)
        pb:SetSize(20, 20); pb:SetPoint("TOPLEFT", 100, y)
        local icon = pb:CreateTexture(nil, "ARTWORK"); icon:SetAllPoints(); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local phl = pb:CreateTexture(nil, "HIGHLIGHT"); phl:SetAllPoints(); phl:SetColorTexture(1, 1, 1, 0.3)
        local eb = editBox(f, 168); eb:SetPoint("TOPLEFT", 132, y)
        local st = label(f, ""); st:SetPoint("TOPLEFT", 308, y - 4); st:SetWidth(150)
        local row = { slot = slot, edit = eb, status = st, icon = icon }
        row.pick = function(item, shift)
            local cur = L.Trim(ns.cdb.bindings[slot.key] or "")
            local v = item.value
            if shift and item.spell and cur ~= "" and cur:sub(1, 1) ~= "@" then v = cur .. "|" .. v end
            eb:SetText(v)
            saveBinding(row)
            if not shift and O.picker then O.picker:Hide() end
        end
        pb:SetScript("OnClick", function(self) O.OpenPicker(self, slot.label, row.pick) end)
        pb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(slot.label)
            GameTooltip:AddLine("Click to pick a spell from your spellbook.", 1, 1, 1)
            GameTooltip:AddLine("Text box: A|B|C = first known spell wins,", 0.7, 0.7, 0.7)
            GameTooltip:AddLine("so bindings upgrade as you level.", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        pb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        eb:SetScript("OnEditFocusLost", function() saveBinding(row) end)
        f.rows[i] = row
    end

    -- Display toggles
    local y0 = -58 - #D.clickSlots * 24 - 10
    local h2 = label(f, "Display", "GameFontNormal"); h2:SetPoint("TOPLEFT", 12, y0)
    local fdb, gdb = ns.db.frames, ns.db.goals
    local function relayout() ns.RunOOC("layout", function() ns.Frames.Layout(); ns.Frames.UpdateAll() end) end
    local opts = {
        { "Lock frames", function() return fdb.locked end, function(v) ns.Frames.SetLocked(v) end },
        { "Class colours", function() return fdb.classColours end, function(v) fdb.classColours = v; ns.Frames.UpdateAll() end },
        { "Mana bars", function() return fdb.showMana end, function(v) fdb.showMana = v; relayout() end },
        { "Me at top", function() return fdb.showSelfFirst end, function(v) fdb.showSelfFirst = v; relayout() end },
        { "Goals panel", function() return gdb.shown end, function(v) ns.Goals.SetShown(v) end },
        { "Goals: problems only", function() return gdb.onlyProblems end, function(v) gdb.onlyProblems = v; ns.Goals.Refresh() end },
        { "Minimap icon", function() return ns.db.minimap.shown end, function() ns.Minimap.Toggle() end },
        { "Test mode (fake party)", function() return ns.Frames.test end, function() ns.Frames.ToggleTest() end },
    }
    for i, o in ipairs(opts) do
        local col, rowN = (i - 1) % 3, math.floor((i - 1) / 3)
        local cb = checkbox(f, o[1], o[2], o[3])
        f.checks = f.checks or {}
        f.checks[#f.checks + 1] = { cb = cb, get = o[2] }
        cb:SetPoint("TOPLEFT", 12 + col * 150, y0 - 18 - rowN * 24)
    end
    local el = label(f, "Flag missing enchants from level:"); el:SetPoint("TOPLEFT", 14, y0 - 98)
    local enchLvl = editBox(f, 36); enchLvl:SetPoint("LEFT", el, "RIGHT", 10, 0); enchLvl:SetNumeric(true)
    enchLvl:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    enchLvl:SetScript("OnEditFocusLost", function(self)
        local n = tonumber(self:GetText()); if n then gdb.enchantFromLevel = n; ns.Goals.Refresh() end
    end)
    f.enchLvl = enchLvl
    local en = label(f, "|cff999999Missing enchants are flagged from this level with the best healer enchant for it. Slots with nothing worth enchanting yet (gloves before 60) are skipped.|r")
    en:SetPoint("TOPLEFT", el, "BOTTOMLEFT", 0, -6); en:SetWidth(420); en:SetJustifyH("LEFT")

    -- Sequence editor
    local x = 480
    local h3 = label(f, "Sequence button (GSE-style)", "GameFontNormal"); h3:SetPoint("TOPLEFT", x, -36)
    local nl = label(f, "Name"); nl:SetPoint("TOPLEFT", x, -62)
    f.seqName = editBox(f, 230); f.seqName:SetPoint("TOPLEFT", x + 50, -58)
    local kl = label(f, "KeyPress - runs every press"); kl:SetPoint("TOPLEFT", x, -88)
    local kp, kph = multiBox(f, 285, 56); kph:SetPoint("TOPLEFT", x, -102); f.keyPress = kp
    local sl = label(f, "Steps"); sl:SetPoint("TOPLEFT", x, -166)
    -- Mode: In turn (one step per press, GSE sequential) or Priority (first usable step fires).
    local modeB = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    modeB:SetSize(120, 18); modeB:SetPoint("LEFT", sl, "RIGHT", 8, 0)
    local function modeText()
        return ns.cdb.sequence.mode == "priority" and "Mode: Priority" or "Mode: In turn"
    end
    modeB:SetScript("OnShow", function(self) self:SetText(modeText()) end)
    modeB:SetScript("OnClick", function(self)
        local seq = ns.cdb.sequence
        seq.mode = (seq.mode == "priority") and "sequential" or "priority"
        self:SetText(modeText())
        ns.Sequence.Build()
        O.Refresh()
        ns.Print("sequence mode: %s", seq.mode == "priority" and "Priority - each press casts the first usable step, top to bottom"
            or "In turn - each press moves on one step")
    end)
    modeB:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Sequence mode")
        GameTooltip:AddLine("In turn: each press runs the next step (GSE style).", 1, 1, 1, true)
        GameTooltip:AddLine("Steps that are on cooldown are skipped past.", 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("Priority: each press tries the steps top to bottom and casts the first one that's usable. Best for spamming a key.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    modeB:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.modeButton = modeB
    buildStepRows(f, x, -180)
    -- Advanced: the raw text editor, swapped in by the "Edit as text" box.
    local st, sth = multiBox(f, 285, 170); sth:SetPoint("TOPLEFT", x, -180); f.steps = st
    sth:Hide(); f.stepsText = sth
    local tm = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    tm:SetSize(18, 18); tm:SetPoint("TOPLEFT", x + 185, -162)
    local tml = label(tm, "Edit as text"); tml:SetPoint("LEFT", tm, "RIGHT", 1, 0)
    tm:SetScript("OnClick", function(self)
        f.textMode = self:GetChecked() and true or false
        f.stepsText:SetShown(f.textMode)
        f.stepHolder:SetShown(not f.textMode)
        f.stepAdd:SetShown(not f.textMode); f.stepCount:SetShown(not f.textMode)
        if f.textMode then
            f.steps:SetText(table.concat(ns.cdb.sequence.steps or {}, "\n"))
        else
            O.RefreshSteps()
        end
    end)
    local pl = label(f, "PostMacro - runs after each step"); pl:SetPoint("TOPLEFT", x, -358)
    local pm, pmh = multiBox(f, 285, 44); pmh:SetPoint("TOPLEFT", x, -372); f.post = pm
    local save = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    save:SetSize(130, 22); save:SetPoint("TOPLEFT", x, -426); save:SetText("Save sequence")
    save:SetScript("OnClick", saveSequence)
    local rst = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    rst:SetSize(130, 22); rst:SetPoint("LEFT", save, "RIGHT", 10, 0); rst:SetText("Build default")
    rst:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Load the sequence for your talent build")
        local b = ns.Talents.CurrentBuild()
        if b then GameTooltip:AddLine(b.label, 1, 1, 1) end
        GameTooltip:AddLine("Change build in the talent planner.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    rst:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rst:SetScript("OnClick", function()
        ns.cdb.sequence = ns.Talents.DefaultSequence() or ns.Copy(D.defaultSequences[ns.class] or D.defaultSequences.DEFAULT)
        f.stepOffset = 0
        ns.Sequence.Build()
        f.seqName:ClearFocus(); f.keyPress:ClearFocus(); f.steps:ClearFocus(); f.post:ClearFocus()
        O.Refresh()
    end)
    f.seqInfo = label(f, ""); f.seqInfo:SetPoint("TOPLEFT", x, -456)
    local tip = label(f, "|cff999999Or use a macro: /click SanctumSeqButton|r"); tip:SetPoint("TOPLEFT", x, -490)
    f.seqInfo:SetWidth(285)

    -- Key binding for the sequence: click, then press the key you want.
    local setKey = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    setKey:SetSize(170, 22); setKey:SetPoint("TOPLEFT", x, -508); setKey:SetText("Set sequence key")
    local clearKey = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clearKey:SetSize(90, 22); clearKey:SetPoint("LEFT", setKey, "RIGHT", 8, 0); clearKey:SetText("Clear key")
    clearKey:SetScript("OnClick", function() ns.Sequence.Bind(nil) end)
    local function stopCapture()
        setKey.capturing = false
        setKey:EnableKeyboard(false)
        setKey:SetScript("OnKeyDown", nil)
        setKey:SetText("Set sequence key")
    end
    setKey:SetScript("OnClick", function(self)
        if InCombatLockdown() then ns.Print("can't change bindings in combat"); return end
        if self.capturing then stopCapture(); return end
        self.capturing = true
        self:SetText("|cffffff00Press a key (Esc cancels)|r")
        self:EnableKeyboard(true)
        if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
        self:SetScript("OnKeyDown", function(_, key)
            local k = L.KeyFromInput(key, IsAltKeyDown(), IsControlKeyDown(), IsShiftKeyDown())
            if not k then return end
            stopCapture()
            if k ~= "cancel" then ns.Sequence.Bind(k) end
        end)
    end)
    setKey:SetScript("OnHide", stopCapture)
    setKey:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Bind the sequence to a key")
        GameTooltip:AddLine("Click, then press the key (modifiers allowed).", 1, 1, 1)
        GameTooltip:AddLine("This overrides whatever that key normally does,", 1, 1, 1)
        GameTooltip:AddLine("e.g. binding 1 replaces action bar slot 1.", 1, 1, 1)
        GameTooltip:Show()
    end)
    setKey:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local tal = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    tal:SetSize(150, 22); tal:SetPoint("BOTTOMLEFT", 12, 12); tal:SetText("Talent planner")
    tal:SetScript("OnClick", function() ns.Talents.Toggle() end)
    local logB = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    logB:SetSize(110, 22); logB:SetPoint("LEFT", tal, "RIGHT", 8, 0); logB:SetText("Cast log")
    logB:SetScript("OnClick", function() ns.Sequence.ToggleLog() end)
    local bwB = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    bwB:SetSize(120, 22); bwB:SetPoint("LEFT", logB, "RIGHT", 8, 0); bwB:SetText("Buff watch")
    bwB:SetScript("OnClick", function(self) ns.BuffWatch.ToggleMenu(self) end)
    bwB:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Buff watch")
        GameTooltip:AddLine("Pick self buffs to show above your own bar.", 1, 1, 1)
        GameTooltip:AddLine("An icon flashes when its buff is missing or falls off.", 1, 1, 1)
        GameTooltip:Show()
    end)
    bwB:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.buffWatchButton = bwB

    f:SetScript("OnShow", O.Refresh)
    f:SetScript("OnHide", function()
        if O.picker then O.picker:Hide() end
    end)
    f:Hide()
    O.frame = f
end

-- Entry in Esc > Options > AddOns with a button that opens the main window.
function O.RegisterSettings()
    local panel = CreateFrame("Frame")
    panel.name = "Sanctum"
    local t = label(panel, "Sanctum " .. ns.version, "GameFontNormalLarge"); t:SetPoint("TOPLEFT", 16, -16)
    local d = label(panel, "Healer frames, click-casting, sequence button and level goals.")
    d:SetPoint("TOPLEFT", 16, -42)
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(200, 26); b:SetPoint("TOPLEFT", 16, -66); b:SetText("Open Sanctum options")
    b:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel:IsShown() then pcall(HideUIPanel, SettingsPanel) end
        if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then pcall(HideUIPanel, InterfaceOptionsFrame) end
        if GameMenuFrame and GameMenuFrame:IsShown() then pcall(HideUIPanel, GameMenuFrame) end
        if not (O.frame and O.frame:IsShown()) then O.Toggle() end
    end)
    local ok = false
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        ok = pcall(function()
            local cat = Settings.RegisterCanvasLayoutCategory(panel, "Sanctum")
            Settings.RegisterAddOnCategory(cat)
        end)
    end
    if not ok and InterfaceOptions_AddCategory then pcall(InterfaceOptions_AddCategory, panel) end
end

function O.Toggle()
    if not O.frame then build() end
    O.frame:SetShown(not O.frame:IsShown())
end

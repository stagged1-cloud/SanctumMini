-- Sanctum / Sequence.lua
-- GSE-style stepping macro button. Each press runs KeyPress lines + the next
-- step + PostMacro lines. Stepping happens in a secure WrapScript snippet, so
-- it works in combat; step text is (re)built only out of combat.
--
-- Use it by binding a key (/sanc bind F) or with a macro:  /click SanctumSeqButton

local ADDON, ns = ...
local S = {}
ns.Sequence = S
local L = ns.Logic

local STEP_SNIPPET = [[
    local n = self:GetAttribute("sanc-n") or 0
    if n == 0 then return end
    local s = self:GetAttribute("sanc-step") or 1
    if s > n then s = 1 end
    self:SetAttribute("macrotext", self:GetAttribute("sanc-m" .. s))
    self:SetAttribute("sanc-step", (s % n) + 1)
    self:CallMethod("SanctumOnStep", s)
]]

function S.Build()
    if InCombatLockdown() then return ns.RunOOC("sequence", S.Build) end
    local b = S.button
    local old = b:GetAttribute("sanc-n") or 0
    for i = 1, old do b:SetAttribute("sanc-m" .. i, nil) end
    -- Lines using spells you haven't learned are left out until you learn them.
    local filtered, waiting = L.FilterSequence(ns.cdb.sequence, ns.IsKnown)
    if S.waiting then
        local still = {}
        for _, n in ipairs(waiting) do still[n] = true end
        for _, n in ipairs(S.waiting) do
            if not still[n] then ns.Print("sequence: |cff40ff40%s is now active|r", n) end
        end
    end
    S.waiting = waiting
    local priority = ns.cdb.sequence.mode == "priority"
    local macros, errors
    if priority then macros, errors = L.BuildPriorityMacro(filtered)
    else macros, errors = L.BuildSequenceMacros(filtered) end
    -- What each active step casts, for the cast log.
    S.stepLabels = {}
    for i, line in ipairs(filtered.steps) do
        local names = L.SpellsInMacroLine(line)
        S.stepLabels[i] = #names > 0 and table.concat(names, "/") or line
    end
    if priority then S.stepLabels = { "priority (first usable)" } end
    for i, m in ipairs(macros) do b:SetAttribute("sanc-m" .. i, m) end
    b:SetAttribute("sanc-n", #macros)
    b:SetAttribute("sanc-step", 1)
    b:SetAttribute("macrotext", macros[1] or "")
    S.count, S.errors = #macros, errors
    for _, e in ipairs(errors) do ns.Print("sequence: %s", e) end
end

function S.ResetStep()
    if not InCombatLockdown() and S.button then S.button:SetAttribute("sanc-step", 1) end
end

-- The sequence button is pinned to the key-UP edge regardless of the
-- ActionButtonUseKeyDown CVar (same approach as GSE), so one press = one step.
function S.SyncClickEdge() end

function S.ApplyKeyBinding()
    if InCombatLockdown() then return ns.RunOOC("seqbind", S.ApplyKeyBinding) end
    ClearOverrideBindings(S.owner)
    local key = ns.cdb.seqKey
    if key and key ~= "" then
        SetOverrideBindingClick(S.owner, true, key, "SanctumSeqButton", "LeftButton")
    end
end

function S.Bind(key)
    if InCombatLockdown() then ns.Print("can't change bindings in combat"); return end
    key = key and L.Trim(key):upper() or ""
    ns.cdb.seqKey = key ~= "" and key or nil
    S.ApplyKeyBinding()
    if ns.cdb.seqKey then ns.Print("sequence bound to %s", ns.cdb.seqKey)
    else ns.Print("sequence key unbound") end
    if ns.Options and ns.Options.Refresh then ns.Options.Refresh() end
end

function S.Report()
    local seq = ns.cdb.sequence
    ns.Print("sequence '%s': %d steps active, key %s, next step %s", seq.name or "?", S.count or 0,
        ns.cdb.seqKey or "none", tostring(S.button and S.button:GetAttribute("sanc-step")))
    if S.waiting and #S.waiting > 0 then
        ns.Print("  waiting to learn: %s", table.concat(S.waiting, ", "))
    end
end

function S.Init()
    -- nil parent (as GSE does) so hiding the UI with Alt+Z never stops the button.
    local b = CreateFrame("Button", "SanctumSeqButton", nil, "SecureActionButtonTemplate,SecureHandlerBaseTemplate")
    b:SetAttribute("type", "macro")
    b:SetAttribute("useOnKeyDown", false)
    b:RegisterForClicks("AnyUp")
    b:WrapScript(b, "OnClick", STEP_SNIPPET)
    S.button = b
    S.owner = CreateFrame("Frame", "SanctumBindingOwner", UIParent)
    S.Build()
    S.ApplyKeyBinding()
    -- Reset only when combat ends. (Resetting on target change made the first
    -- press repeat step 1, because /targetenemy itself changes your target.)
    ns.On("PLAYER_REGEN_ENABLED", S.ResetStep)
    b.SanctumOnStep = function(_, s) S.OnStep(s) end
    S.InitLog()
end

---------------------------------------------------------------------------
-- Cast log: every sequence press, every cast you make, and why casts failed.
-- Saved per character (SanctumCharDB.seqLog) so it survives logout.
---------------------------------------------------------------------------
local LOG_MAX = 300   -- ~10s of hard key-spam, or many minutes of normal play
local lastPress = 0

-- Wall clock with tenths, built from one source so times never run backwards.
local clockBase
local function now()
    local t = GetTime()
    clockBase = clockBase or (time() - t)
    local c = clockBase + t
    -- Truncate (not round) the tenths: rounding .95 gave ".0" on the old second.
    return date("%H:%M:%S", math.floor(c)) .. "." .. math.floor((c % 1) * 10)
end

local function spellName(id)
    if not id then return "?" end
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, id); if ok and n then return n end
    end
    if GetSpellInfo then local ok, n = pcall(GetSpellInfo, id); if ok and n then return n end end
    return tostring(id)
end

local function push(entry)
    ns.cdb.seqLog = ns.cdb.seqLog or {}
    entry.time = now()
    L.LogPush(ns.cdb.seqLog, entry, LOG_MAX)
    if S.logFrame and S.logFrame:IsShown() then S.RefreshLog() end
end

function S.OnStep(step)
    lastPress = GetTime()
    push({ kind = "press", step = step, spell = S.stepLabels and S.stepLabels[step] or "?" })
end

function S.InitLog()
    local issecret = issecretvalue or function() return false end
    ns.On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
        if unit ~= "player" or issecret(spellID) then return end
        push({ kind = "cast", spell = spellName(spellID) })
    end)
    ns.On("UNIT_SPELLCAST_FAILED", function(_, unit, _, spellID)
        if unit ~= "player" or issecret(spellID) then return end
        push({ kind = "fail", spell = spellName(spellID) })
    end)
    ns.On("UNIT_SPELLCAST_INTERRUPTED", function(_, unit, _, spellID)
        if unit ~= "player" or issecret(spellID) then return end
        push({ kind = "fail", spell = spellName(spellID), reason = "interrupted" })
    end)
    ns.On("UI_ERROR_MESSAGE", function(_, _, msg)
        if GetTime() - lastPress > 1 or issecret(msg) then return end
        push({ kind = "error", reason = tostring(msg) })
    end)
end

local COL = { press = "|cff9999ff", cast = "|cff40ff40", fail = "|cffff4040", error = "|cffffbf20" }
local LOG_LINES = 30

function S.RefreshLog()
    local f = S.logFrame
    local log = ns.cdb.seqLog or {}
    local lines = L.LogLines(log, LOG_LINES)
    for i = 1, LOG_LINES do
        local fs = f.lines[i]
        local e = lines[i]
        if e then
            local text
            if e.kind == "press" then text = ("press  step %d  %s"):format(e.step or 0, e.spell or "?")
            elseif e.kind == "cast" then text = ("CAST   %s%s"):format(e.spell or "?", (e.count or 1) > 1 and (" x" .. e.count) or "")
            elseif e.kind == "fail" then text = ("FAIL   %s%s"):format(e.spell or "?", e.reason and (" - " .. e.reason) or "")
            else text = "error  " .. (e.reason or "") end
            fs:SetText(("|cff808080%s|r  %s%s|r"):format(e.time or "", COL[e.kind] or "", text))
            fs:Show()
        else
            fs:Hide()
        end
    end
end

function S.ToggleLog()
    if not S.logFrame then
        local f = CreateFrame("Frame", "SanctumCastLog", UIParent)
        f:SetSize(420, 70 + LOG_LINES * 14)
        f:SetPoint("CENTER", 250, 0)
        f:SetFrameStrata("FULLSCREEN")
        f:SetToplevel(true)
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:SetClampedToScreen(true)
        tinsert(UISpecialFrames, "SanctumCastLog")
        local edge = f:CreateTexture(nil, "BACKGROUND", nil, -1); edge:SetPoint("TOPLEFT", -1, 1); edge:SetPoint("BOTTOMRIGHT", 1, -1)
        edge:SetColorTexture(0.2, 0.5, 0.8, 1)
        local bg = f:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.08, 1)
        local top = f:CreateTexture(nil, "BORDER"); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(24)
        top:SetColorTexture(0.1, 0.3, 0.5, 1)
        local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); t:SetPoint("TOPLEFT", 10, -5)
        t:SetText("Sanctum - sequence cast log (newest first)")
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", 2, 2)
        f.lines = {}
        for i = 1, LOG_LINES do
            local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("TOPLEFT", 10, -30 - (i - 1) * 14)
            fs:SetJustifyH("LEFT")
            f.lines[i] = fs
        end
        local clear = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        clear:SetSize(90, 22); clear:SetPoint("BOTTOMLEFT", 10, 10); clear:SetText("Clear log")
        clear:SetScript("OnClick", function() ns.cdb.seqLog = {}; S.RefreshLog() end)
        local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("LEFT", clear, "RIGHT", 10, 0)
        hint:SetText("|cff999999Saved on logout to SavedVariables.|r")
        f:SetScript("OnShow", function(self) self:Raise(); S.RefreshLog() end)
        f:Hide()
        S.logFrame = f
    end
    S.logFrame:SetShown(not S.logFrame:IsShown())
end

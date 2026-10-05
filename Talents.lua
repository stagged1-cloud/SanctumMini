-- Sanctum / Talents.lua
-- Talent planner: pick a build, see what you should have by your level,
-- what you actually have (when the client exposes talents), and what's next.
-- Prints the next point on every level-up.

local ADDON, ns = ...
local T = ns.Talents or {}
ns.Talents = T
local L = ns.Logic

local COLOURS = {
    done    = "|cff40ff40",
    partial = "|cffffbf20",
    missing = "|cffff4040",
    future  = "|cff808080",
}
local TREE_TAG = { "|cffb0b0ffD|r", "|cffffffa0H|r", "|cffc080ffS|r" }
local MAX_ROWS = 28

local function classData() return ns.TalentData and ns.TalentData[ns.class] end

function T.CurrentBuild()
    local cd = classData()
    if not cd then return nil end
    local key = ns.cdb.talentBuild or cd.defaultBuild
    for i, b in ipairs(cd.builds) do if b.key == key then return b, i end end
    return cd.builds[1], 1
end

-- Reads your spent ranks: { [abbr] = rank }, or nil if the API isn't there.
-- Reads your spent ranks: { [abbr] = rank }, or nil if the client exposes none.
-- Tries the classic talent API, then the modern C_Traits system.
T.readMethod = "none"
local function readLegacy(byName)
    if not (GetNumTalentTabs and GetNumTalents and GetTalentInfo) then return nil end
    local actual, any = {}, false
    local ok = pcall(function()
        for tab = 1, GetNumTalentTabs() do
            for i = 1, GetNumTalents(tab) do
                local name, _, _, _, rank = GetTalentInfo(tab, i)
                if name then
                    any = true
                    local abbr = byName[name]
                    if abbr and rank and rank > 0 then actual[abbr] = rank end
                end
            end
        end
    end)
    if ok and any then return actual end
end

local function spellName(id)
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, id); if ok and n then return n end
    end
    if GetSpellInfo then local ok, n = pcall(GetSpellInfo, id); if ok then return n end end
end

local function readTraits(byName)
    if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits) then return nil end
    local actual, any = {}, false
    local ok = pcall(function()
        local configID = C_ClassTalents.GetActiveConfigID()
        if not configID then return end
        local cfg = C_Traits.GetConfigInfo(configID)
        for _, treeID in ipairs((cfg and cfg.treeIDs) or {}) do
            for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
                local node = C_Traits.GetNodeInfo(configID, nodeID)
                if node then
                    any = true
                    if node.activeEntry and (node.activeRank or 0) > 0 then
                        local entry = C_Traits.GetEntryInfo(configID, node.activeEntry.entryID)
                        local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
                        local name = def and (def.overrideName or (def.spellID and spellName(def.spellID)))
                        local abbr = name and byName[name]
                        if abbr then actual[abbr] = node.activeRank end
                    end
                end
            end
        end
    end)
    if ok and any then return actual end
end

function T.ReadActual()
    local cd = classData()
    if not cd then return nil end
    local byName = {}
    for abbr, t in pairs(cd.talents) do byName[t.name] = abbr end
    local a = readLegacy(byName)
    if a then T.readMethod = "GetTalentInfo"; return a end
    a = readTraits(byName)
    if a then T.readMethod = "C_Traits"; return a end
    T.readMethod = "none"
    return nil
end

-- Why a spell isn't usable yet, in plain words (see Logic.SpellStatus).
function T.SpellStatus(spell)
    local cd = classData()
    local build = T.CurrentBuild()
    local ctx = { level = UnitLevel("player"), isKnown = ns.IsKnown, trainer = cd and cd.trainer or {},
                  activeTalents = {}, talents = cd and cd.talents or {},
                  points = build and L.ExpandBuild(build.order) or {}, buildLabel = build and build.label }
    for _, a in ipairs((cd and cd.activeTalents) or {}) do ctx.activeTalents[cd.talents[a].name] = a end
    return L.SpellStatus(spell, ctx)
end

-- The sequence that suits your chosen build (talent spells it never takes are left out).
function T.DefaultSequence()
    local cd = classData()
    local build = T.CurrentBuild()
    if not cd or not build or not cd.sequences then return nil end
    local tpl = cd.sequences[cd.buildSequence[build.key] or "holy"]
    if not tpl then return nil end
    local active = {}
    for _, a in ipairs(cd.activeTalents or {}) do active[cd.talents[a].name] = a end
    return L.SequenceFromTemplate(tpl, L.ExpandBuild(build.order), active)
end

-- Chat notices: talents off-plan, and sequence spells that need action. Once per session per message.
local told = {}
local function tell(key, fmt, ...)
    if told[key] then return end
    told[key] = true
    ns.Print(fmt, ...)
end

function T.ResetNotices() told = {} end

function T.CheckAndNotify()
    local plan, build, cd = T.Plan()
    if plan and plan.offPlan then
        local missing = {}
        for _, r in ipairs(plan.rows) do
            if r.status == "missing" or r.status == "partial" then
                missing[#missing + 1] = ("%s %d/%d"):format(cd.talents[r.abbr].name, r.actual or 0, r.planned)
            end
        end
        if #missing > 0 then
            tell("miss" .. table.concat(missing), "|cffffbf20talents don't match %s|r - you should have: %s. Open /sanc talents",
                build.label, table.concat(missing, ", "))
        end
        if #plan.offPlan > 0 then
            local names = {}
            for _, a in ipairs(plan.offPlan) do names[#names + 1] = cd.talents[a].name end
            tell("off" .. table.concat(names), "|cffffbf20points outside your build:|r %s - respec at a class trainer to follow %s",
                table.concat(names, ", "), build.label)
        end
    end
    for _, spell in ipairs((ns.Sequence and ns.Sequence.waiting) or {}) do
        local st = T.SpellStatus(spell)
        if st.state == "trainer" or st.state == "talent_due" or st.state == "talent_notinbuild" then
            tell(spell .. st.state, "sequence: |cffffbf20%s|r", st.text)
        end
    end
end

function T.Plan()
    local cd = classData()
    local build = T.CurrentBuild()
    if not build then return nil end
    local pts = L.ExpandBuild(build.order)
    return L.TalentPlan(pts, UnitLevel("player"), T.ReadActual(), 10), build, cd
end

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------
local function fs(parent, template)
    local f = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    f:SetJustifyH("LEFT")
    return f
end

function T.Refresh()
    local f = T.frame
    if not f or not f:IsShown() then return end
    local plan, build, cd = T.Plan()
    for _, r in ipairs(f.rows) do r:Hide() end
    if not plan then
        f.title:SetText("Talent planner")
        f.source:SetText("The talent planner covers the healing classes: Priest, Druid, Paladin and Shaman.")
        f.summary:SetText(""); f.footer:SetText("")
        return
    end
    f.title:SetText(("%s  |cffaaaaaa%s|r"):format(build.label, build.split))
    f.source:SetText("|cff999999Source: " .. build.source .. "|r")
    local level = UnitLevel("player")
    local s
    if level < 10 then
        s = "Talents start at level 10."
    elseif plan.nextAbbr then
        local t = cd.talents[plan.nextAbbr]
        s = ("Level %d: %d points planned.  Next - level %d: |cffffff00%s %d/%d|r"):format(
            level, plan.pointsNow, plan.nextLevel, t.name, plan.nextRank, t.max)
    else
        s = ("Level %d: build complete (%d points)."):format(level, plan.pointsNow)
    end
    f.summary:SetText(s)

    for i, r in ipairs(plan.rows) do
        if i > MAX_ROWS then break end
        local t = cd.talents[r.abbr]
        local you = r.actual and ("  you %d"):format(r.actual) or ""
        local line = f.rows[i]
        line:SetText(("%s  Lv%-2d  %s%s %d/%d|r%s"):format((cd.treeTags or TREE_TAG)[t.tree], r.firstLevel,
            COLOURS[r.status], t.name, r.planned, r.total, you))
        line:Show()
    end

    local foot
    if plan.offPlan == nil then
        foot = "|cff999999Can't read your talents on this client - showing the plan only.|r"
    elseif #plan.offPlan > 0 then
        local names = {}
        for _, a in ipairs(plan.offPlan) do names[#names + 1] = cd.talents[a] and cd.talents[a].name or a end
        foot = "|cffffbf20Off-plan points: " .. table.concat(names, ", ") .. "|r"
    else
        foot = "|cff40ff40Your talents match this build.|r"
    end
    if build.constructed then foot = foot .. "\n|cff999999Order constructed from the source's finished build.|r" end
    f.footer:SetText(foot)
end

local function cycle(dir)
    local cd = classData()
    if not cd then return end
    local _, idx = T.CurrentBuild()
    idx = ((idx - 1 + dir) % #cd.builds) + 1
    ns.cdb.talentBuild = cd.builds[idx].key
    T.ResetNotices()
    T.Refresh()
    if ns.Options and ns.Options.Refresh then ns.Options.Refresh() end
end

local function build()
    local f = CreateFrame("Frame", "SanctumTalentsFrame", UIParent)
    f:SetSize(400, 150 + MAX_ROWS * 14)
    f:SetPoint("CENTER", 0, 40)
    -- Above the options window (DIALOG) so the two never bleed through each other.
    f:SetFrameStrata("FULLSCREEN")
    f:SetToplevel(true)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "SanctumTalentsFrame")
    local bg = f:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.08, 1)
    local edge = f:CreateTexture(nil, "BACKGROUND", nil, -1); edge:SetPoint("TOPLEFT", -1, 1); edge:SetPoint("BOTTOMRIGHT", 1, -1)
    edge:SetColorTexture(0.2, 0.5, 0.8, 1)
    local top = f:CreateTexture(nil, "BORDER"); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(24)
    top:SetColorTexture(0.1, 0.3, 0.5, 1)
    local hdr = fs(f, "GameFontNormal"); hdr:SetPoint("TOPLEFT", 10, -5); hdr:SetText("Sanctum - Talent planner")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", 2, 2)

    local prev = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    prev:SetSize(26, 20); prev:SetPoint("TOPLEFT", 8, -30); prev:SetText("<")
    prev:SetScript("OnClick", function() cycle(-1) end)
    local nextB = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    nextB:SetSize(26, 20); nextB:SetPoint("TOPRIGHT", -8, -30); nextB:SetText(">")
    nextB:SetScript("OnClick", function() cycle(1) end)
    f.title = fs(f, "GameFontNormal"); f.title:SetPoint("LEFT", prev, "RIGHT", 6, 0); f.title:SetPoint("RIGHT", nextB, "LEFT", -6, 0)
    f.title:SetJustifyH("CENTER")
    f.source = fs(f); f.source:SetPoint("TOPLEFT", 10, -56); f.source:SetWidth(380)
    f.summary = fs(f); f.summary:SetPoint("TOPLEFT", 10, -84); f.summary:SetWidth(380)
    f.rows = {}
    for i = 1, MAX_ROWS do
        local r = fs(f); r:SetPoint("TOPLEFT", 12, -104 - (i - 1) * 14)
        f.rows[i] = r
    end
    f.footer = fs(f); f.footer:SetPoint("BOTTOMLEFT", 10, 10); f.footer:SetWidth(380)
    f:SetScript("OnShow", function(self) self:Raise(); T.Refresh() end)
    f:Hide()
    T.frame = f
end

function T.Toggle()
    if not T.frame then build() end
    T.frame:SetShown(not T.frame:IsShown())
end

function T.Init()
    ns.On("PLAYER_LEVEL_UP", function(_, newLevel)
        local cd = classData()
        local b = T.CurrentBuild()
        if not cd or not b or not newLevel or newLevel < 10 then return end
        local pts = L.ExpandBuild(b.order)
        local idx = newLevel - 9
        local abbr = pts[idx]
        if abbr then
            local rank = 0
            for i = 1, idx do if pts[i] == abbr then rank = rank + 1 end end
            local t = cd.talents[abbr]
            ns.Print("level %d talent point: |cffffff00%s %d/%d|r  (%s)", newLevel, t.name, rank, t.max, b.label)
        end
        C_Timer.After(1, T.Refresh)
        C_Timer.After(3, T.CheckAndNotify)
    end)
    ns.On("CHARACTER_POINTS_CHANGED", function() T.Refresh(); C_Timer.After(1, T.CheckAndNotify) end)
    ns.On("PLAYER_TALENT_UPDATE", function() T.Refresh() end)
    ns.On("PLAYER_ENTERING_WORLD", function() C_Timer.After(5, T.CheckAndNotify) end)
end

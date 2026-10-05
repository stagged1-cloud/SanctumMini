-- Sanctum / Core.lua
-- Namespace, saved variables, API compat shims, event bus, combat queue, slash commands.

local ADDON, ns = ...
ns.version = "0.4.2"
ns.Data = ns.Data or {}
ns.Logic = ns.Logic or {}

local PREFIX = "|cff66ccffSanctum|r: "
function ns.Print(...) print(PREFIX .. string.format(...)) end

---------------------------------------------------------------------------
-- Compat: WoW: Forever runs a modern client on vanilla data. Prefer C_* APIs,
-- fall back to the legacy globals. Everything degrades to nil, never errors.
---------------------------------------------------------------------------
local C = {}
ns.C = C

function C.GetSpellIcon(spell)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spell)
        if ok and info then return info.iconID end
    end
    if GetSpellInfo then
        local ok, _, _, icon = pcall(GetSpellInfo, spell)
        if ok then return icon end
    end
end

function C.GetSpellCooldown(spell)
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, spell)
        if ok and info then return info.startTime, info.duration end
    end
    if GetSpellCooldown then
        local ok, s, d = pcall(GetSpellCooldown, spell)
        if ok then return s, d end
    end
end

function C.IsSpellInRange(spell, unit)
    if C_Spell and C_Spell.IsSpellInRange then
        -- May be a secret boolean: returned untouched, never tested here.
        local ok, r = pcall(C_Spell.IsSpellInRange, spell, unit)
        if ok then return r end
    end
    if IsSpellInRange then
        local ok, r = pcall(IsSpellInRange, spell, unit)
        if ok and r ~= nil then return r == 1 end
    end
    return nil
end

-- Calls fn(auraTable) for each aura; fn returning true stops the loop.
function C.ForEachAura(unit, filter, fn)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        -- Forever blocks reading some auras in combat ("Auras cannot be accessed
        -- when secret"). That raises an error, so each read is protected and the
        -- loop just stops; C.auraBlocked records it for /sanc probe.
        for i = 1, 40 do
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
            if not ok then C.auraBlocked = (C.auraBlocked or 0) + 1; return end
            if not a then return end
            if fn(a) then return end
        end
    elseif UnitAura then
        for i = 1, 40 do
            local name, icon, count, dispelType, duration, expirationTime, source, _, _, spellId = UnitAura(unit, i, filter)
            if not name then return end
            if fn({ name = name, icon = icon, applications = count, dispelName = dispelType, duration = duration,
                    expirationTime = expirationTime, sourceUnit = source, spellId = spellId }) then return end
        end
    end
end

function C.GetItemCount(id)
    if C_Item and C_Item.GetItemCount then
        local ok, n = pcall(C_Item.GetItemCount, id)
        if ok and n then return n end
    end
    if GetItemCount then return GetItemCount(id) or 0 end
    return 0
end

-- returns itemLevel, reqLevel (nil if not cached)
function C.GetItemLevels(item)
    local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not fn then return end
    local ok, _, _, _, ilvl, req = pcall(fn, item)
    if ok then return ilvl, req end
end

function C.NumFreeBagSlots()
    local free = 0
    local numSlots = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
    if not numSlots then return nil end
    for bag = 0, 4 do
        local n, bagType = numSlots(bag)
        if n and (bagType == nil or bagType == 0) then free = free + n end
    end
    return free
end

function C.IncomingHeals(unit)
    if UnitGetIncomingHeals then
        local ok, n = pcall(UnitGetIncomingHeals, unit)
        if ok then return n or 0 end
    end
    return 0
end

-- Known-spell set built from the spellbook (names, highest rank implied).
ns.known, ns.spellList = {}, {}
function C.ScanSpellbook()
    local known, castable = {}, {}
    local function add(name, icon, passive)
        known[name] = true
        if not passive and not castable[name] then castable[name] = icon or true end
    end
    local okModern = false
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and Enum and Enum.SpellBookSpellBank then
        okModern = pcall(function()
            local bank = Enum.SpellBookSpellBank.Player
            for t = 1, C_SpellBook.GetNumSpellBookSkillLines() do
                local line = C_SpellBook.GetSpellBookSkillLineInfo(t)
                if line then
                    for i = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                        local info = C_SpellBook.GetSpellBookItemInfo(i, bank)
                        if info and info.name and info.itemType ~= (Enum.SpellBookItemType and Enum.SpellBookItemType.FutureSpell) then
                            add(info.name, info.iconID, info.isPassive)
                        end
                    end
                end
            end
        end)
        okModern = okModern and next(known) ~= nil
        if not okModern then known, castable = {}, {} end
    end
    if not okModern and GetNumSpellTabs then
        pcall(function()
            for t = 1, GetNumSpellTabs() do
                local _, _, offset, num = GetSpellTabInfo(t)
                for i = offset + 1, offset + num do
                    local name = GetSpellBookItemName(i, BOOKTYPE_SPELL or "spell")
                    local kind = GetSpellBookItemInfo and GetSpellBookItemInfo(i, BOOKTYPE_SPELL or "spell")
                    if name and kind ~= "FUTURESPELL" then
                        local icon = GetSpellBookItemTexture and GetSpellBookItemTexture(i, BOOKTYPE_SPELL or "spell")
                        local passive = IsPassiveSpell and IsPassiveSpell(i, BOOKTYPE_SPELL or "spell")
                        add(name, icon, passive)
                    end
                end
            end
        end)
    end
    ns.known = known
    -- Sorted castable list for the spell picker: { {name=, icon=} }
    local list = {}
    for name, icon in pairs(castable) do list[#list + 1] = { name = name, icon = icon ~= true and icon or nil } end
    table.sort(list, function(a, b) return a.name < b.name end)
    ns.spellList = list
    return known
end

function ns.IsKnown(name) return ns.known[name] == true end

-- Is a spell friendly (heal/buff)? API first, then a fallback list.
local HELPFUL_FALLBACK = {
    ["Power Word: Shield"] = true, ["Power Word: Fortitude"] = true, ["Prayer of Fortitude"] = true,
    ["Inner Fire"] = true, ["Renew"] = true, ["Lesser Heal"] = true, ["Heal"] = true, ["Flash Heal"] = true,
    ["Greater Heal"] = true, ["Prayer of Healing"] = true, ["Fear Ward"] = true, ["Divine Spirit"] = true,
    ["Shadow Protection"] = true, ["Dispel Magic"] = false, ["Cure Disease"] = true, ["Abolish Disease"] = true,
    ["Fade"] = true, ["Desperate Prayer"] = true, ["Divine Grace"] = true, ["Binding Heal"] = true,
    ["Prayer of Mending"] = true, ["Penance"] = false, ["Elune's Grace"] = true, ["Inner Focus"] = true,
    ["Power Infusion"] = true,
}
function ns.IsHelpful(name)
    if HELPFUL_FALLBACK[name] ~= nil then return HELPFUL_FALLBACK[name] end
    if C_Spell and C_Spell.IsSpellHelpful then
        local ok, r = pcall(C_Spell.IsSpellHelpful, name)
        if ok and type(r) == "boolean" then return r end
    end
    if IsHelpfulSpell then
        local ok, r = pcall(IsHelpfulSpell, name)
        if ok and r ~= nil then return r and true or false end
    end
    return false
end

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------
local defaults = {
    frames = { x = -320, y = 60, point = "CENTER", locked = false, scale = 1, width = 130, height = 40,
               spacing = 3, classColours = true, showMana = true, showSelfFirst = true },
    minimap = { shown = true, angle = 200 },
    goals = { shown = true, x = 320, y = 120, point = "CENTER", enchantFromLevel = 40, onlyProblems = false },
}

local function applyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            applyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function copy(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = copy(v) end
    return o
end
ns.Copy = copy

function ns.ClassKit(class)
    return ns.Data.classKits[class] or ns.Data.classKits.DEFAULT
end

local function initDB()
    SanctumDB = SanctumDB or {}
    applyDefaults(SanctumDB, defaults)
    SanctumCharDB = SanctumCharDB or {}
    local _, class = UnitClass("player")
    ns.class = class
    if type(SanctumCharDB.bindings) ~= "table" then SanctumCharDB.bindings = copy(ns.ClassKit(class)) end
    if type(SanctumCharDB.sequence) ~= "table" then
        SanctumCharDB.sequence = copy(ns.Data.defaultSequences[class] or ns.Data.defaultSequences.DEFAULT)
    end
    ns.db, ns.cdb = SanctumDB, SanctumCharDB
end

---------------------------------------------------------------------------
-- Combat queue: protected work requested in combat runs on PLAYER_REGEN_ENABLED.
---------------------------------------------------------------------------
local queue = {}
function ns.RunOOC(key, fn)
    if InCombatLockdown() then
        queue[key] = fn
        return false
    end
    fn()
    return true
end

---------------------------------------------------------------------------
-- Click edge matching ActionButtonUseKeyDown (TMM lesson: wrong edge = dead buttons).
---------------------------------------------------------------------------
function ns.ClickEdge()
    local down = false
    if C_CVar and C_CVar.GetCVarBool then down = C_CVar.GetCVarBool("ActionButtonUseKeyDown")
    elseif GetCVarBool then down = GetCVarBool("ActionButtonUseKeyDown") end
    return down and "AnyDown" or "AnyUp"
end

---------------------------------------------------------------------------
-- Event bus
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ns.handlers = {}
function ns.On(event, fn)
    if not ns.handlers[event] then
        ns.handlers[event] = {}
        pcall(ev.RegisterEvent, ev, event)
    end
    table.insert(ns.handlers[event], fn)
end
ev:SetScript("OnEvent", function(_, event, ...)
    local list = ns.handlers[event]
    if list then for _, fn in ipairs(list) do fn(event, ...) end end
end)

ns.On("PLAYER_REGEN_ENABLED", function()
    for k, fn in pairs(queue) do queue[k] = nil; fn() end
end)

ns.On("ADDON_LOADED", function(_, name)
    if name ~= ADDON then return end
    initDB()
end)

ns.On("PLAYER_LOGIN", function()
    C.ScanSpellbook()
    -- Each module starts in isolation: one failure is reported, the rest still load.
    ns.initErrors = {}
    local function safe(name, fn)
        if not fn then return end
        local ok, err = xpcall(fn, function(e)
            return tostring(e) .. (debugstack and ("\n" .. debugstack(2, 3, 0)) or "")
        end)
        if not ok then
            ns.initErrors[#ns.initErrors + 1] = name .. ": " .. err
            ns.Print("|cffff4040%s failed to start:|r %s", name, err)
        end
    end
    safe("Frames", ns.Frames and ns.Frames.Init)
    safe("Sequence", ns.Sequence and ns.Sequence.Init)
    safe("Goals", ns.Goals and ns.Goals.Init)
    safe("Minimap", ns.Minimap and ns.Minimap.Init)
    safe("Talents", ns.Talents and ns.Talents.Init)
    safe("Settings", ns.Options and ns.Options.RegisterSettings)
    ns.Print("v%s loaded - /sanc for options, /sanc help for commands.", ns.version)
end)

local function onSpellsChanged()
    C.ScanSpellbook()
    if ns.Frames and ns.Frames.ready then ns.RunOOC("bindings", ns.Frames.ApplyBindings) end
    if ns.Sequence and ns.Sequence.button then ns.Sequence.Build() end
    if ns.Goals and ns.Goals.ready then ns.Goals.Refresh() end
    if ns.Options and ns.Options.Refresh then ns.Options.Refresh() end
end
ns.On("SPELLS_CHANGED", onSpellsChanged)
ns.On("LEARNED_SPELL_IN_TAB", onSpellsChanged)

ns.On("CVAR_UPDATE", function(_, name)
    if name and tostring(name):lower() == "actionbuttonusekeydown" then
        ns.RunOOC("clickedge", function()
            if ns.Frames then ns.Frames.SyncClickEdge() end
            if ns.Sequence then ns.Sequence.SyncClickEdge() end
        end)
    end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function probe()
    ns.Print("probe - WOW_PROJECT_ID=%s, interface=%s", tostring(WOW_PROJECT_ID), tostring(select(4, GetBuildInfo())))
    local apis = {
        "C_Spell.GetSpellInfo", "C_Spell.IsSpellInRange", "C_UnitAuras.GetAuraDataByIndex", "UnitAura",
        "C_SpellBook.GetNumSpellBookSkillLines", "GetNumSpellTabs", "UnitGetIncomingHeals",
        "C_Container.GetContainerNumFreeSlots", "UnitThreatSituation", "UnitInRange",
        "issecretvalue", "GetTalentInfo", "GetNumTalentTabs", "C_SpecializationInfo", "C_ClassTalents", "C_Traits",
    }
    for _, path in ipairs(apis) do
        local a, b = path:match("^([^%.]+)%.?(.*)$")
        local v = _G[a]
        if b ~= "" then v = type(v) == "table" and v[b] or nil end
        ns.Print("  %s: %s", path, v and "|cff00ff00yes|r" or "|cffff4040no|r")
    end
    local n = 0; for _ in pairs(ns.known) do n = n + 1 end
    ns.Print("  known spells: %d, click edge: %s", n, ns.ClickEdge())
    ns.Print("  sequence steps built: %s", tostring(ns.Sequence and ns.Sequence.count))
    ns.Print("  auras blocked (secret) this session: %d", C.auraBlocked or 0)
    if ns.Talents and ns.Talents.ReadActual then
        local a = ns.Talents.ReadActual()
        local n = 0; for _ in pairs(a or {}) do n = n + 1 end
        ns.Print("  talents readable via: %s (%d talents with points)", ns.Talents.readMethod or "none", n)
    end
    for _, e in ipairs((ns.Sequence and ns.Sequence.errors) or {}) do ns.Print("  |cffff4040seq:|r %s", e) end
    for _, e in ipairs(ns.initErrors or {}) do ns.Print("  |cffff4040init:|r %s", e) end
    if #(ns.initErrors or {}) == 0 then ns.Print("  init: all modules started") end
end

SLASH_SANCTUM1, SLASH_SANCTUM2 = "/sanc", "/sanctum"
SlashCmdList.SANCTUM = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    if cmd == "" or cmd == "options" or cmd == "config" then
        ns.Options.Toggle()
    elseif cmd == "lock" or cmd == "unlock" then
        ns.Frames.SetLocked(cmd == "lock")
    elseif cmd == "log" then
        ns.Sequence.ToggleLog()
    elseif cmd == "talents" or cmd == "talent" then
        ns.Talents.Toggle()
    elseif cmd == "minimap" then
        ns.Minimap.Toggle()
    elseif cmd == "test" then
        ns.Frames.ToggleTest()
    elseif cmd == "goals" then
        ns.Goals.Toggle()
    elseif cmd == "bind" then
        ns.Sequence.Bind(rest)
    elseif cmd == "unbind" then
        ns.Sequence.Bind(nil)
    elseif cmd == "seq" then
        ns.Sequence.Report()
    elseif cmd == "probe" then
        probe()
    elseif cmd == "reset" then
        ns.RunOOC("reset", function()
            ns.db.frames.point, ns.db.frames.x, ns.db.frames.y = "CENTER", -320, 60
            ns.db.goals.point, ns.db.goals.x, ns.db.goals.y = "CENTER", 320, 120
            ns.Frames.Reposition(); ns.Goals.Reposition()
        end)
        ns.Print("positions reset")
    elseif cmd == "defaults" then
        ns.RunOOC("defaults", function()
            ns.cdb.bindings = copy(ns.ClassKit(ns.class))
            ns.Frames.ApplyBindings()
            if ns.Options.Refresh then ns.Options.Refresh() end
        end)
        ns.Print("click bindings reset to the %s kit", ns.class or "default")
    else
        ns.Print("commands:")
        ns.Print("  /sanc log - sequence cast log")
        ns.Print("  /sanc talents - talent planner   /sanc minimap - show/hide the minimap icon")
        ns.Print("  /sanc - options   /sanc lock|unlock   /sanc test   /sanc goals")
        ns.Print("  /sanc bind <KEY> - bind the sequence button (e.g. /sanc bind F)   /sanc unbind")
        ns.Print("  /sanc seq - sequence status   /sanc defaults - reset click bindings   /sanc reset - positions")
        ns.Print("  /sanc probe - API diagnostic for the Forever client")
    end
end

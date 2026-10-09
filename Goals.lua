-- Sanctum / Goals.lua
-- Per-level goals checklist: gear, enchants, consumables, buffs, reagents.
-- Gathers a snapshot from the client, hands it to Logic.EvaluateGoals, draws the result.

local ADDON, ns = ...
local G = {}
ns.Goals = G
local D, L, C = ns.Data, ns.Logic, ns.C

local COLOURS = {
    [0] = { 0.3, 1.0, 0.3 },   -- ok
    [1] = { 1.0, 0.75, 0.1 },  -- warn
    [2] = { 1.0, 0.25, 0.25 }, -- bad
}
local MAX_LINES = 40
local LINE_H = 13
local MIN_W, MAX_W = 260, 420   -- panel grows to fit its widest line, then wraps

local function enchantedFromLink(link)
    if not link then return false end
    local e = link:match("item:%d+:(%d*)")
    return e ~= nil and e ~= "" and e ~= "0"
end

-- Item IDs the last snapshot asked the client about. GET_ITEM_INFO_RECEIVED only matters for these.
local requested = {}

function G.Snapshot()
    local gd = D.goals
    requested = {}
    local snap = {
        level = UnitLevel("player"),
        inCombat = InCombatLockdown() or UnitAffectingCombat("player"),
        inInstance = select(2, IsInInstance()) == "party" or select(2, IsInInstance()) == "raid",
        enchantFromLevel = ns.db.goals.enchantFromLevel,
        slots = {}, counts = {}, itemReqLevel = {}, buffs = {}, known = ns.known,
        freeSlots = C.NumFreeBagSlots(),
    }
    for _, slot in ipairs(gd.gearSlots) do
        local link = GetInventoryItemLink("player", slot.id)
        if link then
            local linkId = tonumber(link:match("item:(%d+)"))
            if linkId then requested[linkId] = true end
            local ilvl, req = C.GetItemLevels(link)
            local cur, max = GetInventoryItemDurability(slot.id)
            snap.slots[slot.id] = { link = link, itemLevel = ilvl, reqLevel = req, durCur = cur, durMax = max,
                                    enchanted = enchantedFromLink(link), twoHand = C.IsTwoHand(link) }
        else
            snap.slots[slot.id] = { empty = true }
        end
    end
    local function countIds(ids)
        for _, id in ipairs(ids) do
            requested[id] = true
            snap.counts[id] = C.GetItemCount(id)
            local _, req = C.GetItemLevels(id)
            if req then snap.itemReqLevel[id] = req end
        end
    end
    for _, c in ipairs(gd.consumables) do
        local ids = {}
        for _, t in ipairs(c.tiers) do ids[#ids + 1] = t.id end
        countIds(ids)
    end
    for _, r in ipairs(gd.reagents[ns.class] or {}) do countIds(r.ids) end
    local issecret = issecretvalue or function() return false end
    C.ForEachAura("player", "HELPFUL", function(a)
        if not issecret(a.name) then snap.buffs[a.name] = true end
    end)
    local cd = ns.TalentData and ns.TalentData[ns.class]
    if cd and cd.trainer then
        snap.training = { levels = cd.trainer, skip = cd.trainerSkip, quest = cd.trainerQuest,
                          cache = ns.cdb.trainer }
    end
    return snap
end

---------------------------------------------------------------------------
-- Trainer scan: on opening your class trainer, remember every service (including
-- the ones you're too low for, with their level) so the panel can say when a new
-- rank is ready without you having to go and look.
---------------------------------------------------------------------------
local scanning, filterChangedAt = false, -10
-- "used" (already trained) is not needed: anything missing from the cache is not ready.
local FILTERS = { "available", "unavailable" }

function G.ReadTrainer()
    if not GetNumTrainerServices or not GetTrainerServiceInfo then return nil end
    if IsTradeskillTrainer and IsTradeskillTrainer() then return nil end
    -- Only touch a filter the player has switched off, and put it back after.
    local changed = {}
    if GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter then
        for _, t in ipairs(FILTERS) do
            local on = GetTrainerServiceTypeFilter(t)
            if not on or on == 0 then changed[#changed + 1] = t; SetTrainerServiceTypeFilter(t, 1) end
        end
    end
    local services = {}
    for i = 1, GetNumTrainerServices() or 0 do
        local name, rank, state = GetTrainerServiceInfo(i)
        if name then
            services[#services + 1] = {
                name = name, rank = rank, state = state,
                req = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i) or 0,
                cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or 0,
            }
        end
    end
    for _, t in ipairs(changed) do SetTrainerServiceTypeFilter(t, 0) end
    if #changed > 0 then filterChangedAt = GetTime() end
    return services
end

function G.ScanTrainer(event)
    -- Our own filter changes fire TRAINER_UPDATE: ignore those, never a real purchase.
    if scanning or (event == "TRAINER_UPDATE" and GetTime() - filterChangedAt < 1) then return end
    scanning = true
    local ok, services = pcall(G.ReadTrainer)
    scanning = false
    if not ok or not services then return end
    local cd = ns.TalentData and ns.TalentData[ns.class]
    local cache = L.TrainerCacheFrom(services, cd and cd.trainer, ns.known)
    if cache then
        cache.at = UnitLevel("player")
        ns.cdb.trainer = cache
        G.Queue()
    end
end

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------
function G.Draw(sections, overall)
    local f = G.frame
    local onlyProblems = ns.db.goals.onlyProblems
    local n = 0
    local shown = {}
    local function line(text, status, indent)
        n = n + 1
        if n > MAX_LINES then return end
        local fs = f.lines[n]
        fs:SetWidth(0)   -- unwrapped, so its natural width can be measured
        fs:SetText(text)
        local c = COLOURS[status] or COLOURS[0]
        fs:SetTextColor(c[1], c[2], c[3])
        fs:Show()
        shown[#shown + 1] = { fs = fs, x = 8 + (indent and 10 or 0) }
    end
    for _, sec in ipairs(sections) do
        local head = sec.title
        if sec.compact then
            head = ("%s  (%d/%d OK)"):format(sec.title, sec.checked - #sec.items, sec.checked)
        end
        line(head, sec.status, false)
        for _, it in ipairs(sec.items) do
            if not (onlyProblems and it.status == L.OK) then line(it.text, it.status, true) end
        end
    end
    if n == 0 then line("Nothing to check yet.", L.OK, false) end
    for i = n + 1, MAX_LINES do f.lines[i]:Hide() end
    local c = COLOURS[overall]
    f.title:SetText(("Sanctum - level %d goals"):format(UnitLevel("player")))
    f.title:SetTextColor(c[1], c[2], c[3])
    -- Width: fit the widest line (and the title beside the close button), within MIN_W..MAX_W.
    local w = MIN_W
    for _, s in ipairs(shown) do w = math.max(w, s.x + (s.fs:GetStringWidth() or 0) + 10) end
    w = math.max(w, (f.title:GetStringWidth() or 0) + 40)
    w = math.min(math.ceil(w), MAX_W)
    f:SetWidth(w)
    -- Lay lines out top to bottom; anything still too wide wraps and takes the height it needs.
    local y = -24
    for _, s in ipairs(shown) do
        s.fs:ClearAllPoints()
        s.fs:SetWidth(w - s.x - 8)
        s.fs:SetPoint("TOPLEFT", f, "TOPLEFT", s.x, y)
        y = y - math.max(LINE_H, math.ceil(s.fs:GetStringHeight() or LINE_H))
    end
    f:SetHeight(8 - y)
    G.width = w
end

function G.Refresh()
    if not G.ready or not G.frame:IsShown() then return end
    local snap = G.Snapshot()
    local sections, overall = L.EvaluateGoals(snap, D.goals, ns.class)
    G.Draw(sections, overall)
end

-- Bursts of events (auras, item info, bags) collapse into one snapshot. A dirty
-- flag records that a refresh is wanted; a single timer clears it. Nothing runs
-- in combat: the flag stays set and PLAYER_REGEN_ENABLED refreshes once. Events
-- raised synchronously during the refresh itself are ignored. Item info arrives
-- LATER (after the flush), so GET_ITEM_INFO_RECEIVED is handled separately: only
-- for item IDs the scan requested, and at most one retry per ID per scan cycle (a
-- cycle starts with any other refresh trigger), so an item that never resolves
-- cannot keep the panel refreshing.
local QUEUE_DELAY = 0.75
local dirty, timerSet, refreshing = false, false, false
local freshCycle, retried = true, {}

local function flush()
    timerSet = false
    if not dirty or InCombatLockdown() then return end
    dirty = false
    if freshCycle then retried = {}; freshCycle = false end
    refreshing = true
    local ok, err = pcall(G.Refresh)
    refreshing = false
    if not ok then error(err, 0) end
end

local function schedule()
    if timerSet then return end
    timerSet = true
    C_Timer.After(QUEUE_DELAY, flush)
end

function G.Queue()
    if not G.ready or refreshing then return end
    dirty = true
    freshCycle = true
    if InCombatLockdown() then return end
    schedule()
end

-- GET_ITEM_INFO_RECEIVED(itemID, success): retry the scan once per requested item ID per cycle.
function G.OnItemInfo(_, itemID)
    if not G.ready or refreshing then return end
    if not itemID or not requested[itemID] or retried[itemID] then return end
    retried[itemID] = true
    dirty = true
    if InCombatLockdown() then return end
    schedule()
end

-- Combat just ended: refresh once. InCombatLockdown may still read true on the
-- event itself, so the delayed flush (not this call) does the check.
function G.OnCombatEnd()
    if not G.ready then return end
    dirty = true
    freshCycle = true
    schedule()
end

-- Single place that shows or hides the panel, so the saved setting, the panel
-- and the Options checkbox can never disagree.
function G.SetShown(v)
    ns.db.goals.shown = v and true or false
    G.frame:SetShown(ns.db.goals.shown)
    retried = {}                      -- opening the panel starts a new scan cycle
    G.Refresh()
    if ns.Options and ns.Options.Refresh then ns.Options.Refresh() end
end

function G.Toggle()
    G.SetShown(not ns.db.goals.shown)
end

function G.Reposition()
    local db = ns.db.goals
    G.frame:ClearAllPoints()
    G.frame:SetPoint(db.point, UIParent, db.point, db.x, db.y)
end

function G.Init()
    local db = ns.db.goals
    local f = CreateFrame("Frame", "SanctumGoalsFrame", UIParent)
    f:SetSize(260, 60)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, _, x, y = self:GetPoint()
        db.point, db.x, db.y = p, x, y
    end)
    local bg = f:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.6)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 8, -6)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() G.SetShown(false) end)
    f.closeButton = close
    f.lines = {}
    for i = 1, MAX_LINES do
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetJustifyH("LEFT")
        fs:Hide()
        f.lines[i] = fs
    end
    G.frame = f
    G.Reposition()
    f:SetShown(db.shown)
    f:SetScript("OnShow", function() G.Refresh() end)

    for _, e in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP",
                         "UPDATE_INVENTORY_DURABILITY", "PLAYER_REGEN_DISABLED",
                         "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
        ns.On(e, G.Queue)
    end
    ns.On("GET_ITEM_INFO_RECEIVED", G.OnItemInfo)
    ns.On("PLAYER_REGEN_ENABLED", G.OnCombatEnd)
    ns.On("UNIT_AURA", function(_, unit) if unit == "player" then G.Queue() end end)
    ns.On("TRAINER_SHOW", G.ScanTrainer)
    ns.On("TRAINER_UPDATE", G.ScanTrainer)
    G.ready = true
    G.Refresh()
end

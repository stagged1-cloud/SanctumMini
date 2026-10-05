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

local function enchantedFromLink(link)
    if not link then return false end
    local e = link:match("item:%d+:(%d*)")
    return e ~= nil and e ~= "" and e ~= "0"
end

function G.Snapshot()
    local gd = D.goals
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
            local ilvl, req = C.GetItemLevels(link)
            local cur, max = GetInventoryItemDurability(slot.id)
            snap.slots[slot.id] = { link = link, itemLevel = ilvl, reqLevel = req, durCur = cur, durMax = max,
                                    enchanted = enchantedFromLink(link) }
        else
            snap.slots[slot.id] = { empty = true }
        end
    end
    local function countIds(ids)
        for _, id in ipairs(ids) do
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
    return snap
end

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------
function G.Draw(sections, overall)
    local f = G.frame
    local onlyProblems = ns.db.goals.onlyProblems
    local n = 0
    local function line(text, status, indent)
        n = n + 1
        if n > MAX_LINES then return end
        local fs = f.lines[n]
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", f, "TOPLEFT", 8 + (indent and 10 or 0), -24 - (n - 1) * LINE_H)
        fs:SetText(text)
        local c = COLOURS[status] or COLOURS[0]
        fs:SetTextColor(c[1], c[2], c[3])
        fs:Show()
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
    f:SetHeight(32 + math.min(n, MAX_LINES) * LINE_H)
    local c = COLOURS[overall]
    f.title:SetText(("Sanctum - level %d goals"):format(UnitLevel("player")))
    f.title:SetTextColor(c[1], c[2], c[3])
end

function G.Refresh()
    if not G.ready or not G.frame:IsShown() then return end
    local snap = G.Snapshot()
    local sections, overall = L.EvaluateGoals(snap, D.goals, ns.class)
    G.Draw(sections, overall)
end

local pending = false
function G.Queue()
    if pending or not G.ready then return end
    pending = true
    C_Timer.After(0.5, function() pending = false; G.Refresh() end)
end

function G.Toggle()
    ns.db.goals.shown = not ns.db.goals.shown
    G.frame:SetShown(ns.db.goals.shown)
    G.Refresh()
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
    close:SetScript("OnClick", function() G.Toggle() end)
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
                         "UPDATE_INVENTORY_DURABILITY", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
                         "PLAYER_ENTERING_WORLD", "GET_ITEM_INFO_RECEIVED", "ZONE_CHANGED_NEW_AREA" }) do
        ns.On(e, G.Queue)
    end
    ns.On("UNIT_AURA", function(_, unit) if unit == "player" then G.Queue() end end)
    G.ready = true
    G.Refresh()
end

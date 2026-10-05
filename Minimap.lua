-- Sanctum / Minimap.lua
-- Self-contained minimap button (no LibDBIcon dependency).
-- Left-click: options. Right-click: lock/unlock frames. Shift-click: goals panel. Drag: move round the rim.

local ADDON, ns = ...
local M = {}
ns.Minimap = M

local ICON = "Interface\\Icons\\Spell_Holy_HolyBolt"

local function place()
    local b, db = M.button, ns.db.minimap
    local a = math.rad(db.angle or 200)
    local r = (Minimap:GetWidth() / 2) + 5
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function onDragUpdate()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local s = Minimap:GetEffectiveScale()
    px, py = px / s, py / s
    ns.db.minimap.angle = math.deg(math.atan2(py - my, px - mx))
    place()
end

function M.Toggle()
    ns.db.minimap.shown = not ns.db.minimap.shown
    M.button:SetShown(ns.db.minimap.shown)
    ns.Print("minimap icon %s", ns.db.minimap.shown and "shown" or "hidden - /sanc minimap to bring it back")
    if ns.Options and ns.Options.Refresh then ns.Options.Refresh() end
end

function M.Init()
    local b = CreateFrame("Button", "SanctumMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetMovable(true)

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("TOPLEFT", 7, -5)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    icon:SetPoint("TOPLEFT", 7, -6)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    b:SetScript("OnClick", function(_, button)
        if IsControlKeyDown() then
            ns.Talents.Toggle()
        elseif IsShiftKeyDown() then
            ns.Goals.Toggle()
        elseif button == "RightButton" then
            ns.Frames.SetLocked(not ns.db.frames.locked)
        else
            ns.Options.Toggle()
        end
    end)
    b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", onDragUpdate) end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Sanctum " .. ns.version)
        GameTooltip:AddLine("Left-click: options", 1, 1, 1)
        GameTooltip:AddLine(("Right-click: %s frames"):format(ns.db.frames.locked and "unlock" or "lock"), 1, 1, 1)
        GameTooltip:AddLine("Shift-click: goals panel", 1, 1, 1)
        GameTooltip:AddLine("Ctrl-click: talent planner", 1, 1, 1)
        GameTooltip:AddLine("Drag: move this icon", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    M.button = b
    place()
    b:SetShown(ns.db.minimap.shown)
end

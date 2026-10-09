-- luacheck config for SanctumMini (WoW Classic addon, Lua 5.1).
-- How read_globals was built: scanned Core, Data, TalentData, Logic, Frames,
-- Sequence, Goals, BuffWatch, Minimap, Talents and Options for identifiers that
-- are not local, not table keys and not Lua 5.1 stdlib, then kept the ones that
-- are WoW API functions, frames, constants or Blizzard-provided tables. It was
-- built by grep, not by running luacheck: expect to add the odd name the first
-- time luacheck runs in CI ("accessing undefined variable X").
std = "lua51"
max_line_length = false
-- Noise reduction: unused args (212), unused loop vars (213), and
-- shadowing of upvalues (431) / of values (432) are common in WoW event code.
unused_args = false
ignore = { "212", "213", "431", "432" }
exclude_files = { "tests/" }

-- Globals this addon creates or writes to.
globals = {
    "SanctumDB",
    "SanctumCharDB",
    "SlashCmdList",
    "SLASH_SANCTUM1",
    "SLASH_SANCTUM2",
    "UISpecialFrames",
}

read_globals = {
    -- Lua / WoW stdlib helpers not in lua51 std
    "date", "time", "debugstack", "issecretvalue",
    "strsplit", "strtrim", "tinsert", "tremove", "wipe",

    -- Namespaced APIs
    "C_AddOns", "C_CVar", "C_ClassTalents", "C_Container", "C_Item",
    "C_Spell", "C_SpellBook", "C_Timer", "C_Traits", "C_UnitAuras",
    "Enum", "Settings",

    -- Frames and fonts
    "UIParent", "Minimap", "GameTooltip", "GameMenuFrame", "SettingsPanel",
    "InterfaceOptionsFrame", "ChatFontNormal", "GameFontHighlightSmall",

    -- Constants and Blizzard tables
    "BOOKTYPE_SPELL", "WOW_PROJECT_ID", "RAID_CLASS_COLORS", "CUSTOM_CLASS_COLORS",

    -- Frame / UI functions
    "CreateFrame", "GameTooltip_SetDefaultAnchor", "HideUIPanel",
    "InterfaceOptions_AddCategory", "PlaySound", "PlaySoundFile",
    "RegisterUnitWatch", "UnregisterUnitWatch",
    "SetOverrideBindingClick", "ClearOverrideBindings",
    "GetCursorPosition", "IsAltKeyDown", "IsControlKeyDown", "IsShiftKeyDown",

    -- Game state / info
    "GetAddOnMetadata", "GetBuildInfo", "GetCVarBool", "GetTime",
    "InCombatLockdown", "IsInInstance",

    -- Items / inventory / bags
    "GetContainerNumFreeSlots", "GetInventoryItemDurability",
    "GetInventoryItemLink", "GetItemCount", "GetItemInfo", "GetItemInfoInstant",
    "GetWeaponEnchantInfo",

    -- Spells / spellbook / talents / trainer
    "GetNumSpellTabs", "GetSpellTabInfo", "GetSpellBookItemInfo",
    "GetSpellBookItemName", "GetSpellBookItemTexture", "GetSpellCooldown",
    "GetSpellInfo", "IsHelpfulSpell", "IsPassiveSpell", "IsSpellInRange",
    "GetNumTalentTabs", "GetNumTalents", "GetTalentInfo",
    "GetNumTrainerServices", "GetTrainerServiceInfo", "GetTrainerServiceCost",
    "GetTrainerServiceLevelReq", "GetTrainerServiceTypeFilter",
    "SetTrainerServiceTypeFilter", "IsTradeskillTrainer",

    -- Unit API
    "UnitAffectingCombat", "UnitAura", "UnitClass", "UnitExists", "UnitGUID",
    "UnitGetIncomingHeals", "UnitHealth", "UnitHealthMax", "UnitInRange",
    "UnitIsConnected", "UnitIsDeadOrGhost", "UnitIsGhost", "UnitLevel",
    "UnitName", "UnitPower", "UnitPowerMax", "UnitPowerType",
    "UnitThreatSituation",
}

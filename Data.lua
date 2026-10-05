-- Sanctum / Data.lua
-- Static reference data: class click-cast kits, dispel map, tracked auras,
-- goals checklist tables and the default sequence.
--
-- Item IDs are vanilla 1.12 references, unverified on WoW: Forever.
-- Required levels are read live from the client (GetItemInfo) when cached,
-- so a wrong level here self-corrects; a wrong ID simply never matches.

local ADDON, ns = ...
ns.Data = ns.Data or {}
local D = ns.Data

---------------------------------------------------------------------------
-- Click-cast slots, in display order.
-- key = attribute modifier prefix + mouse button number.
---------------------------------------------------------------------------
D.clickSlots = {
    { key = "1",        mod = "",       button = 1, label = "Left" },
    { key = "2",        mod = "",       button = 2, label = "Right" },
    { key = "3",        mod = "",       button = 3, label = "Middle" },
    { key = "shift-1",  mod = "shift-", button = 1, label = "Shift + Left" },
    { key = "shift-2",  mod = "shift-", button = 2, label = "Shift + Right" },
    { key = "shift-3",  mod = "shift-", button = 3, label = "Shift + Middle" },
    { key = "ctrl-1",   mod = "ctrl-",  button = 1, label = "Ctrl + Left" },
    { key = "ctrl-2",   mod = "ctrl-",  button = 2, label = "Ctrl + Right" },
    { key = "alt-1",    mod = "alt-",   button = 1, label = "Alt + Left" },
    { key = "alt-2",    mod = "alt-",   button = 2, label = "Alt + Right" },
    { key = "4",        mod = "",       button = 4, label = "Mouse 4" },
    { key = "5",        mod = "",       button = 5, label = "Mouse 5" },
}

-- Binding values:
--   "Spell A|Spell B|Spell C"  priority list - first KNOWN spell is used,
--                              so bindings upgrade themselves as you level.
--   "@target"                  target the unit
--   "@menu"                    open the unit menu
--   ""                         unbound
D.classKits = {
    PRIEST = {
        ["1"]       = "Heal|Lesser Heal",
        ["2"]       = "Renew",
        ["3"]       = "Resurrection",
        ["shift-1"] = "Flash Heal|Lesser Heal",
        ["shift-2"] = "Power Word: Shield",
        ["shift-3"] = "Power Word: Fortitude",
        ["ctrl-1"]  = "Greater Heal|Heal|Lesser Heal",
        ["ctrl-2"]  = "Dispel Magic",
        ["alt-1"]   = "@target",
        ["alt-2"]   = "Abolish Disease|Cure Disease",
        ["4"]       = "Prayer of Healing",
        ["5"]       = "",
    },
    PALADIN = {
        ["1"] = "Holy Light", ["2"] = "Blessing of Wisdom|Blessing of Might", ["3"] = "Redemption",
        ["shift-1"] = "Flash of Light|Holy Light", ["shift-2"] = "Lay on Hands", ["shift-3"] = "",
        ["ctrl-1"] = "", ["ctrl-2"] = "Cleanse|Purify", ["alt-1"] = "@target",
        ["alt-2"] = "Blessing of Protection", ["4"] = "", ["5"] = "",
    },
    DRUID = {
        ["1"] = "Healing Touch", ["2"] = "Rejuvenation", ["3"] = "Rebirth",
        ["shift-1"] = "Regrowth|Healing Touch", ["shift-2"] = "Mark of the Wild", ["shift-3"] = "",
        ["ctrl-1"] = "", ["ctrl-2"] = "Remove Curse", ["alt-1"] = "@target",
        ["alt-2"] = "Abolish Poison|Cure Poison", ["4"] = "", ["5"] = "",
    },
    SHAMAN = {
        ["1"] = "Healing Wave", ["2"] = "Chain Heal|Healing Wave", ["3"] = "Ancestral Spirit",
        ["shift-1"] = "Lesser Healing Wave|Healing Wave", ["shift-2"] = "", ["shift-3"] = "",
        ["ctrl-1"] = "", ["ctrl-2"] = "Cure Poison", ["alt-1"] = "@target",
        ["alt-2"] = "Cure Disease", ["4"] = "", ["5"] = "",
    },
    DEFAULT = {
        ["1"] = "@target", ["2"] = "@menu",
    },
}

-- Which dispel types each known spell lets you remove.
D.dispelSpells = {
    ["Dispel Magic"]    = { Magic = true },
    ["Cure Disease"]    = { Disease = true },
    ["Abolish Disease"] = { Disease = true },
    ["Purify"]          = { Poison = true, Disease = true },
    ["Cleanse"]         = { Magic = true, Poison = true, Disease = true },
    ["Remove Curse"]    = { Curse = true },
    ["Remove Lesser Curse"] = { Curse = true },
    ["Cure Poison"]     = { Poison = true },
    ["Abolish Poison"]  = { Poison = true },
}

D.dispelColours = {
    Magic   = { 0.20, 0.60, 1.00 },
    Curse   = { 0.60, 0.00, 1.00 },
    Disease = { 0.60, 0.40, 0.00 },
    Poison  = { 0.00, 0.60, 0.00 },
}

-- Corner indicators on unit frames. filter HELPFUL/HARMFUL, mine = only your casts.
D.trackedAuras = {
    PRIEST = {
        { name = "Renew",              filter = "HELPFUL", mine = true,  colour = { 0.2, 1.0, 0.2 } },
        { name = "Power Word: Shield", filter = "HELPFUL", mine = false, colour = { 1.0, 1.0, 1.0 } },
        { name = "Weakened Soul",      filter = "HARMFUL", mine = false, colour = { 0.8, 0.2, 0.2 } },
    },
    DRUID = {
        { name = "Rejuvenation", filter = "HELPFUL", mine = true, colour = { 0.8, 0.3, 1.0 } },
        { name = "Regrowth",     filter = "HELPFUL", mine = true, colour = { 0.2, 1.0, 0.2 } },
        { name = "Wild Growth",  filter = "HELPFUL", mine = true, colour = { 0.6, 1.0, 0.6 } },
    },
    PALADIN = {
        { name = "Light's Vigil", filter = "HELPFUL", mine = true,  colour = { 1.0, 0.9, 0.3 } },
        { name = "Forbearance",   filter = "HARMFUL", mine = false, colour = { 0.8, 0.2, 0.2 } },
    },
    SHAMAN = {
        { name = "Riptide",             filter = "HELPFUL", mine = true,  colour = { 0.2, 0.6, 1.0 } },
        { name = "Ancestral Fortitude", filter = "HELPFUL", mine = false, colour = { 0.6, 0.9, 0.3 } },
    },
}

-- Group buff you are responsible for: a small dot shows on frames missing it (out of combat).
D.groupBuff = {
    PRIEST  = { "Power Word: Fortitude", "Prayer of Fortitude" },
    DRUID   = { "Mark of the Wild", "Gift of the Wild" },
}

---------------------------------------------------------------------------
-- Goals checklist
---------------------------------------------------------------------------
D.goals = {
    -- Gear: inventory slot id, label, level from which an EMPTY slot is flagged,
    -- and whether the slot is expected to carry an enchant (checked from enchantFromLevel).
    gearSlots = {
        { id = 1,  name = "Head",      emptyFrom = 10 },
        { id = 2,  name = "Neck",      emptyFrom = 25 },
        { id = 3,  name = "Shoulder",  emptyFrom = 20 },
        { id = 15, name = "Back",      emptyFrom = 10, enchant = true },
        { id = 5,  name = "Chest",     emptyFrom = 5,  enchant = true },
        { id = 9,  name = "Wrist",     emptyFrom = 10, enchant = true },
        { id = 10, name = "Hands",     emptyFrom = 10, enchant = true },
        { id = 6,  name = "Waist",     emptyFrom = 10 },
        { id = 7,  name = "Legs",      emptyFrom = 5 },
        { id = 8,  name = "Feet",      emptyFrom = 5,  enchant = true },
        { id = 11, name = "Ring 1",    emptyFrom = 25 },
        { id = 12, name = "Ring 2",    emptyFrom = 30 },
        { id = 13, name = "Trinket 1", emptyFrom = 40 },
        { id = 14, name = "Trinket 2", emptyFrom = 50 },
        { id = 16, name = "Main Hand", emptyFrom = 1,  enchant = true },
        { id = 18, name = "Wand",      emptyFrom = 5 },
    },
    enchantFromLevel = 40,  -- enchants flagged from this level (configurable in SanctumDB)
    staleWarn = 10,         -- item required level this far below yours -> amber
    staleBad  = 16,         -- ...this far below -> red
    durWarn = 0.40,
    durBad  = 0.20,
    minFreeBagSlots = 4,

    -- Consumables. Best tier is the highest whose required level <= yours.
    consumablesFrom = 5,
    consumables = {
        {
            label = "Healing Potion", min = 5,
            tiers = {
                { id = 118,   lvl = 1,  name = "Minor Healing Potion" },
                { id = 858,   lvl = 3,  name = "Lesser Healing Potion" },
                { id = 929,   lvl = 12, name = "Healing Potion" },
                { id = 1710,  lvl = 21, name = "Greater Healing Potion" },
                { id = 3928,  lvl = 35, name = "Superior Healing Potion" },
                { id = 13446, lvl = 45, name = "Major Healing Potion" },
            },
        },
        {
            label = "Mana Potion", min = 5, from = 10,
            tiers = {
                { id = 2455,  lvl = 5,  name = "Minor Mana Potion" },
                { id = 3385,  lvl = 14, name = "Lesser Mana Potion" },
                { id = 3827,  lvl = 22, name = "Mana Potion" },
                { id = 6149,  lvl = 31, name = "Greater Mana Potion" },
                { id = 13443, lvl = 41, name = "Superior Mana Potion" },
                { id = 13444, lvl = 49, name = "Major Mana Potion" },
            },
        },
        {
            label = "Drink", min = 20,
            tiers = {
                { id = 159,  lvl = 1,  name = "Refreshing Spring Water" },
                { id = 5350, lvl = 1,  name = "Conjured Water" },
                { id = 1179, lvl = 5,  name = "Ice Cold Milk" },
                { id = 2288, lvl = 5,  name = "Conjured Fresh Water" },
                { id = 1205, lvl = 15, name = "Melon Juice" },
                { id = 2136, lvl = 15, name = "Conjured Purified Water" },
                { id = 1708, lvl = 25, name = "Sweet Nectar" },
                { id = 3772, lvl = 25, name = "Conjured Spring Water" },
                { id = 1645, lvl = 35, name = "Moonberry Juice" },
                { id = 8077, lvl = 35, name = "Conjured Mineral Water" },
                { id = 8766, lvl = 45, name = "Morning Glory Dew" },
                { id = 8078, lvl = 45, name = "Conjured Sparkling Water" },
                { id = 8079, lvl = 55, name = "Conjured Crystal Water" },
            },
        },
        {
            label = "Buff Food", min = 5, from = 10,
            tiers = {
                { id = 6888,  lvl = 1,  name = "Herb Baked Egg" },
                { id = 5527,  lvl = 15, name = "Goblin Deviled Clams" },
                { id = 3729,  lvl = 25, name = "Soothing Turtle Bisque" },
                { id = 12218, lvl = 35, name = "Monster Omelet" },
                { id = 13931, lvl = 35, name = "Nightfin Soup" },
                { id = 18045, lvl = 40, name = "Tender Wolf Steak" },
                { id = 18254, lvl = 45, name = "Runn Tum Tuber Surprise" },
            },
        },
    },

    -- Self-buffs that should be up when out of combat (only checked if the spell is known).
    selfBuffs = {
        PRIEST = {
            { spell = "Power Word: Fortitude", accept = { "Power Word: Fortitude", "Prayer of Fortitude" } },
            { spell = "Inner Fire",            accept = { "Inner Fire" } },
        },
        DRUID   = { { spell = "Mark of the Wild", accept = { "Mark of the Wild", "Gift of the Wild" } } },
        PALADIN = { { spell = "Devotion Aura", accept = { "Devotion Aura", "Concentration Aura", "Retribution Aura" } } },
    },

    -- Reagents, only checked once the spell that needs them is known.
    reagents = {
        PRIEST = {
            { spell = "Prayer of Fortitude", label = "Candles", min = 10, ids = { 17028, 17029 } },
        },
        PALADIN = {
            { spell = "Divine Intervention", label = "Symbol of Divinity", min = 1, ids = { 17033 } },
        },
        DRUID = {
            { spell = "Rebirth", label = "Rebirth reagent", min = 1, ids = { 17034, 17035, 17036, 17037, 17038 } },
        },
        SHAMAN = {
            { spell = "Reincarnation", label = "Ankh", min = 1, ids = { 17030 } },
        },
    },
}

---------------------------------------------------------------------------
-- Default GSE-style sequence. One step fires per key press; KeyPress lines
-- run on every press, PostMacro lines after the step.
---------------------------------------------------------------------------
D.defaultSequences = {
    PRIEST = {
        name = "Priest levelling DPS",
        -- Lines with spells you don't know yet are skipped automatically and
        -- switch on when you learn them (Mind Flay is a Shadow talent).
        keyPress = {
            "/targetenemy [noharm][dead]",
            "/cast [mod:shift,@player] Power Word: Shield",
        },
        steps = {
            "/castsequence [harm,nodead] reset=target Shadow Word: Pain, null",
            "/cast [harm,nodead] Mind Blast",
            "/cast [harm,nodead] Mind Flay",
            "/castsequence [harm,nodead] reset=target Shadow Word: Pain, null",
            "/cast [harm,nodead] !Shoot",
        },
        postMacro = {},
    },
    DRUID = {
        name = "Druid levelling DPS",
        -- Caster form. Feral builds get a Cat Form sequence from the talent planner.
        keyPress = { "/targetenemy [noharm][dead]" },
        steps = {
            "/castsequence [harm,nodead] reset=target Moonfire, null",
            "/castsequence [harm,nodead] reset=target Insect Swarm, null",
            "/cast [harm,nodead] Wrath",
        },
        postMacro = {},
    },
    PALADIN = {
        name = "Paladin levelling DPS",
        -- Seals last 30 sec in Forever and Judgement no longer consumes them,
        -- so the seal goes up once per target.
        keyPress = { "/targetenemy [noharm][dead]", "/startattack" },
        steps = {
            "/castsequence [harm,nodead] reset=target Seal of Righteousness, null",
            "/cast [harm,nodead] Judgement",
            "/cast [harm,nodead] Holy Strike",
        },
        postMacro = {},
    },
    SHAMAN = {
        name = "Shaman levelling DPS",
        keyPress = { "/targetenemy [noharm][dead]" },
        steps = {
            "/castsequence [harm,nodead] reset=target Flame Shock, null",
            "/cast [harm,nodead] Stormstrike",
            "/cast [harm,nodead] Lightning Bolt",
        },
        postMacro = {},
    },
    DEFAULT = {
        name = "Empty",
        keyPress = { "/targetenemy [noharm][dead]" },
        steps = { "/startattack" },
        postMacro = {},
    },
}

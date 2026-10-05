-- Sanctum / TalentData.lua
-- WoW: Forever Priest talent trees and recommended builds.
-- Researched 5 Oct 2026. Positions agree across wowforevertalents.net
-- (build 1.60.1.70009), forevertalents.org and classicwowforever.com, and
-- match Blizzard's Priest deep dive (30 Sep 2026). Beta: may change.
-- Every build below is validated by tests/run.lua (row gates, prerequisites, max ranks).

local ADDON, ns = ...
ns.Talents = ns.Talents or {}
local TD = {}
ns.TalentData = TD

-- abbr = { name, tree (1 Disc, 2 Holy, 3 Shadow), row, max, pre = abbr }
TD.PRIEST = {
    talents = {
        -- Discipline
        PiL      = { name = "Power in Light",             tree = 1, row = 1, max = 5 },
        Wand     = { name = "Wand Specialization",        tree = 1, row = 1, max = 2 },
        TD       = { name = "Twin Disciplines",           tree = 1, row = 1, max = 5 },
        SilRes   = { name = "Silent Resolve",             tree = 1, row = 2, max = 3 },
        HolyPrec = { name = "Holy Precision",             tree = 1, row = 2, max = 3 },
        IPWS     = { name = "Improved Power Word: Shield", tree = 1, row = 2, max = 3 },
        Mart     = { name = "Martyrdom",                  tree = 1, row = 2, max = 2 },
        MA       = { name = "Mental Agility",             tree = 1, row = 3, max = 3 },
        IF       = { name = "Inner Focus",                tree = 1, row = 3, max = 1 },
        Med      = { name = "Meditation",                 tree = 1, row = 3, max = 3 },
        IIF      = { name = "Improved Inner Fire",        tree = 1, row = 4, max = 3 },
        MS       = { name = "Mental Strength",            tree = 1, row = 4, max = 5 },
        SW       = { name = "Soul Warding",               tree = 1, row = 4, max = 1, pre = "IPWS" },
        IMB      = { name = "Improved Mana Burn",         tree = 1, row = 4, max = 2 },
        Pen      = { name = "Penance",                    tree = 1, row = 5, max = 1 },
        RH       = { name = "Renewed Hope",               tree = 1, row = 5, max = 5, pre = "SW" },
        DA       = { name = "Divine Aegis",               tree = 1, row = 6, max = 3 },
        PI       = { name = "Power Infusion",             tree = 1, row = 7, max = 1, pre = "Pen" },
        -- Holy
        TF       = { name = "Twilight Focus",             tree = 2, row = 1, max = 3 },
        IR       = { name = "Improved Renew",             tree = 2, row = 1, max = 3 },
        HS       = { name = "Holy Specialization",        tree = 2, row = 1, max = 5 },
        SpW      = { name = "Spell Warding",              tree = 2, row = 2, max = 5 },
        DF       = { name = "Divine Fury",                tree = 2, row = 2, max = 5 },
        HN       = { name = "Holy Nova",                  tree = 2, row = 3, max = 1 },
        BR       = { name = "Blessed Recovery",           tree = 2, row = 3, max = 3 },
        Insp     = { name = "Inspiration",                tree = 2, row = 3, max = 3 },
        HR       = { name = "Holy Reach",                 tree = 2, row = 4, max = 2 },
        IH       = { name = "Improved Healing",           tree = 2, row = 4, max = 3 },
        SL       = { name = "Searing Light",              tree = 2, row = 4, max = 2, pre = "DF" },
        BH       = { name = "Binding Heal",               tree = 2, row = 4, max = 1 },
        LoL      = { name = "Litany of Light",            tree = 2, row = 5, max = 2 },
        SoR      = { name = "Spirit of Redemption",       tree = 2, row = 5, max = 1 },
        SG       = { name = "Spiritual Guidance",         tree = 2, row = 5, max = 5 },
        SH       = { name = "Spiritual Healing",          tree = 2, row = 6, max = 3 },
        PoM      = { name = "Prayer of Mending",          tree = 2, row = 7, max = 1, pre = "SoR" },
        -- Shadow Magic
        SF       = { name = "Shadow Focus",               tree = 3, row = 1, max = 5 },
        BO       = { name = "Blackout",                   tree = 3, row = 1, max = 5 },
        ST       = { name = "Spirit Tap",                 tree = 3, row = 1, max = 5 },
        SA       = { name = "Shadow Affinity",            tree = 3, row = 2, max = 3 },
        ISWP     = { name = "Improved Shadow Word: Pain", tree = 3, row = 2, max = 2 },
        SR       = { name = "Shadow Reach",               tree = 3, row = 2, max = 2 },
        IMBl     = { name = "Improved Mind Blast",        tree = 3, row = 3, max = 5 },
        IPS      = { name = "Improved Psychic Scream",    tree = 3, row = 3, max = 2, pre = "BO" },
        MF       = { name = "Mind Flay",                  tree = 3, row = 3, max = 1 },
        IMF      = { name = "Improved Mind Flay",         tree = 3, row = 3, max = 2, pre = "MF" },
        IFade    = { name = "Improved Fade",              tree = 3, row = 4, max = 2 },
        VE       = { name = "Vampiric Embrace",           tree = 3, row = 4, max = 1 },
        SWv      = { name = "Shadow Weaving",             tree = 3, row = 4, max = 3 },
        Sil      = { name = "Silence",                    tree = 3, row = 5, max = 1 },
        DC       = { name = "Devouring Contagion",        tree = 3, row = 5, max = 2 },
        ED       = { name = "Early Demise",               tree = 3, row = 6, max = 2 },
        Dark     = { name = "Darkness",                   tree = 3, row = 6, max = 5 },
        SFm      = { name = "Shadowform",                 tree = 3, row = 7, max = 1, pre = "VE" },
    },
    trees = { "Discipline", "Holy", "Shadow" },

    -- One token per point from level 10. "X*3" = three points in X.
    -- constructed = true: the source gives a finished build, not an order;
    -- the order was built from that source's priorities.
    builds = {
        {
            key = "holy_dungeon", label = "Holy - dungeon healing (levelling)", split = "10/41/0",
            source = "wowforeverbuilds.com Spell Cleave + Control Group 5-man guides (15-16 Sep 2026)",
            order = "IR*3 TF*2 DF*5 HN Insp*3 TF IH*3 HR*2 SG*5 SH*3 SoR LoL PoM HS*5 LoL BH TD*5 SilRes*2 IPWS*3 BR*3",
        },
        {
            key = "disc_dungeon", label = "Disc - dungeon healing (levelling)", split = "41/10/0",
            source = "wowforeverbuilds.com Shadow Cleave 5-man (Discipline) guide (15-16 Sep 2026)",
            order = "TD*5 IPWS*3 SilRes*3 Med*3 IF SW MS*5 Pen RH*5 DA*3 PI MA*3 Mart*2 IIF*3 Wand*2 IR*3 TF*2 DF*5",
        },
        {
            key = "holy_hybrid", label = "Holy - solo levelling that still heals", split = "20/26/5",
            source = "wowforeverbuilds.com Holy Priest leveling 30-60 (Smite / Holy Fire / Searing Light) (15-16 Sep 2026)",
            order = "Wand*2 ST*5 HS*5 DF*5 HN TF*3 BR SL*2 HR*2 BR*2 SG*5 PiL*5 HolyPrec*3 MA*3 IF Med*3 IPWS*3",
        },
        {
            key = "shadow_solo", label = "Shadow - fastest solo levelling", split = "11/0/40",
            source = "wowforeverbuilds.com Shadow Priest leveling guide 10-60 (15-16 Sep 2026)",
            order = "Wand*2 ST*5 ISWP*2 SF*3 MF IMF*2 IMBl*2 VE SWv*3 IMBl Sil IMBl*2 SR*2 Dark*5 SFm SF*2 BO*5 IPS*2 TD*3 IPWS*3 TD*2 MA",
        },
        {
            key = "wand_disc", label = "Disc - wand levelling (10-40)", split = "24/0/7",
            source = "wowforeverbuilds.com Wand Discipline leveling 10-40",
            order = "Wand*2 ST*5 ISWP*2 TD*3 IPWS*3 TD*2 Med*3 MA*2 SW MS*5 Pen MA IF",
        },
        {
            key = "holy_raid", label = "Holy - raid healing (60)", split = "18/33/0", constructed = true,
            source = "wowforeverbuilds.com Holy Priest PvE guide (17 Sep 2026) - order constructed from its priorities",
            order = "IR*3 HS*5 DF*5 HN Insp*3 IH*3 SG*5 SH*3 SoR LoL PoM LoL BH TD*5 SilRes*3 IPWS*2 Med*3 IF MA MS*3",
        },
        {
            key = "disc_raid", label = "Disc - raid healing (60)", split = "33/18/0", constructed = true,
            source = "wowforeverbuilds.com Discipline Priest PvE guide (17 Sep 2026) - order constructed from its priorities",
            order = "TD*5 IPWS*3 SilRes*2 Med*3 IF MA SW MS*4 Pen RH*5 DA*3 MS PI MA*2 HS*5 DF*5 SpW*2 Insp*3 IH*3",
        },
    },
    defaultBuild = "holy_dungeon",
}

-- Talents that give you a castable spell (name == talent name).
TD.PRIEST.activeTalents = { "MF", "Sil", "VE", "SFm", "IF", "Pen", "PI", "HN", "BH", "PoM" }

-- Trainer level for each baseline spell (rank 1). Vanilla 1.12 levels, with
-- Forever changes from Blizzard's deep dive (30 Sep 2026): Fear Ward and
-- Devouring Plague baseline at 20, Divine Spirit at 30, Shadow Word: Death at 32,
-- Human Divine Grace at 10. Racials marked are race-only.
TD.PRIEST.trainer = {
    ["Smite"] = 1, ["Lesser Heal"] = 1, ["Power Word: Fortitude"] = 1, ["Shoot"] = 1,
    ["Shadow Word: Pain"] = 4, ["Power Word: Shield"] = 6, ["Renew"] = 8, ["Fade"] = 8,
    ["Mind Blast"] = 10, ["Resurrection"] = 10, ["Inner Fire"] = 12, ["Psychic Scream"] = 14,
    ["Cure Disease"] = 14, ["Heal"] = 16, ["Dispel Magic"] = 18, ["Holy Fire"] = 20,
    ["Flash Heal"] = 20, ["Mind Soothe"] = 20, ["Shackle Undead"] = 20, ["Fear Ward"] = 20,
    ["Devouring Plague"] = 20, ["Mind Vision"] = 22, ["Mana Burn"] = 24, ["Prayer of Healing"] = 30,
    ["Shadow Protection"] = 30, ["Mind Control"] = 30, ["Divine Spirit"] = 30,
    ["Abolish Disease"] = 32, ["Shadow Word: Death"] = 32, ["Levitate"] = 34, ["Greater Heal"] = 40,
    ["Prayer of Fortitude"] = 48, ["Prayer of Shadow Protection"] = 56,
    -- racials
    ["Divine Grace"] = 10, ["Desperate Prayer"] = 10, ["Starshards"] = 10, ["Hex of Weakness"] = 10,
    ["Touch of Weakness"] = 10, ["Feedback"] = 20, ["Elune's Grace"] = 20, ["Shadowguard"] = 20,
}

-- Sequence templates per play style. Steps using a talent your build never
-- takes are left out when the template is loaded.
TD.PRIEST.sequences = {
    shadow = {
        name = "Shadow levelling",
        keyPress = { "/targetenemy [noharm][dead]", "/cast [mod:shift,@player] Power Word: Shield" },
        steps = { { "Shadow Word: Pain", "dot" }, { "Mind Blast", "enemy" }, { "Mind Flay", "enemy" },
                  { "Shadow Word: Pain", "dot" }, { "Mind Flay", "enemy" }, { "Shoot", "enemy" } },
    },
    holy = {
        name = "Holy levelling",
        keyPress = { "/targetenemy [noharm][dead]", "/cast [mod:shift,@player] Power Word: Shield" },
        steps = { { "Shadow Word: Pain", "dot" }, { "Holy Fire", "enemy" }, { "Mind Blast", "enemy" },
                  { "Shadow Word: Pain", "dot" }, { "Shoot", "enemy" } },
    },
    disc = {
        name = "Disc levelling",
        keyPress = { "/targetenemy [noharm][dead]", "/cast [mod:shift,@player] Power Word: Shield" },
        steps = { { "Shadow Word: Pain", "dot" }, { "Penance", "enemy" }, { "Mind Blast", "enemy" },
                  { "Shadow Word: Pain", "dot" }, { "Shoot", "enemy" } },
    },
}
-- Which template each build uses.
TD.PRIEST.buildSequence = {
    holy_dungeon = "holy", disc_dungeon = "disc", holy_hybrid = "holy", shadow_solo = "shadow",
    wand_disc = "disc", holy_raid = "holy", disc_raid = "disc",
}

-- Sanctum / TalentData.lua
-- WoW: Forever talent trees and recommended builds for the healing classes
-- Priest researched 5 Oct 2026. Positions agree across wowforevertalents.net
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

---------------------------------------------------------------------------
-- Druid. Researched 5 Oct 2026. Positions from the talentsforever.com /
-- wowforevertalents.com export (client 1.60.1.70170, page build 70205),
-- Balance and Restoration also agree with classicwowforever.com (70009).
-- Uses the post 24 Sep tree (Shifting Power in, King of the Jungle and
-- Tiger's Fury out). Beta: may change.
---------------------------------------------------------------------------
TD.DRUID = {
    talents = {
        -- Balance
        IW       = { name = "Improved Wrath",            tree = 1, row = 1, max = 5 },
        Gen      = { name = "Genesis",                   tree = 1, row = 1, max = 5 },
        MGlow    = { name = "Moonglow",                  tree = 1, row = 2, max = 3 },
        IMF      = { name = "Improved Moonfire",         tree = 1, row = 2, max = 2 },
        NMaj     = { name = "Nature's Majesty",          tree = 1, row = 2, max = 2 },
        NReach   = { name = "Nature's Reach",            tree = 1, row = 2, max = 2 },
        IER      = { name = "Improved Entangling Roots", tree = 1, row = 3, max = 3 },
        NSplen   = { name = "Nature's Splendor",         tree = 1, row = 3, max = 1, pre = "NMaj" },
        ISwarm   = { name = "Insect Swarm",              tree = 1, row = 4, max = 1 },
        Veng     = { name = "Vengeance",                 tree = 1, row = 4, max = 5, pre = "IMF" },
        IStar    = { name = "Improved Starfire",         tree = 1, row = 4, max = 5 },
        Overg    = { name = "Overgrowth",                tree = 1, row = 5, max = 2 },
        NGrace   = { name = "Nature's Grace",            tree = 1, row = 5, max = 1 },
        Eclipse  = { name = "Eclipse",                   tree = 1, row = 5, max = 3 },
        Moonfury = { name = "Moonfury",                  tree = 1, row = 6, max = 5 },
        Moonkin  = { name = "Moonkin Form",              tree = 1, row = 7, max = 1 },
        -- Feral Combat
        Feroc    = { name = "Ferocity",                  tree = 2, row = 1, max = 5 },
        HotW     = { name = "Heart of the Wild",         tree = 2, row = 1, max = 5 },
        FSwift   = { name = "Feral Swiftness",           tree = 2, row = 2, max = 2 },
        FInst    = { name = "Feral Instinct",            tree = 2, row = 2, max = 3 },
        BrutImp  = { name = "Brutal Impact",             tree = 2, row = 2, max = 2 },
        ThickH   = { name = "Thick Hide",                tree = 2, row = 2, max = 3 },
        ShredAtk = { name = "Shredding Attacks",         tree = 2, row = 3, max = 3 },
        SavFury  = { name = "Savage Fury",               tree = 2, row = 3, max = 2 },
        FCharge  = { name = "Feral Charge",              tree = 2, row = 3, max = 1 },
        SharpCl  = { name = "Sharpened Claws",           tree = 2, row = 3, max = 2 },
        ShiftPow = { name = "Shifting Power",            tree = 2, row = 4, max = 1, pre = "ShredAtk" },
        PBite    = { name = "Primal Bite",               tree = 2, row = 4, max = 1, pre = "SavFury" },
        PredStr  = { name = "Predatory Strikes",         tree = 2, row = 4, max = 3 },
        BFrenzy  = { name = "Blood Frenzy",              tree = 2, row = 4, max = 2, pre = "SharpCl" },
        ImpShift = { name = "Improved Shifting Power",   tree = 2, row = 5, max = 2, pre = "ShiftPow" },
        LotP     = { name = "Leader of the Pack",        tree = 2, row = 5, max = 1 },
        PredInst = { name = "Predatory Instincts",       tree = 2, row = 5, max = 2 },
        NatReact = { name = "Natural Reaction",          tree = 2, row = 6, max = 5 },
        RendTear = { name = "Rend and Tear",             tree = 2, row = 6, max = 5, pre = "PredStr" },
        Berserk  = { name = "Berserk",                   tree = 2, row = 7, max = 1, pre = "LotP" },
        -- Restoration
        NFocus   = { name = "Nature's Focus",            tree = 3, row = 1, max = 5 },
        Furor    = { name = "Furor",                     tree = 3, row = 1, max = 5 },
        Natur    = { name = "Naturalist",                tree = 3, row = 2, max = 5 },
        Subt     = { name = "Subtlety",                  tree = 3, row = 2, max = 3 },
        NShape   = { name = "Natural Shapeshifter",      tree = 3, row = 2, max = 3 },
        Refl     = { name = "Reflection",                tree = 3, row = 3, max = 3 },
        GoN      = { name = "Gift of Nature",            tree = 3, row = 3, max = 5 },
        GotE     = { name = "Gift of the Earthmother",   tree = 3, row = 3, max = 1 },
        TSpirit  = { name = "Tranquil Spirit",           tree = 3, row = 4, max = 5 },
        IRejuv   = { name = "Improved Rejuvenation",     tree = 3, row = 4, max = 3 },
        Swiftm   = { name = "Swiftmend",                 tree = 3, row = 4, max = 1 },
        NSwift   = { name = "Nature's Swiftness",        tree = 3, row = 5, max = 1, pre = "Natur" },
        LSpirit  = { name = "Living Spirit",             tree = 3, row = 5, max = 3 },
        ITranq   = { name = "Improved Tranquility",      tree = 3, row = 5, max = 2 },
        IRegr    = { name = "Improved Regrowth",         tree = 3, row = 6, max = 5, pre = "IRejuv" },
        WGrowth  = { name = "Wild Growth",               tree = 3, row = 7, max = 1, pre = "LSpirit" },
    },
    trees = { "Balance", "Feral", "Restoration" },
    treeTags = { "|cff80c0ffB|r", "|cffffa040F|r", "|cff60ff60R|r" },
    builds = {
        {
            key = "resto_dungeon", label = "Resto - dungeon healing (levelling)", split = "10/0/41", constructed = true,
            source = "wowforeverbuilds.com Hybrid Cleave 5-man Restoration Druid (15-16 Sep 2026) to 40, then completed towards its Resto PvE guide (17 Sep 2026)",
            order = "NFocus*5 Natur*5 GoN*5 IRejuv*3 Swiftm GotE NSwift LSpirit*3 Refl*3 IRegr*3 WGrowth IRegr*2 Gen*5 Subt*3 TSpirit*3 ITranq*2 NMaj*2 MGlow*3",
        },
        {
            key = "feral_solo", label = "Feral - cat solo levelling", split = "0/41/10", constructed = true,
            source = "wowforeverbuilds.com Feral Druid leveling guide 10-60 (15-16 Sep 2026), moved to the current tree (Primal Bite, Blood Frenzy, Shifting Power)",
            order = "Feroc*5 FSwift*2 ThickH*3 SharpCl*2 SavFury*2 FCharge ShredAtk*3 PredStr*3 ShiftPow BFrenzy*2 PBite ImpShift*2 PredInst*2 LotP RendTear*5 Berserk Furor*5 Natur*5 HotW*5",
        },
        {
            key = "resto_solo", label = "Resto - solo levelling that still heals (10-40)", split = "5/0/26",
            source = "wowforeverbuilds.com Restoration Druid leveling guide 1-40 (15 Sep 2026)",
            order = "IW*5 NFocus*5 Natur*5 Refl*3 GoN*2 Swiftm IRejuv*3 GoN NSwift LSpirit*3 GoN*2",
        },
        {
            key = "balance_solo", label = "Balance - Moonkin levelling", split = "46/0/5", constructed = true,
            source = "wowforeverbuilds.com Balance Druid leveling guide 10-50 (15 Sep 2026), last 10 points from its Druid + Hunter duo guide",
            order = "IW*5 IMF*2 NMaj*2 NReach*2 IER*3 NSplen ISwarm Veng*5 NGrace MGlow*3 Moonfury*5 Moonkin IStar*5 NFocus*5 Gen*5 Eclipse*3 Overg*2",
        },
        {
            key = "resto_raid", label = "Resto - raid healing (60)", split = "10/0/41", constructed = true,
            source = "wowforeverbuilds.com Restoration Druid PvE guide (17 Sep 2026) - order constructed from its priorities",
            order = "NFocus*5 Natur*5 GoN*5 IRejuv*3 Swiftm GotE NSwift LSpirit*3 Refl*3 IRegr*5 WGrowth Subt*3 TSpirit*3 ITranq*2 Gen*5 NMaj*2 MGlow*3",
        },
        {
            key = "feral_resto", label = "Feral/Resto hybrid (60)", split = "0/20/31", constructed = true,
            source = "wowforeverbuilds.com Restoration Druid PvP guide (17 Sep 2026) - order constructed from its priorities",
            order = "HotW*5 FSwift*2 ThickH*3 SavFury*2 FCharge SharpCl*2 PredStr*3 ShredAtk*2 NFocus*5 Natur*5 Refl*3 GoN*2 GotE IRejuv*3 TSpirit Swiftm NSwift LSpirit*3 IRegr*5 WGrowth",
        },
    },
    defaultBuild = "resto_dungeon",
}

TD.DRUID.activeTalents = { "ISwarm", "Moonkin", "FCharge", "ShiftPow", "PBite", "Berserk", "Swiftm", "NSwift", "WGrowth" }

-- Vanilla 1.12 levels with Forever changes: Nature's Grasp trained at 10,
-- Revive at 12, Omen of Clarity baseline at 20, Lacerate at 42, Tiger's Fury removed.
TD.DRUID.trainer = {
    ["Wrath"] = 1, ["Healing Touch"] = 1, ["Mark of the Wild"] = 1,
    ["Moonfire"] = 4, ["Rejuvenation"] = 4, ["Thorns"] = 6, ["Entangling Roots"] = 8,
    ["Bear Form"] = 10, ["Demoralizing Roar"] = 10, ["Growl"] = 10, ["Maul"] = 10,
    ["Teleport: Moonglade"] = 10, ["Nature's Grasp"] = 10,
    ["Regrowth"] = 12, ["Enrage"] = 12, ["Revive"] = 12,
    ["Bash"] = 14, ["Cure Poison"] = 14, ["Swipe"] = 16, ["Aquatic Form"] = 16,
    ["Faerie Fire"] = 18, ["Hibernate"] = 18,
    ["Cat Form"] = 20, ["Claw"] = 20, ["Rip"] = 20, ["Prowl"] = 20, ["Rebirth"] = 20,
    ["Starfire"] = 20, ["Omen of Clarity"] = 20,
    ["Shred"] = 22, ["Soothe Animal"] = 22, ["Rake"] = 24, ["Remove Curse"] = 24,
    ["Dash"] = 26, ["Abolish Poison"] = 26, ["Cower"] = 28, ["Challenging Roar"] = 28,
    ["Travel Form"] = 30, ["Tranquility"] = 30,
    ["Ferocious Bite"] = 32, ["Ravage"] = 32, ["Track Humanoids"] = 32,
    ["Pounce"] = 36, ["Frenzied Regeneration"] = 36,
    ["Dire Bear Form"] = 40, ["Hurricane"] = 40, ["Innervate"] = 40, ["Feline Grace"] = 40,
    ["Lacerate"] = 42, ["Barkskin"] = 44, ["Gift of the Wild"] = 50,
}

TD.DRUID.sequences = {
    feral = {
        name = "Feral levelling (Cat Form)",
        keyPress = { "/targetenemy [noharm][dead]", "/startattack" },
        steps = { { "Faerie Fire", "dot" }, { "Rake", "dot" }, { "Claw", "enemy" } },
    },
    balance = {
        name = "Balance levelling",
        keyPress = { "/targetenemy [noharm][dead]" },
        steps = { { "Moonfire", "dot" }, { "Insect Swarm", "dot" }, { "Wrath", "enemy" } },
    },
}
TD.DRUID.buildSequence = {
    resto_dungeon = "balance", feral_solo = "feral", resto_solo = "balance",
    balance_solo = "balance", resto_raid = "balance", feral_resto = "feral",
}

---------------------------------------------------------------------------
-- Paladin. Researched 5 Oct 2026. Positions agree across
-- wowforevertalents.net (69876 / 70009), wowforevertalent.com (70170),
-- forevertalents.org and wowforevertalents.com (70205). Uses the post
-- 24 Sep tree (Crusade and Improved Holy Strike removed). The source
-- guides predate that update, so builds that used them are adapted.
-- Horde can play Paladin as Undead only. Beta: may change.
---------------------------------------------------------------------------
TD.PALADIN = {
    talents = {
        -- Holy
        DStr    = { name = "Divine Strength",        tree = 1, row = 1, max = 5 },
        DInt    = { name = "Divine Intellect",       tree = 1, row = 1, max = 5 },
        HLgt    = { name = "Healing Light",          tree = 1, row = 2, max = 3 },
        SFoc    = { name = "Spiritual Focus",        tree = 1, row = 2, max = 2 },
        ISeal   = { name = "Improved Seals",         tree = 1, row = 2, max = 3 },
        UFaith  = { name = "Unyielding Faith",       tree = 1, row = 2, max = 2 },
        VoT     = { name = "Voice of Truth",         tree = 1, row = 3, max = 1 },
        Rev     = { name = "Reverence",              tree = 1, row = 3, max = 3 },
        PPow    = { name = "Purifying Power",        tree = 1, row = 3, max = 2 },
        IoL     = { name = "Infusion of Light",      tree = 1, row = 4, max = 2 },
        Illum   = { name = "Illumination",           tree = 1, row = 4, max = 5, pre = "Rev" },
        DFav    = { name = "Divine Favor",           tree = 1, row = 4, max = 1 },
        HShock  = { name = "Holy Shock",             tree = 1, row = 5, max = 1 },
        DPrec   = { name = "Divine Precision",       tree = 1, row = 5, max = 3, pre = "HShock" },
        CGround = { name = "Consecrated Ground",     tree = 1, row = 5, max = 2 },
        HPow    = { name = "Holy Power",             tree = 1, row = 6, max = 5 },
        LVig    = { name = "Light's Vigil",          tree = 1, row = 7, max = 1, pre = "HShock" },
        -- Protection
        Tough   = { name = "Toughness",              tree = 2, row = 1, max = 5 },
        Redo    = { name = "Redoubt",                tree = 2, row = 1, max = 5 },
        Prec    = { name = "Precision",              tree = 2, row = 2, max = 3 },
        GFav    = { name = "Guardian's Favor",       tree = 2, row = 2, max = 2 },
        Antic   = { name = "Anticipation",           tree = 2, row = 2, max = 5 },
        ISoF    = { name = "Improved Seal of Fury",  tree = 2, row = 3, max = 1 },
        IRF     = { name = "Improved Righteous Fury", tree = 2, row = 3, max = 3 },
        SSpec   = { name = "Shield Specialization",  tree = 2, row = 3, max = 3, pre = "Redo" },
        SDuty   = { name = "Sacred Duty",            tree = 2, row = 3, max = 2 },
        SwJ     = { name = "Swift Judgement",        tree = 2, row = 4, max = 1, pre = "ISoF" },
        OneH    = { name = "One-Handed Weapon Specialization", tree = 2, row = 4, max = 3 },
        IHoJ    = { name = "Improved Hammer of Justice", tree = 2, row = 4, max = 3 },
        TBul    = { name = "Templar's Bulwark",      tree = 2, row = 5, max = 1 },
        Reck    = { name = "Reckoning",              tree = 2, row = 5, max = 5 },
        ICreed  = { name = "Iron Creed",             tree = 2, row = 6, max = 5 },
        HShield = { name = "Holy Shield",            tree = 2, row = 7, max = 1, pre = "TBul" },
        -- Retribution
        Defl    = { name = "Deflection",             tree = 3, row = 1, max = 5 },
        Bene    = { name = "Benediction",            tree = 3, row = 1, max = 5 },
        IJudge  = { name = "Improved Judgement",     tree = 3, row = 2, max = 2 },
        HCond   = { name = "Holy Conduit",           tree = 3, row = 2, max = 2 },
        Conv    = { name = "Conviction",             tree = 3, row = 2, max = 5 },
        Vind    = { name = "Vindication",            tree = 3, row = 3, max = 3 },
        SJudge  = { name = "Sanctified Judgement",   tree = 3, row = 3, max = 3 },
        SoC     = { name = "Seal of Command",        tree = 3, row = 3, max = 1 },
        PoJ     = { name = "Pursuit of Justice",     tree = 3, row = 3, max = 2 },
        EfE     = { name = "Eye for an Eye",         tree = 3, row = 4, max = 2 },
        SArb    = { name = "Sacred Arbiter",         tree = 3, row = 4, max = 1 },
        TwoH    = { name = "Two-Handed Weapon Specialization", tree = 3, row = 5, max = 3 },
        Veng    = { name = "Vengeance",              tree = 3, row = 5, max = 3, pre = "SJudge" },
        Rep     = { name = "Repentance",             tree = 3, row = 5, max = 1 },
        CotL    = { name = "Champion of the Light",  tree = 3, row = 6, max = 3 },
        ILaw    = { name = "Instrument of Law",      tree = 3, row = 6, max = 2 },
        ToL     = { name = "Twist of Light",         tree = 3, row = 7, max = 1 },
    },
    trees = { "Holy", "Protection", "Retribution" },
    treeTags = { "|cffffffa0H|r", "|cff80c0ffP|r", "|cffff8080R|r" },
    builds = {
        {
            key = "holy_dungeon", label = "Holy - dungeon healing (levelling)", split = "43/0/8",
            source = "wowforeverbuilds.com Mage Cleave 5-man Holy Paladin guide (15 Sep 2026), last 2 points moved off the removed Improved Holy Strike",
            order = "DInt*5 HLgt*3 SFoc*2 Rev*3 UFaith*2 Illum*5 HShock DFav IoL*2 VoT HPow*5 LVig PPow*2 CGround*2 Bene*5 HCond*2 IJudge DPrec*3 ISeal*3 DStr*2",
        },
        {
            key = "ret_solo", label = "Ret - solo levelling", split = "13/0/38",
            source = "wowforeverbuilds.com Retribution Paladin leveling guide 10-60 (15-16 Sep 2026), Crusade points moved after its removal",
            order = "Bene*5 IJudge*2 Conv*3 SoC Conv*2 SJudge*3 HCond*2 PoJ*2 Veng*3 TwoH*3 Rep Vind*3 ToL CotL*3 SArb Defl*2 DStr*5 ISeal*3 DInt*5 Defl",
        },
        {
            key = "holy_shock", label = "Holy - Holy Shock hybrid levelling (10-40)", split = "21/0/10",
            source = "wowforeverbuilds.com Holy Paladin leveling guide 10-40 (15-16 Sep 2026), Improved Holy Strike points moved after its removal",
            order = "DStr*5 ISeal*3 DInt*2 PPow*2 Rev*3 DFav DInt*3 HLgt HShock Bene*5 IJudge*2 Conv*3",
        },
        {
            key = "prot_dungeon", label = "Prot - dungeon tanking (levelling)", split = "8/43/0",
            source = "wowforeverbuilds.com Mage Cleave 5-man Protection Paladin guide (15 Sep 2026)",
            order = "Tough*3 Redo*2 Prec*3 Antic*2 ISoF IRF*3 SDuty SwJ OneH*3 SDuty TBul Tough*2 Antic*2 ICreed*5 HShield Redo*3 SSpec*3 Antic Reck*5 DInt*5 ISeal*3",
        },
        {
            key = "prot_aoe", label = "Prot - AoE solo levelling", split = "0/46/5",
            source = "wowforeverbuilds.com Protection Paladin AoE leveling guide 30-60 (15-16 Sep 2026)",
            order = "Redo*5 Prec*3 Tough*2 ISoF SSpec*3 IRF*3 OneH*3 TBul Reck*5 ICreed*4 HShield ICreed SDuty*2 SwJ Tough*3 Antic*5 Bene*5 IHoJ*3",
        },
        {
            key = "holy_raid", label = "Holy - raid healing (60)", split = "33/7/11", constructed = true,
            source = "wowforeverbuilds.com Holy Paladin PvE guide (17 Sep 2026) - order constructed from its priorities",
            order = "DInt*5 HLgt*3 SFoc*2 Rev*3 UFaith*2 Illum*5 HShock DFav IoL*2 VoT HPow*5 LVig PPow*2 Bene*5 IJudge*2 HCond*2 Defl SJudge Tough*5 GFav*2",
        },
    },
    defaultBuild = "holy_dungeon",
}

TD.PALADIN.activeTalents = { "VoT", "DFav", "HShock", "LVig", "SwJ", "TBul", "HShield", "SoC", "Rep" }

-- Vanilla 1.12 levels with Forever changes: Holy Strike at 6, Seal of Fury at 10,
-- Consecration and Blessing of Kings baseline at 20, Greater Blessing of Kings at 60.
TD.PALADIN.trainer = {
    ["Holy Light"] = 1, ["Seal of Righteousness"] = 1, ["Devotion Aura"] = 1,
    ["Blessing of Might"] = 4, ["Judgement"] = 4,
    ["Divine Protection"] = 6, ["Seal of the Crusader"] = 6, ["Holy Strike"] = 6,
    ["Purify"] = 8, ["Hammer of Justice"] = 8,
    ["Lay on Hands"] = 10, ["Blessing of Protection"] = 10, ["Seal of Fury"] = 10,
    ["Redemption"] = 12, ["Blessing of Wisdom"] = 14,
    ["Righteous Fury"] = 16, ["Retribution Aura"] = 16, ["Blessing of Freedom"] = 18,
    ["Exorcism"] = 20, ["Flash of Light"] = 20, ["Sense Undead"] = 20,
    ["Consecration"] = 20, ["Blessing of Kings"] = 20,
    ["Concentration Aura"] = 22, ["Seal of Justice"] = 22, ["Turn Undead"] = 24,
    ["Blessing of Salvation"] = 26, ["Shadow Resistance Aura"] = 28,
    ["Divine Intervention"] = 30, ["Seal of Light"] = 30,
    ["Frost Resistance Aura"] = 32, ["Divine Shield"] = 34, ["Fire Resistance Aura"] = 36,
    ["Seal of Wisdom"] = 38, ["Blessing of Light"] = 40, ["Cleanse"] = 42,
    ["Hammer of Wrath"] = 44, ["Blessing of Sacrifice"] = 46, ["Holy Wrath"] = 50,
    ["Greater Blessing of Might"] = 52, ["Greater Blessing of Wisdom"] = 54,
    ["Greater Blessing of Kings"] = 60, ["Greater Blessing of Light"] = 60,
    ["Greater Blessing of Salvation"] = 60,
}

-- Seals are cast once per target ("dot" step): in Forever they last 30 sec
-- and Judgement no longer consumes them.
TD.PALADIN.sequences = {
    ret = {
        name = "Ret levelling",
        keyPress = { "/targetenemy [noharm][dead]", "/startattack" },
        steps = { { "Seal of Command", "dot" }, { "Seal of Righteousness", "dot" },
                  { "Judgement", "enemy" }, { "Holy Strike", "enemy" } },
    },
    holy = {
        name = "Holy questing",
        keyPress = { "/targetenemy [noharm][dead]", "/startattack" },
        steps = { { "Seal of Righteousness", "dot" }, { "Judgement", "enemy" },
                  { "Holy Shock", "enemy" }, { "Holy Strike", "enemy" } },
    },
    prot = {
        name = "Prot levelling",
        keyPress = { "/targetenemy [noharm][dead]", "/startattack" },
        steps = { { "Seal of Fury", "dot" }, { "Judgement", "enemy" },
                  { "Holy Strike", "enemy" }, { "Consecration", "enemy" } },
    },
}
TD.PALADIN.buildSequence = {
    holy_dungeon = "holy", ret_solo = "ret", holy_shock = "holy",
    prot_dungeon = "prot", prot_aoe = "prot", holy_raid = "holy",
}

---------------------------------------------------------------------------
-- Shaman. Researched 5 Oct 2026. Positions agree across
-- wowforevertalents.net (70009), talentsforever.com (70170) and
-- foreverchanges.pro (70205). wowforeverbuilds.com swaps two Elemental and
-- two Restoration pairs; the majority layout is used and every build below
-- is legal under it. Alliance can play Shaman as Dwarf only. Earth Shield
-- does not exist; Water Shield is a Restoration talent. Beta: may change.
---------------------------------------------------------------------------
TD.SHAMAN = {
    talents = {
        -- Elemental
        Conv    = { name = "Convection",             tree = 1, row = 1, max = 5 },
        Conc    = { name = "Concussion",             tree = 1, row = 1, max = 5 },
        EWard   = { name = "Elemental Warding",      tree = 1, row = 2, max = 3 },
        Reverb  = { name = "Reverberation",          tree = 1, row = 2, max = 5 },
        CoF     = { name = "Call of Flame",          tree = 1, row = 2, max = 3 },
        EDev    = { name = "Elemental Devastation",  tree = 1, row = 2, max = 3 },
        EFocus  = { name = "Elemental Focus",        tree = 1, row = 3, max = 1 },
        EAlac   = { name = "Elemental Alacrity",     tree = 1, row = 3, max = 3 },
        IFN     = { name = "Improved Fire Nova",     tree = 1, row = 4, max = 2 },
        EotS    = { name = "Eye of the Storm",       tree = 1, row = 4, max = 3 },
        CoT     = { name = "Call of Thunder",        tree = 1, row = 4, max = 1, pre = "EAlac" },
        EReach  = { name = "Elemental Reach",        tree = 1, row = 5, max = 2 },
        LO      = { name = "Lightning Overload",     tree = 1, row = 5, max = 3 },
        EBound  = { name = "Earthbound",             tree = 1, row = 5, max = 1 },
        EFury   = { name = "Elemental Fury",         tree = 1, row = 6, max = 5, pre = "CoT" },
        LvB     = { name = "Lava Burst",             tree = 1, row = 7, max = 1, pre = "LO" },
        -- Enhancement
        EGrasp  = { name = "Earth's Grasp",          tree = 2, row = 1, max = 2 },
        TStrike = { name = "Thundering Strikes",     tree = 2, row = 1, max = 5 },
        AK      = { name = "Ancestral Knowledge",    tree = 2, row = 1, max = 5 },
        GTotem  = { name = "Guardian Totems",        tree = 2, row = 2, max = 2 },
        MDex    = { name = "Mental Dexterity",       tree = 2, row = 2, max = 3 },
        IGW     = { name = "Improved Ghost Wolf",    tree = 2, row = 2, max = 2 },
        ILS     = { name = "Improved Lightning Shield", tree = 2, row = 2, max = 3 },
        EWeap   = { name = "Elemental Weapons",      tree = 2, row = 3, max = 3 },
        SFocus  = { name = "Shamanistic Focus",      tree = 2, row = 3, max = 1 },
        Antic   = { name = "Anticipation",           tree = 2, row = 3, max = 3 },
        Tough   = { name = "Toughness",              tree = 2, row = 4, max = 5 },
        Flurry  = { name = "Flurry",                 tree = 2, row = 4, max = 5, pre = "MDex" },
        SS      = { name = "Stormstrike",            tree = 2, row = 4, max = 1 },
        SpWeap  = { name = "Spirit Weapons",         tree = 2, row = 5, max = 1 },
        MQuick  = { name = "Mental Quickness",       tree = 2, row = 5, max = 2 },
        ISS     = { name = "Improved Stormstrike",   tree = 2, row = 5, max = 2, pre = "SS" },
        MW      = { name = "Maelstrom Weapon",       tree = 2, row = 6, max = 5 },
        RotF    = { name = "Rage of the Farseer",    tree = 2, row = 7, max = 1, pre = "MQuick" },
        -- Restoration
        IHW     = { name = "Improved Healing Wave",  tree = 3, row = 1, max = 5 },
        TotF    = { name = "Totemic Focus",          tree = 3, row = 1, max = 5 },
        Mind    = { name = "Mindfulness",            tree = 3, row = 2, max = 3 },
        NGrace  = { name = "Natural Grace",          tree = 3, row = 2, max = 3 },
        TidF    = { name = "Tidal Focus",            tree = 3, row = 2, max = 5 },
        IReinc  = { name = "Improved Reincarnation", tree = 3, row = 2, max = 2 },
        AH      = { name = "Ancestral Healing",      tree = 3, row = 3, max = 3 },
        HFocus  = { name = "Healing Focus",          tree = 3, row = 3, max = 3 },
        WS      = { name = "Water Shield",           tree = 3, row = 3, max = 1 },
        TM      = { name = "Tidal Mastery",          tree = 3, row = 4, max = 5 },
        RT      = { name = "Restorative Totems",     tree = 3, row = 4, max = 5 },
        MTT     = { name = "Mana Tide Totem",        tree = 3, row = 4, max = 1 },
        HWay    = { name = "Healing Way",            tree = 3, row = 5, max = 3 },
        NS      = { name = "Nature's Swiftness",     tree = 3, row = 5, max = 1 },
        Purif   = { name = "Purification",           tree = 3, row = 6, max = 5 },
        Rip     = { name = "Riptide",                tree = 3, row = 7, max = 1, pre = "HWay" },
    },
    trees = { "Elemental", "Enhancement", "Restoration" },
    treeTags = { "|cffff8040E|r", "|cff80c0ffN|r", "|cff60ff60R|r" },
    builds = {
        {
            key = "resto_dungeon", label = "Resto - dungeon healing (levelling)", split = "0/0/51",
            source = "wowforeverbuilds.com Melee Cleave / Melee Burst 5-man Restoration Shaman guides (15-16 Sep 2026)",
            order = "IHW*5 TidF*5 HFocus*3 WS NGrace TotF*2 MTT RT*2 HWay*3 NS RT Purif*5 Rip Mind*3 TM*5 AH*3 RT*2 TotF*3 NGrace*2 IReinc*2",
        },
        {
            key = "enh_solo", label = "Enhancement - solo levelling", split = "0/41/10",
            source = "wowforeverbuilds.com Enhancement Shaman leveling guide 10-60 (15-16 Sep 2026)",
            order = "TStrike*5 MDex*3 AK*2 EWeap*3 SFocus AK Flurry*5 SS ISS*2 MQuick*2 MW*5 RotF AK*2 Antic*3 IHW*5 TidF*5 Tough*5",
        },
        {
            key = "resto_battle", label = "Resto - battle-healer solo levelling (10-40)", split = "0/8/23",
            source = "wowforeverbuilds.com Restoration Shaman leveling guide 10-40 (15-16 Sep 2026)",
            order = "IHW*5 TidF*5 WS HFocus*3 IReinc*2 TotF*5 NS TStrike*5 MDex*3 Mind",
        },
        {
            key = "ele_solo", label = "Elemental - levelling (10-50)", split = "36/5/0", constructed = true,
            source = "wowforeverbuilds.com Elemental Shaman leveling guide 20-50 (15-16 Sep 2026) - reordered to fit the current tree",
            order = "Conv*5 CoF*3 Conc*2 EFocus EAlac*3 Conc CoT Conc*2 EotS*2 LO*3 EotS Reverb EFury*5 LvB TStrike*5 Reverb*3 EReach*2",
        },
        {
            key = "enh_dungeon", label = "Enhancement - dungeon DPS (levelling)", split = "6/45/0",
            source = "wowforeverbuilds.com Melee Burst 5-man Enhancement Shaman guide (15-16 Sep 2026)",
            order = "TStrike*5 MDex*3 ILS*3 EWeap*3 SFocus Flurry*5 SS SpWeap MQuick*2 ISS*2 MW*5 RotF Conc*5 EDev Tough*5 Antic*3 AK*5",
        },
        {
            key = "resto_raid", label = "Resto - raid healing (60)", split = "0/8/43", constructed = true,
            source = "wowforeverbuilds.com Restoration Shaman PvE guide (17 Sep 2026) - order constructed from its priorities",
            order = "IHW*5 TidF*5 Mind*3 WS AH*3 TotF*3 MTT RT*4 HWay*3 NS Purif*5 Rip TM*5 RT TotF*2 TStrike*3 AK*5",
        },
    },
    defaultBuild = "resto_dungeon",
}

TD.SHAMAN.activeTalents = { "LvB", "SS", "RotF", "WS", "MTT", "NS", "Rip" }

-- Vanilla 1.12 levels with Forever changes: Fire Nova is a spell at 12 (Fire Nova
-- Totem gone), Totemic Recall and Call of the Elements at 20, Totemic Projection
-- at 22, Call of the Ancestors at 30, Call of the Spirits at 40.
TD.SHAMAN.trainer = {
    ["Lightning Bolt"] = 1, ["Rockbiter Weapon"] = 1, ["Healing Wave"] = 1,
    ["Earth Shock"] = 4, ["Stoneskin Totem"] = 4, ["Earthbind Totem"] = 6,
    ["Lightning Shield"] = 8, ["Stoneclaw Totem"] = 8,
    ["Flame Shock"] = 10, ["Flametongue Weapon"] = 10, ["Searing Totem"] = 10,
    ["Strength of Earth Totem"] = 10,
    ["Fire Nova"] = 12, ["Purge"] = 12, ["Ancestral Spirit"] = 12,
    ["Cure Poison"] = 16, ["Tremor Totem"] = 18,
    ["Frost Shock"] = 20, ["Frostbrand Weapon"] = 20, ["Ghost Wolf"] = 20,
    ["Healing Stream Totem"] = 20, ["Lesser Healing Wave"] = 20,
    ["Call of the Elements"] = 20, ["Totemic Recall"] = 20,
    ["Totemic Projection"] = 22, ["Water Breathing"] = 22, ["Cure Disease"] = 22,
    ["Poison Cleansing Totem"] = 22, ["Frost Resistance Totem"] = 24,
    ["Far Sight"] = 26, ["Magma Totem"] = 26, ["Mana Spring Totem"] = 26,
    ["Fire Resistance Totem"] = 28, ["Flametongue Totem"] = 28, ["Water Walking"] = 28,
    ["Astral Recall"] = 30, ["Grounding Totem"] = 30, ["Nature Resistance Totem"] = 30,
    ["Reincarnation"] = 30, ["Windfury Weapon"] = 30, ["Call of the Ancestors"] = 30,
    ["Chain Lightning"] = 32, ["Windfury Totem"] = 32, ["Sentry Totem"] = 34,
    ["Windwall Totem"] = 36, ["Disease Cleansing Totem"] = 38,
    ["Chain Heal"] = 40, ["Call of the Spirits"] = 40, ["Grace of Air Totem"] = 42,
}

TD.SHAMAN.sequences = {
    enh = {
        name = "Enhancement levelling",
        keyPress = { "/targetenemy [noharm][dead]", "/startattack" },
        steps = { { "Stormstrike", "enemy" }, { "Flame Shock", "dot" }, { "Earth Shock", "enemy" } },
    },
    ele = {
        name = "Elemental levelling",
        keyPress = { "/targetenemy [noharm][dead]" },
        steps = { { "Flame Shock", "dot" }, { "Lava Burst", "enemy" }, { "Lightning Bolt", "enemy" } },
    },
    resto = {
        name = "Resto levelling",
        keyPress = { "/targetenemy [noharm][dead]" },
        steps = { { "Flame Shock", "dot" }, { "Lightning Bolt", "enemy" } },
    },
}
TD.SHAMAN.buildSequence = {
    resto_dungeon = "resto", enh_solo = "enh", resto_battle = "resto",
    ele_solo = "ele", enh_dungeon = "enh", resto_raid = "resto",
}

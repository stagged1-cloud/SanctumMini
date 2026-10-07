-- Sanctum test suite. Run from the addon folder:  lua5.1 tests/run.lua
-- Part 1: pure Logic tests. Part 2: secure step snippet. Part 3: smoke-load of
-- every file against a mocked WoW API, driving login, test mode, options, goals.

local pass, fail = 0, 0
local function T(name, fn)
    local ok, err = pcall(fn)
    if ok then pass = pass + 1; print("  PASS  " .. name)
    else fail = fail + 1; print("  FAIL  " .. name .. "\n        " .. tostring(err)) end
end
local function eq(a, b, msg)
    if a ~= b then error((msg or "") .. " expected [" .. tostring(b) .. "] got [" .. tostring(a) .. "]", 2) end
end

local ns = {}
assert(loadfile("Data.lua"))("Sanctum", ns)
assert(loadfile("Logic.lua"))("Sanctum", ns)
assert(loadfile("TalentData.lua"))("Sanctum", ns)
local L, D = ns.Logic, ns.Data

local function knownSet(list)
    local s = {}
    for _, n in ipairs(list) do s[n] = true end
    return function(n) return s[n] == true end, s
end

print("== Logic: parsing")
-- T1: priority list splits and trims, ignores empties
T("SplitPriority trims and drops empties", function()
    local r = L.SplitPriority(" Heal | |Lesser Heal|")
    eq(#r, 2); eq(r[1], "Heal"); eq(r[2], "Lesser Heal")
end)
-- T2: non-string input is safe
T("SplitPriority(nil) -> empty", function() eq(#L.SplitPriority(nil), 0) end)
-- T3: CRLF text and blank lines
T("ParseLines handles CRLF and blank lines", function()
    local r = L.ParseLines("a\r\n\r\n  b  \n\nc")
    eq(#r, 3); eq(r[2], "b")
end)

print("== Logic: binding resolution")
-- T4: first known spell in the chain wins (level 16 priest has Heal)
T("ResolveBinding picks first known", function()
    local k = knownSet({ "Lesser Heal", "Heal" })
    local kind, spell, st = L.ResolveBinding("Greater Heal|Heal|Lesser Heal", k)
    eq(kind, "spell"); eq(spell, "Heal"); eq(st, "ok")
end)
-- T5: level 5 priest knows none of the chain except Lesser Heal
T("ResolveBinding falls through to lowest", function()
    local _, spell = L.ResolveBinding("Flash Heal|Lesser Heal", knownSet({ "Lesser Heal" }))
    eq(spell, "Lesser Heal")
end)
-- T6: nothing known -> unknown, no spell
T("ResolveBinding unknown", function()
    local kind, spell, st = L.ResolveBinding("Prayer of Healing", knownSet({}))
    eq(kind, "spell"); eq(spell, nil); eq(st, "unknown")
end)
-- T7: special tokens are case-insensitive
T("ResolveBinding @Target / @MENU", function()
    eq((L.ResolveBinding("@Target", knownSet({}))), "target")
    eq((L.ResolveBinding(" @MENU ", knownSet({}))), "menu")
end)
-- T8: empty / nil
T("ResolveBinding empty -> none", function()
    eq((L.ResolveBinding("", knownSet({}))), "none")
    eq((L.ResolveBinding(nil, knownSet({}))), "none")
end)

print("== Logic: click attributes")
-- T9: priest kit at level 10: attributes map to secure keys
T("BuildClickAttributes priest lvl10", function()
    local k = knownSet({ "Lesser Heal", "Renew", "Power Word: Shield", "Power Word: Fortitude", "Resurrection" })
    local a, report = L.BuildClickAttributes(D.classKits.PRIEST, D.clickSlots, k)
    eq(a["type1"], "spell"); eq(a["spell1"], "Lesser Heal")
    eq(a["type2"], "spell"); eq(a["spell2"], "Renew")
    eq(a["shift-spell2"], "Power Word: Shield")
    eq(a["alt-type1"], "target")
    eq(a["ctrl-type2"], nil, "Dispel Magic not known yet")
    eq(#report, #D.clickSlots)
end)
-- T10: plain left always does something
T("BuildClickAttributes left-click safety net", function()
    local a = L.BuildClickAttributes({ ["1"] = "Unknown Spell" }, D.clickSlots, knownSet({}))
    eq(a["type1"], "target")
end)
-- T11: nil bindings table is tolerated
T("BuildClickAttributes nil bindings", function()
    local a = L.BuildClickAttributes(nil, D.clickSlots, knownSet({}))
    eq(a["type1"], "target")
end)
-- T12: every slot owns exactly its type+spell keys
T("SlotAttributeKeys", function()
    local keys = L.SlotAttributeKeys({ mod = "shift-", button = 2 })
    eq(keys[1], "shift-type2"); eq(keys[2], "shift-spell2")
end)

print("== Logic: dispel")
-- T13: priest with Dispel Magic + Cure Disease
T("DispelTypes priest", function()
    local d = L.DispelTypes(D.dispelSpells, knownSet({ "Dispel Magic", "Cure Disease" }))
    eq(d.Magic, true); eq(d.Disease, true); eq(d.Poison, nil); eq(d.Curse, nil)
end)
-- T14: first dispellable debuff chosen, non-dispellable ignored
T("PickDispel", function()
    local can = { Magic = true }
    eq(L.PickDispel({ { dispelName = "Curse" }, { dispelName = nil }, { dispelName = "Magic" } }, can), "Magic")
    eq(L.PickDispel({ { dispelName = "Poison" } }, can), nil)
    eq(L.PickDispel(nil, can), nil)
end)

print("== Logic: sequence")
-- T15: keyPress + step + post joined per step
T("BuildSequenceMacros joins lines", function()
    local m, e = L.BuildSequenceMacros({ keyPress = { "/tar" }, steps = { "/cast A", " ", "/cast B" }, postMacro = { "/p" } })
    eq(#e, 0); eq(#m, 2); eq(m[1], "/tar\n/cast A\n/p"); eq(m[2], "/tar\n/cast B\n/p")
end)
-- T16: over-length step skipped with error, others kept
T("BuildSequenceMacros macro limit", function()
    local long = "/cast " .. string.rep("x", 1100)
    local m, e = L.BuildSequenceMacros({ steps = { "/cast A", long } })
    eq(#m, 1); eq(#e, 1)
end)
-- T17: empty / invalid
T("BuildSequenceMacros invalid", function()
    local m, e = L.BuildSequenceMacros(nil); eq(#m, 0); eq(#e, 1)
    m, e = L.BuildSequenceMacros({ steps = {} }); eq(#m, 0); eq(#e, 1)
end)
-- T18: default priest sequence fits the limit
T("Default priest sequence builds", function()
    local m, e = L.BuildSequenceMacros(D.defaultSequences.PRIEST)
    eq(#e, 0); eq(#m, 5)
end)


print("== Logic: sequence spell awareness")
-- T: spell extraction handles conditionals, reset=, !, null, ranks, ; alternatives
T("SpellsInMacroLine parses /cast and /castsequence", function()
    local r = L.SpellsInMacroLine("/castsequence [harm,nodead] reset=target Shadow Word: Pain, null")
    eq(#r, 1); eq(r[1], "Shadow Word: Pain")
    r = L.SpellsInMacroLine("/cast [mod:shift,@player] Power Word: Shield; [harm] !Shoot")
    eq(#r, 2); eq(r[1], "Power Word: Shield"); eq(r[2], "Shoot")
    r = L.SpellsInMacroLine("/cast Heal(Rank 2)")
    eq(r[1], "Heal")
    eq(#L.SpellsInMacroLine("/targetenemy [noharm][dead]"), 0)
    eq(#L.SpellsInMacroLine(nil), 0)
end)
-- T: lines with unknown spells are held back and reported
T("FilterSequence holds back unlearned spells", function()
    local known = knownSet({ "Shadow Word: Pain", "Mind Blast" })
    local out, waiting = L.FilterSequence(D.defaultSequences.PRIEST, known)
    eq(#out.steps, 4, "Mind Flay step dropped, Shoot always allowed")
    eq(#out.keyPress, 1, "PW:S keypress dropped")
    eq(table.concat(waiting, ","), "Mind Flay,Power Word: Shield")
    local out2, w2 = L.FilterSequence(D.defaultSequences.PRIEST,
        knownSet({ "Shadow Word: Pain", "Mind Blast", "Mind Flay", "Power Word: Shield" }))
    eq(#out2.steps, 5); eq(#w2, 0)
end)
T("FilterSequence nil-safe", function()
    local out, w = L.FilterSequence(nil, knownSet({}))
    eq(#out.steps, 0); eq(#w, 0)
end)

print("== Logic: talents")
local PT = ns.TalentData.PRIEST
-- T: every shipped build is legal (row gates, prerequisites, max ranks, <= 51 points)
for _, b in ipairs(PT.builds) do
    T("Build legal: " .. b.key, function()
        local pts = L.ExpandBuild(b.order)
        local errs = L.ValidateBuild(pts, PT.talents, 10)
        eq(#errs, 0, table.concat(errs, "; "))
        assert(#pts <= 51)
    end)
end
-- T: split label matches actual points per tree
for _, b in ipairs(PT.builds) do
    T("Build split label: " .. b.key, function()
        local c = { 0, 0, 0 }
        for _, a in ipairs(L.ExpandBuild(b.order)) do c[PT.talents[a].tree] = c[PT.talents[a].tree] + 1 end
        eq(table.concat(c, "/"), b.split)
    end)
end
-- T: validator catches illegal orders
T("ValidateBuild rejects bad orders", function()
    eq(#L.ValidateBuild(L.ExpandBuild("HN"), PT.talents) > 0, true, "row 3 with 0 points")
    eq(#L.ValidateBuild(L.ExpandBuild("Wand*3"), PT.talents) > 0, true, "over max")
    eq(#L.ValidateBuild(L.ExpandBuild("Bogus"), PT.talents) > 0, true, "unknown")
    local s = "TD*5 IPWS*2 SilRes*3 SW"
    eq(#L.ValidateBuild(L.ExpandBuild(s), PT.talents) > 0, true, "Soul Warding needs IPWS 3/3")
end)
-- T: plan at level 15 for the holy dungeon build
T("TalentPlan level 15, no API", function()
    local pts = L.ExpandBuild(PT.builds[1].order)
    local plan = L.TalentPlan(pts, 15, nil, 10)
    eq(plan.pointsNow, 6)
    eq(plan.nextLevel, 16); eq(plan.nextAbbr, "DF"); eq(plan.nextRank, 2)
    eq(plan.rows[1].abbr, "IR"); eq(plan.rows[1].planned, 3); eq(plan.rows[1].status, "done")
    eq(plan.rows[2].abbr, "TF"); eq(plan.rows[2].planned, 2)
    eq(plan.rows[3].abbr, "DF"); eq(plan.rows[3].planned, 1)
    eq(plan.rows[4].status, "future")
    eq(plan.offPlan, nil)
end)
-- T: plan compares against actual ranks
T("TalentPlan with actual ranks", function()
    local pts = L.ExpandBuild(PT.builds[1].order)
    local plan = L.TalentPlan(pts, 15, { IR = 3, TF = 1, ST = 2 }, 10)
    eq(plan.rows[1].status, "done"); eq(plan.rows[2].status, "partial")
    eq(table.concat(plan.offPlan, ","), "ST")
    plan = L.TalentPlan(pts, 15, {}, 10)
    eq(plan.rows[1].status, "missing")
end)
-- T: below 10 and at 60
T("TalentPlan edges", function()
    local pts = L.ExpandBuild(PT.builds[1].order)
    eq(L.TalentPlan(pts, 5, nil).pointsNow, 0)
    eq(L.TalentPlan(pts, 5, nil).nextLevel, 10)
    local p60 = L.TalentPlan(pts, 60, nil)
    eq(p60.pointsNow, 51); eq(p60.nextLevel, nil)
end)

-- T: resize clamps and rounds
T("ClampBarSize", function()
    local w, h = L.ClampBarSize(130.4, 40.6); eq(w, 130); eq(h, 41)
    w, h = L.ClampBarSize(10, 5); eq(w, 60); eq(h, 18)
    w, h = L.ClampBarSize(999, 999); eq(w, 300); eq(h, 80)
    w, h = L.ClampBarSize(nil, nil); eq(w, 60); eq(h, 18)
end)

T("KeyFromInput", function()
    eq(L.KeyFromInput("1", false, false, false), "1")
    eq(L.KeyFromInput("F", true, true, true), "ALT-CTRL-SHIFT-F")
    eq(L.KeyFromInput("LSHIFT", false, false, true), nil)
    eq(L.KeyFromInput("ESCAPE"), "cancel")
    eq(L.KeyFromInput(nil), nil)
end)

print("== Logic: step builder")
-- T: every mode round-trips through BuildStep/ParseStep
T("BuildStep/ParseStep round trip", function()
    for _, m in ipairs(L.STEP_MODES) do
        local line = L.BuildStep("Mind Blast", m.key)
        local sp, mode = L.ParseStep(line)
        eq(sp, "Mind Blast", m.key); eq(mode, m.key)
    end
end)
T("BuildStep exact text", function()
    eq(L.BuildStep("Shadow Word: Pain", "dot"), "/castsequence [harm,nodead] reset=target Shadow Word: Pain, null")
    eq(L.BuildStep("Power Word: Shield", "self"), "/cast [@player] Power Word: Shield")
    eq(L.BuildStep("Renew", "heal"), "/cast [@mouseover,help,nodead][@player] Renew")
    eq(L.BuildStep("Shoot", "enemy"), "/cast [harm,nodead] !Shoot")
    eq(L.BuildStep("  ", "enemy"), nil)
end)
T("ParseStep: wand and custom lines", function()
    local sp, m = L.ParseStep("/cast [harm,nodead] !Shoot"); eq(sp, "Shoot"); eq(m, "enemy")
    eq(L.ParseStep("/startattack"), nil)
    eq(L.ParseStep("/cast [mod:shift] Fade"), nil)
end)
T("DefaultStepMode", function()
    eq(L.DefaultStepMode("Shadow Word: Pain", false), "dot")
    eq(L.DefaultStepMode("Power Word: Shield", true), "self")
    eq(L.DefaultStepMode("Smite", false), "enemy")
end)
T("NextStepMode cycles", function()
    eq(L.NextStepMode("enemy"), "dot"); eq(L.NextStepMode("heal"), "enemy"); eq(L.NextStepMode("bogus"), "enemy")
end)
-- T: the bug Don hit - a wrapped line split in two would be SAID in chat
T("JoinContinuations rejoins split lines", function()
    local r = L.JoinContinuations({ "/castsequence [harm,nodead] reset=target", "Shadow Word: Pain, null", "/cast Mind Blast", "" })
    eq(#r, 2); eq(r[1], "/castsequence [harm,nodead] reset=target Shadow Word: Pain, null")
    eq(#L.JoinContinuations({ "orphan" }), 1)
end)
T("FilterSequence never emits a non-slash line", function()
    local seq = { steps = { "/castsequence [harm,nodead] reset=target", "Shadow Word: Pain, null" } }
    local out = L.FilterSequence(seq, knownSet({ "Shadow Word: Pain" }))
    eq(#out.steps, 1)
    for _, l in ipairs(out.steps) do eq(l:sub(1, 1), "/") end
end)

print("== Logic: spell status")
local function ctxFor(level, known, buildKey)
    local b
    for _, x in ipairs(PT.builds) do if x.key == buildKey then b = x end end
    local active = {}
    for _, a in ipairs(PT.activeTalents) do active[PT.talents[a].name] = a end
    return { level = level, isKnown = knownSet(known), trainer = PT.trainer, activeTalents = active,
             talents = PT.talents, points = L.ExpandBuild(b.order), buildLabel = b.label }
end
-- T: Don's case - level 15, Holy build, Mind Flay in the sequence
T("SpellStatus: talent not in build", function()
    local st = L.SpellStatus("Mind Flay", ctxFor(15, {}, "holy_dungeon"))
    eq(st.state, "talent_notinbuild"); assert(st.text:find("Shadow talent"), st.text)
end)
T("SpellStatus: talent later / due", function()
    local st = L.SpellStatus("Mind Flay", ctxFor(15, {}, "shadow_solo"))
    eq(st.state, "talent_later"); eq(st.level, 22)
    st = L.SpellStatus("Mind Flay", ctxFor(23, {}, "shadow_solo"))
    eq(st.state, "talent_due"); assert(st.text:find("row 3"), st.text)
end)
T("SpellStatus: level vs trainer vs known", function()
    eq(L.SpellStatus("Holy Fire", ctxFor(15, {}, "holy_dungeon")).state, "level")
    eq(L.SpellStatus("Holy Fire", ctxFor(15, {}, "holy_dungeon")).level, 20)
    eq(L.SpellStatus("Heal", ctxFor(17, {}, "holy_dungeon")).state, "trainer")
    eq(L.SpellStatus("Heal", ctxFor(17, { "Heal" }, "holy_dungeon")).state, "known")
    eq(L.SpellStatus("Shoot", ctxFor(5, {}, "holy_dungeon")).state, "known")
    eq(L.SpellStatus("Made Up", ctxFor(5, {}, "holy_dungeon")).state, "unknown")
end)
T("SpellStatusShort labels", function()
    eq(L.SpellStatusShort({ state = "level", level = 20 }), "lvl 20")
    eq(L.SpellStatusShort({ state = "talent_notinbuild" }), "not in build")
end)
-- T: templates drop talent spells the build never takes
T("SequenceFromTemplate per build", function()
    local active = {}
    for _, a in ipairs(PT.activeTalents) do active[PT.talents[a].name] = a end
    local holy = L.SequenceFromTemplate(PT.sequences.shadow, L.ExpandBuild(PT.builds[1].order), active)
    for _, l in ipairs(holy.steps) do assert(not l:find("Mind Flay"), "holy build must not get Mind Flay") end
    local sh = L.SequenceFromTemplate(PT.sequences.shadow, L.ExpandBuild(PT.builds[4].order), active)
    local mf = 0; for _, l in ipairs(sh.steps) do if l:find("Mind Flay") then mf = mf + 1 end end
    eq(mf, 2)
    local disc = L.SequenceFromTemplate(PT.sequences.disc, L.ExpandBuild(PT.builds[2].order), active)
    local pen = false; for _, l in ipairs(disc.steps) do if l:find("Penance") then pen = true end end
    eq(pen, true)
    for _, l in ipairs(sh.steps) do eq(l:sub(1, 1), "/") end
end)
T("Every build maps to a sequence template", function()
    for _, b in ipairs(PT.builds) do assert(PT.sequences[PT.buildSequence[b.key]], b.key) end
end)

T("BuildPriorityMacro: one macro, steps in order", function()
    local m, e = L.BuildPriorityMacro({ keyPress = { "/targetenemy [noharm][dead]" },
        steps = { "/castsequence [harm,nodead] reset=target Shadow Word: Pain, null", "/cast [harm,nodead] Mind Blast", "", "/cast [harm,nodead] !Shoot" } })
    eq(#e, 0); eq(#m, 1)
    eq(m[1], "/targetenemy [noharm][dead]\n/castsequence [harm,nodead] reset=target Shadow Word: Pain, null\n/cast [harm,nodead] Mind Blast\n/cast [harm,nodead] !Shoot")
    m, e = L.BuildPriorityMacro({ steps = {} }); eq(#m, 0); eq(#e, 1)
    local big = {}
    for i = 1, 40 do big[i] = "/cast [harm,nodead] Some Long Spell Name Number " .. i end
    m, e = L.BuildPriorityMacro({ steps = big }); eq(#m, 0); assert(e[1]:find("limit"))
end)

print("== Logic: cast log")
T("LogPush collapses repeated casts and caps size", function()
    local log = {}
    L.LogPush(log, { kind = "press", step = 1 }, 5)
    L.LogPush(log, { kind = "cast", spell = "Shoot" }, 5)
    L.LogPush(log, { kind = "cast", spell = "Shoot" }, 5)
    L.LogPush(log, { kind = "cast", spell = "Shoot" }, 5)
    eq(#log, 2); eq(log[2].count, 3)
    L.LogPush(log, { kind = "fail", spell = "Mind Blast" }, 5)
    L.LogPush(log, { kind = "cast", spell = "Shoot" }, 5)
    eq(#log, 4, "a different entry in between starts a new Shoot line")
    for i = 1, 10 do L.LogPush(log, { kind = "press", step = i }, 5) end
    eq(#log, 5); eq(log[5].step, 10)
end)
T("LogLines newest first", function()
    local log = { { step = 1 }, { step = 2 }, { step = 3 } }
    local o = L.LogLines(log, 2)
    eq(#o, 2); eq(o[1].step, 3); eq(o[2].step, 2)
    eq(#L.LogLines({}, 5), 0)
end)

print("== Logic: secure step snippet (simulated)")
-- T19: the restricted snippet cycles 1..n and wraps
T("Step snippet cycles", function()
    local attrs = { ["sanc-n"] = 3, ["sanc-m1"] = "A", ["sanc-m2"] = "B", ["sanc-m3"] = "C" }
    local self = { GetAttribute = function(_, k) return attrs[k] end, SetAttribute = function(_, k, v) attrs[k] = v end, CallMethod = function(_, m, a) attrs._called = (attrs._called or '') .. m .. a .. ';' end }
    local src = assert(io.open("Sequence.lua")):read("*a")
    local body = src:match("STEP_SNIPPET = %[%[(.-)%]%]")
    local fn = assert(loadstring("local self = ...\n" .. body))
    local seen = {}
    for i = 1, 7 do fn(self); seen[i] = attrs.macrotext end
    eq(table.concat(seen), "ABCABCA")
    assert(attrs._called:find("SanctumOnStep1;SanctumOnStep2;SanctumOnStep3;SanctumOnStep1"), attrs._called)
end)
-- T20: n = 0 does nothing
T("Step snippet with no steps", function()
    local attrs = { ["sanc-n"] = 0 }
    local self = { GetAttribute = function(_, k) return attrs[k] end, SetAttribute = function(_, k, v) attrs[k] = v end, CallMethod = function(_, m, a) attrs._called = (attrs._called or '') .. m .. a .. ';' end }
    local body = assert(io.open("Sequence.lua")):read("*a"):match("STEP_SNIPPET = %[%[(.-)%]%]")
    assert(loadstring("local self = ...\n" .. body))(self)
    eq(attrs.macrotext, nil)
end)

print("== Logic: goals")
local G = D.goals
local function fullGear(req, enchanted)
    local s = {}
    for _, slot in ipairs(G.gearSlots) do
        s[slot.id] = { reqLevel = req, itemLevel = req + 5, durCur = 50, durMax = 50, enchanted = enchanted }
    end
    return s
end
-- T21: fully geared lvl 20 priest, no problems in gear
T("Gear all OK", function()
    -- enchanted: enchants are checked from 15 since 0.5.1
    local sec = L.EvaluateGear({ level = 20, slots = fullGear(18, true) }, G, "PRIEST")
    eq(sec.status, L.OK); eq(#sec.items, 0); eq(sec.checked, #G.gearSlots)
end)
-- T22: empty chest at level 10 is red; empty neck at 10 is fine
T("Gear empty slots respect emptyFrom", function()
    local slots = fullGear(8, false); slots[5] = { empty = true }; slots[2] = { empty = true }
    local sec = L.EvaluateGear({ level = 10, slots = slots }, G, "PRIEST")
    eq(sec.status, L.BAD); eq(#sec.items, 1); assert(sec.items[1].text:find("Chest"))
end)
-- T23: stale thresholds - 10 below amber, 16 below red
T("Gear staleness", function()
    local s = fullGear(30, true)
    s[7] = { reqLevel = 20, durCur = 1, durMax = 1, enchanted = true }  -- legs, 10 below
    s[8] = { reqLevel = 14, durCur = 1, durMax = 1, enchanted = true }  -- feet, 16 below
    local sec = L.EvaluateGear({ level = 30, slots = s }, G, "PRIEST")
    local st = {}
    for _, it in ipairs(sec.items) do st[it.text:match("^(%w+)")] = it.status end
    eq(st.Legs, L.WARN); eq(st.Feet, L.BAD)
end)
-- T24: no reqLevel falls back to ilvl-5
T("EffectiveItemLevel fallback", function()
    eq(L.EffectiveItemLevel({ reqLevel = 0, itemLevel = 25 }), 20)
    eq(L.EffectiveItemLevel({ reqLevel = 12 }), 12)
    eq(L.EffectiveItemLevel({}), nil)
end)
-- T25: enchants only flagged from the configured level
T("Enchant gating", function()
    local a = L.EvaluateGear({ level = 39, slots = fullGear(36, false), enchantFromLevel = 40 }, G, "PRIEST")
    eq(#a.items, 0)
    local b = L.EvaluateGear({ level = 40, slots = fullGear(36, false), enchantFromLevel = 40 }, G, "PRIEST")
    eq(b.status, L.BAD); eq(#b.items, 5, "6 enchantable slots, Hands skipped until 60")
end)
-- E1: the best reachable enchant is named, nil when nothing is reachable yet
T("EnchantFor picks the best tier for the level", function()
    local list = G.enchants["Chest"]
    eq(L.EnchantFor(list, 7), nil)
    eq(L.EnchantFor(list, 8), "Minor Intellect")
    eq(L.EnchantFor(list, 21), "Lesser Intellect")
    eq(L.EnchantFor(list, 22), "Intellect")
    eq(L.EnchantFor(list, 60), "Major Intellect")
    eq(L.EnchantFor(nil, 60), nil)
    eq(L.EnchantFor({}, 60), nil)
end)
-- E2: at 15 the message names the enchant to get, per slot
T("Enchant suggestions at 15", function()
    local sec = L.EvaluateGear({ level = 15, slots = fullGear(12, false), enchantFromLevel = 15 }, G, "PRIEST")
    local t = {}
    for _, it in ipairs(sec.items) do t[it.text:match("^([%w ]+):")] = it.text end
    eq(t.Chest, "Chest: no enchant - get Lesser Intellect")
    eq(t.Back, "Back: no enchant - get Lesser Protection")
    eq(t.Wrist, "Wrist: no enchant - get Minor Spirit")
    eq(t.Feet, "Feet: no enchant - get Minor Stamina")
    eq(t.Hands, nil, "no healer glove enchant before 60")
    eq(t["Main Hand"], nil, "one-hander: nothing worth it before 22")
end)
-- E3: a two-handed weapon (staff) gets its own list and is flagged from 15
T("Two-hand weapon enchant", function()
    local s = fullGear(12, false); s[16].twoHand = true
    local sec = L.EvaluateGear({ level = 15, slots = s, enchantFromLevel = 15 }, G, "PRIEST")
    local found
    for _, it in ipairs(sec.items) do if it.text:find("^Main Hand") then found = it.text end end
    eq(found, "Main Hand: no enchant - get Lesser Intellect")
end)
-- E4: below the configured level nothing is flagged, even with suggestions available
T("Enchant level setting still gates suggestions", function()
    local sec = L.EvaluateGear({ level = 30, slots = fullGear(28, false), enchantFromLevel = 31 }, G, "PRIEST")
    eq(#sec.items, 0)
end)
-- E5: enchanted slots stay quiet; Hands flagged at 60 with the raid source named
T("Enchanted slots OK, Hands at 60", function()
    eq(#L.EvaluateGear({ level = 60, slots = fullGear(58, true), enchantFromLevel = 15 }, G, "PRIEST").items, 0)
    local sec = L.EvaluateGear({ level = 60, slots = fullGear(58, false), enchantFromLevel = 15 }, G, "PRIEST")
    local hands
    for _, it in ipairs(sec.items) do if it.text:find("^Hands") then hands = it.text end end
    eq(hands, "Hands: no enchant - get Healing Power (Ahn'Qiraj)")
end)
-- E6: suggestion data well formed - ascending levels, names present, every enchantable slot covered
T("Enchant table well formed", function()
    eq(G.enchantFromLevel, 15)
    for _, slot in ipairs(G.gearSlots) do
        if slot.enchant then assert(G.enchants[slot.name], "no suggestions for " .. slot.name) end
    end
    for key, list in pairs(G.enchants) do
        local last = 0
        for _, t in ipairs(list) do
            assert(t.lvl >= last and t.lvl <= 60, key .. " levels out of order")
            assert(type(t.name) == "string" and #t.name > 0, key .. " name")
            assert(not t.name:find("\226\128\147") and not t.name:find("\226\128\148"), "dash in " .. t.name)
            last = t.lvl
        end
    end
end)
-- T26: durability thresholds
T("Durability", function()
    local s = fullGear(10, false)
    s[5].durCur, s[5].durMax = 10, 100   -- 10% red
    s[7].durCur, s[7].durMax = 35, 100   -- 35% amber
    local sec = L.EvaluateGear({ level = 10, slots = s }, G, "PRIEST")
    eq(#sec.items, 2); eq(sec.status, L.BAD)
end)
-- T27: wand slot ignored for paladin
T("Wand slot only for wand classes", function()
    local s = fullGear(20, true); s[18] = { empty = true }
    eq(#L.EvaluateGear({ level = 20, slots = s }, G, "PALADIN").items, 0)
    eq(#L.EvaluateGear({ level = 20, slots = s }, G, "PRIEST").items, 1)
end)
-- T28: consumables tiers
T("Consumables best tier ok / lower tier warn / none bad", function()
    local snap = { level = 16, counts = { [1205] = 20, [929] = 5, [858] = 0 } }
    local sec = L.EvaluateConsumables(snap, G, "PRIEST")
    local by = {}
    for _, it in ipairs(sec.items) do by[it.text:match("^([%a ]+):")] = it.status end
    eq(by["Drink"], L.OK)
    eq(by["Healing Potion"], L.OK)
    eq(by["Mana Potion"], L.BAD)           -- none
    snap.counts[1205] = 0; snap.counts[1179] = 25  -- only Ice Cold Milk at 16
    sec = L.EvaluateConsumables(snap, G, "PRIEST")
    for _, it in ipairs(sec.items) do if it.text:find("^Drink") then eq(it.status, L.WARN) end end
end)
-- T29: conjured water counts as the same tier
T("Conjured water counts at its tier", function()
    local sec = L.EvaluateConsumables({ level = 15, counts = { [2136] = 20 } }, G, "PRIEST")
    for _, it in ipairs(sec.items) do if it.text:find("^Drink") then eq(it.status, L.OK) end end
end)
-- T30: live client required level overrides table level
T("Live reqLevel overrides table", function()
    -- pretend Forever moved Melon Juice to level 20: at 16 the best tier is Ice Cold Milk
    local sec = L.EvaluateConsumables({ level = 16, counts = { [1179] = 20 }, itemReqLevel = { [1205] = 20, [2136] = 20 } }, G, "PRIEST")
    for _, it in ipairs(sec.items) do if it.text:find("^Drink") then eq(it.status, L.OK) end end
end)
-- T31: warriors skip drink/mana; below consumablesFrom nothing
T("Consumables class & level gating", function()
    local sec = L.EvaluateConsumables({ level = 20, counts = {} }, G, "WARRIOR")
    for _, it in ipairs(sec.items) do assert(not it.text:find("Drink") and not it.text:find("Mana")) end
    eq(L.EvaluateConsumables({ level = 4, counts = {} }, G, "PRIEST"), nil)
end)
-- T32: self-buffs only for known spells and out of combat
T("Buffs", function()
    local snap = { level = 20, known = { ["Power Word: Fortitude"] = true }, buffs = {} }
    local sec = L.EvaluateBuffs(snap, G, "PRIEST")
    eq(#sec.items, 1); eq(sec.status, L.BAD)
    snap.buffs["Prayer of Fortitude"] = true
    eq(L.EvaluateBuffs(snap, G, "PRIEST").status, L.OK)
    snap.inCombat = true
    eq(L.EvaluateBuffs(snap, G, "PRIEST"), nil)
end)
-- T33: Well Fed only nagged inside instances
T("Well Fed in instance", function()
    local sec = L.EvaluateBuffs({ level = 30, known = {}, buffs = {}, inInstance = true }, G, "PRIEST")
    eq(sec.items[1].status, L.WARN)
    eq(L.EvaluateBuffs({ level = 30, known = {}, buffs = {} }, G, "PRIEST"), nil)
end)
-- T34: reagents and bag space
T("Reagents & bags", function()
    local sec = L.EvaluateReagents({ known = { ["Prayer of Fortitude"] = true }, counts = { [17028] = 4 }, freeSlots = 2 }, G, "PRIEST")
    eq(#sec.items, 2); eq(sec.status, L.WARN)
    eq(L.EvaluateReagents({ known = {}, counts = {}, freeSlots = 10 }, G, "PRIEST"), nil)
end)
-- T35: overall roll-up is the worst section
T("EvaluateGoals overall", function()
    local slots = fullGear(5, false); slots[5] = { empty = true }
    local secs, overall = L.EvaluateGoals({ level = 6, slots = slots, counts = {}, buffs = {}, known = {} }, G, "PRIEST")
    eq(overall, L.BAD); assert(#secs >= 2)
end)

---------------------------------------------------------------------------
print("== Logic: training (0.6.0)")
local TDp = ns.TalentData
local function trainingSnap(level, knownList, cache)
    local k = {}
    for _, n in ipairs(knownList or {}) do k[n] = true end
    return { level = level, known = k,
             training = { levels = TDp.PRIEST.trainer, skip = TDp.PRIEST.trainerSkip, cache = cache } }
end
-- TR1: no trainer visit yet - static rank 1 spells you are high enough for and don't know
T("Training: static rank 1 spells due, plus the visit-trainer nudge", function()
    local sec = L.EvaluateTraining(trainingSnap(8, { "Smite", "Lesser Heal", "Power Word: Fortitude", "Shoot",
        "Shadow Word: Pain", "Power Word: Shield" }), D.goals, "PRIEST")
    eq(sec.title, "Training"); eq(sec.status, L.BAD)
    eq(sec.items[1].text, "Trainer: Fade - level 8")      -- same level sorts by name
    eq(sec.items[2].text, "Trainer: Renew - level 8")
    eq(sec.items[#sec.items].text, "Open your class trainer once to track new ranks")
    eq(sec.items[#sec.items].status, L.WARN)
end)
-- TR2: spells above your level are never listed
T("Training: nothing above your level", function()
    local sec = L.EvaluateTraining(trainingSnap(1, { "Smite", "Lesser Heal", "Power Word: Fortitude", "Shoot" }), D.goals, "PRIEST")
    eq(#sec.items, 1, "only the nudge"); eq(sec.status, L.WARN)
end)
-- TR3: racials (race-only) are skipped in the static check
T("Training: racials are not demanded of every priest", function()
    local sec = L.EvaluateTraining(trainingSnap(10, {}), D.goals, "PRIEST")
    for _, it in ipairs(sec.items) do
        assert(not it.text:find("Starshards") and not it.text:find("Desperate Prayer") and not it.text:find("Divine Grace"), it.text)
    end
end)
-- TR4: with a trainer cache: ranks ready at your level, used and too-high ones left out, cost in the title
T("Training: trainer cache lists ready ranks with cost", function()
    local cache = { services = {
        { name = "Heal", rank = "Rank 2", req = 22, state = "unavailable", cost = 1500 },
        { name = "Renew", rank = "Rank 3", req = 20, state = "available", cost = 1000 },
        { name = "Smite", rank = "Rank 4", req = 22, state = "unavailable", cost = 900 },
        { name = "Lesser Heal", rank = "Rank 3", req = 10, state = "used", cost = 100 },
        { name = "Flash Heal", rank = "Rank 3", req = 28, state = "unavailable", cost = 5000 },
    } }
    local sec = L.EvaluateTraining(trainingSnap(22, {}, cache), D.goals, "PRIEST")
    eq(sec.ready, 3)
    eq(sec.items[1].text, "Trainer: Renew (Rank 3) - level 20")
    eq(sec.items[2].text, "Trainer: Heal (Rank 2) - level 22")
    eq(sec.items[3].text, "Trainer: Smite (Rank 4) - level 22")
    eq(sec.title, "Training (3 ready, 34s)")
    for _, it in ipairs(sec.items) do assert(not it.text:find("Open your class trainer"), "no nudge once cached") end
end)
-- TR5: cache present and nothing due -> green "Nothing new to train"
T("Training: up to date is green", function()
    local cache = { services = { { name = "Heal", rank = "Rank 2", req = 30, state = "unavailable", cost = 1 } } }
    local sec = L.EvaluateTraining(trainingSnap(22, {}, cache), D.goals, "PRIEST")
    eq(sec.status, L.OK); eq(#sec.items, 1); eq(sec.items[1].text, "Nothing new to train")
end)
-- TR6: long lists collapse to "...and N more"
T("Training: more than 6 ready collapses", function()
    local sv = {}
    for i = 1, 9 do sv[i] = { name = "Spell" .. i, rank = "Rank 2", req = 10, state = "available", cost = 0 } end
    local sec = L.EvaluateTraining(trainingSnap(20, {}, { services = sv }), D.goals, "PRIEST")
    eq(#sec.items, 7); eq(sec.items[7].text, "...and 3 more at your trainer")
end)
-- TR7: class quest spells are amber with their own wording, and show even with a cache
T("Training: class quest spells (Druid Bear Form)", function()
    local snap = { level = 10, known = { Wrath = true }, training = { levels = TDp.DRUID.trainer,
        quest = TDp.DRUID.trainerQuest, cache = { services = {} } } }
    local sec = L.EvaluateTraining(snap, D.goals, "DRUID")
    local found
    for _, it in ipairs(sec.items) do if it.text == "Class quest: Bear Form - from level 10" then found = it end end
    assert(found, "bear form quest line"); eq(found.status, L.WARN)
    for _, it in ipairs(sec.items) do assert(not it.text:find("Trainer: Bear Form"), "never sent to the trainer") end
end)
-- TR8: no training data (non-healer) -> no section
T("Training: no data, no section", function()
    eq(L.EvaluateTraining({ level = 10 }, D.goals, "WARRIOR"), nil)
end)
-- TR9: trainer list -> cache keeps class spells only, rejects weapon/profession trainers
T("TrainerCacheFrom keeps class spells, rejects other trainers", function()
    local levels = TDp.PRIEST.trainer
    local c = L.TrainerCacheFrom({
        { name = "Renew", rank = "Rank 3", state = "available", req = 20, cost = 1000 },
        { name = "Mind Flay", rank = "Rank 2", state = "unavailable", req = 28, cost = 0 },  -- ranked talent spell
        { name = "Staves", rank = "", state = "available", req = 1, cost = 1000 },           -- weapon skill
        { name = "Holy", state = "header" },
    }, levels, {})
    eq(#c.services, 2); eq(c.services[1].name, "Renew"); eq(c.services[2].name, "Mind Flay")
    eq(L.TrainerCacheFrom({ { name = "Staves", rank = "", state = "available", req = 1 } }, levels, {}), nil,
        "weapon master is not a class trainer")
    eq(L.TrainerCacheFrom(nil, levels, {}), nil)
end)
-- TR10: money formatting
T("FormatMoney", function()
    eq(L.FormatMoney(0), "0c"); eq(L.FormatMoney(5), "5c"); eq(L.FormatMoney(1500), "15s")
    eq(L.FormatMoney(21005), "2g 10s 5c"); eq(L.FormatMoney(nil), "0c")
end)
-- TR11: the goals panel includes Training right after Gear
T("EvaluateGoals includes Training after Gear", function()
    local snap = trainingSnap(8, {}); snap.slots = fullGear(6, true)
    local sections = L.EvaluateGoals(snap, D.goals, "PRIEST")
    eq(sections[1].title, "Gear"); eq(sections[2].title, "Training")
end)

print("== Logic: buff watch (0.6.0)")
-- BW1: up / missing / time left, first matching aura wins
T("BuffWatchState: up with time left, missing, accept list", function()
    local tracked = {
        { key = "Power Word: Fortitude", accept = { "Power Word: Fortitude", "Prayer of Fortitude" }, icon = 1 },
        { key = "Inner Fire", accept = { "Inner Fire" }, icon = 2 },
        { key = "Well Fed", accept = { "Well Fed" } },
    }
    local auras = { ["Prayer of Fortitude"] = { icon = 9, expirationTime = 1600 }, ["Well Fed"] = { icon = 7, expirationTime = 0 } }
    local st = L.BuffWatchState(tracked, auras, 1000)
    eq(st[1].up, true); eq(st[1].remaining, 600); eq(st[1].icon, 9, "live icon when up")
    eq(st[2].up, false); eq(st[2].icon, 2, "saved icon when missing"); eq(st[2].remaining, nil)
    eq(st[3].up, true); eq(st[3].remaining, nil, "no expiry -> no timer")
end)
-- BW2: weapon imbue uses the weapon enchant, not auras
T("BuffWatchState: weapon imbue", function()
    local tracked = { { key = "Weapon imbue", weapon = true } }
    eq(L.BuffWatchState(tracked, {}, 0, { mainHand = true, mainHandMs = 90000 })[1].remaining, 90)
    eq(L.BuffWatchState(tracked, {}, 0, { mainHand = false })[1].up, false)
    eq(L.BuffWatchState(tracked, {}, 0, nil)[1].up, false, "no weapon info -> missing")
end)
-- BW3: empty / nil inputs are safe
T("BuffWatchState: empty inputs", function()
    eq(#L.BuffWatchState(nil, nil, nil), 0)
    eq(L.BuffWatchState({ { key = "X" } }, nil, nil)[1].up, false, "accept defaults to key")
end)
-- BW4: dropdown rows: learnt class buffs, Well Fed, then current auras, ticks from saved list
T("BuffWatchCandidates: known class buffs, Well Fed, current buffs", function()
    local known = { ["Power Word: Fortitude"] = true, ["Inner Fire"] = true }
    local current = { ["Arcane Intellect"] = 135932, ["Prayer of Fortitude"] = 1, ["Well Fed"] = 2 }
    local tracked = { { key = "Inner Fire" } }
    local rows = L.BuffWatchCandidates(D.buffWatch.PRIEST, known, current, tracked)
    local labels = {}
    for _, r in ipairs(rows) do labels[#labels + 1] = r.label end
    eq(table.concat(labels, ","), "Power Word: Fortitude,Inner Fire,Well Fed,Arcane Intellect",
        "Prayer of Fortitude folded into PW:F, unlearnt buffs hidden")
    eq(rows[2].checked, true); eq(rows[1].checked, false)
    eq(rows[4].icon, 135932)
end)
-- BW5: a tracked buff stays in the list after it falls off you
T("BuffWatchCandidates: tracked aura buff stays listed when gone", function()
    local rows = L.BuffWatchCandidates(D.buffWatch.PRIEST, {}, {}, { { key = "Arcane Intellect", label = "Arcane Intellect" } })
    eq(rows[#rows].key, "Arcane Intellect"); eq(rows[#rows].checked, true)
end)
-- BW6: Shaman imbue entry appears once any imbue is known; Paladin grouped entries
T("BuffWatchCandidates: needs lists and grouped entries", function()
    local rows = L.BuffWatchCandidates(D.buffWatch.SHAMAN, { ["Rockbiter Weapon"] = true }, {}, {})
    eq(rows[1].key, "Weapon imbue"); eq(rows[1].weapon, true)
    local prow = L.BuffWatchCandidates(D.buffWatch.PALADIN, { ["Devotion Aura"] = true, ["Seal of Righteousness"] = true }, {}, {})
    eq(prow[1].label, "Aura (any)"); eq(prow[2].label, "Seal (any)")
end)
-- BW7: time formatting
T("FormatRemaining", function()
    eq(L.FormatRemaining(nil), ""); eq(L.FormatRemaining(0), ""); eq(L.FormatRemaining(45.7), "45s")
    eq(L.FormatRemaining(90), "2m"); eq(L.FormatRemaining(1799), "30m"); eq(L.FormatRemaining(3600), "1h")
end)

print("== Logic: alert panel (0.7.0)")
-- AP1: expiry fallback. A stale aura list (combat read blocked) still lists the buff,
-- but its expiry time has passed, so it counts as gone. Before expiry it is still up.
T("BuffWatchState: expired aura in a stale read counts as gone", function()
    local tracked = { { key = "Inner Fire", accept = { "Inner Fire" } } }
    local stale = { ["Inner Fire"] = { expirationTime = 1010 } }
    eq(L.BuffWatchState(tracked, stale, 1011)[1].up, false, "past expiry")
    eq(L.BuffWatchState(tracked, stale, 1010)[1].up, false, "exactly at expiry")
    local st = L.BuffWatchState(tracked, stale, 1005)[1]
    eq(st.up, true); eq(st.remaining, 5)
    -- no expiry (0 or missing) never times out
    eq(L.BuffWatchState(tracked, { ["Inner Fire"] = { expirationTime = 0 } }, 99999)[1].up, true)
end)
-- AP2: debuff entries read the harmful list only; a buff of the same name does not count
T("BuffWatchState: debuffs read the harmful list", function()
    local tracked = { { key = "Weakened Soul", harmful = true } }
    eq(L.BuffWatchState(tracked, { ["Weakened Soul"] = {} }, 0, nil, {})[1].up, false, "helpful list ignored")
    local st = L.BuffWatchState(tracked, {}, 1000, nil, { ["Weakened Soul"] = { icon = 5, expirationTime = 1015 } })[1]
    eq(st.up, true); eq(st.remaining, 15); eq(st.harmful, true); eq(st.icon, 5)
    eq(L.BuffWatchState(tracked, {}, 0, nil, nil)[1].up, false, "nil harmful list is safe")
end)
-- AP3: modes. Buffs default to the bar; debuffs always use the panel (default "present").
T("AlertMode / IsPanelEntry / DefaultAlertMode", function()
    eq(L.AlertMode({ key = "X" }), nil); eq(L.IsPanelEntry({ key = "X" }), false)
    eq(L.AlertMode({ key = "X", alert = "missing" }), "missing")
    eq(L.AlertMode({ key = "X", alert = "present" }), "present")
    eq(L.AlertMode({ key = "X", alert = "rubbish" }), nil, "unknown mode falls back to bar")
    eq(L.AlertMode({ key = "D", harmful = true }), "present", "debuff with no mode")
    eq(L.AlertMode({ key = "D", harmful = true, alert = "missing" }), "missing")
    eq(L.AlertMode(nil), nil); eq(L.IsPanelEntry(nil), false)
    eq(L.DefaultAlertMode(true), "present"); eq(L.DefaultAlertMode(false), nil)
end)
-- AP4: mode button cycles. Buffs: bar -> gone -> on -> bar. Debuffs never go to the bar.
T("NextAlertMode and labels", function()
    eq(L.NextAlertMode(nil, false), "missing")
    eq(L.NextAlertMode("missing", false), "present")
    eq(L.NextAlertMode("present", false), nil)
    eq(L.NextAlertMode("present", true), "missing")
    eq(L.NextAlertMode("missing", true), "present")
    eq(L.NextAlertMode(nil, true), "present")
    eq(L.AlertModeLabel(nil), "Bar"); eq(L.AlertModeLabel("missing"), "Panel: gone"); eq(L.AlertModeLabel("present"), "Panel: on")
end)
-- AP5: "Panel: gone": alert when missing, amber warning inside the window, hidden otherwise
T("AlertState: missing mode, alert and warning", function()
    local tracked = { { key = "A", alert = "missing" }, { key = "B", alert = "missing" },
                      { key = "C", alert = "missing" }, { key = "D", alert = "missing" }, { key = "Bar" } }
    local states = { { label = "A", up = false }, { label = "B", up = true, remaining = 20 },
                     { label = "C", up = true, remaining = 300 }, { label = "D", up = true },
                     { label = "Bar", up = false } }
    local out = L.AlertState(tracked, states, 30)
    eq(#out, 2, "only A (gone) and B (inside warning window)")
    eq(out[1].key, "A"); eq(out[1].level, "alert"); eq(out[1].id, "+A")
    eq(out[2].key, "B"); eq(out[2].level, "warn"); eq(out[2].remaining, 20)
    eq(#L.AlertState(tracked, states, 0), 1, "warnings off")
    eq(#L.AlertState(tracked, states, nil), 1, "warnings nil = off")
    eq(L.AlertState(tracked, states, 30)[1].key, "A", "bar entry never listed even though missing")
end)
-- AP6: "Panel: on": alert while present (debuffs, procs), nothing when gone, never a warning
T("AlertState: present mode", function()
    local tracked = { { key = "Weakened Soul", harmful = true }, { key = "Clearcasting", alert = "present" } }
    local out = L.AlertState(tracked, { { label = "WS", up = true, remaining = 5 }, { label = "CC", up = false } }, 30)
    eq(#out, 1); eq(out[1].level, "alert", "present + short time is still an alert, not a warning")
    eq(out[1].id, "-Weakened Soul"); eq(out[1].harmful, true)
    out = L.AlertState(tracked, { { up = false }, { up = true } }, 30)
    eq(#out, 1); eq(out[1].key, "Clearcasting")
end)
-- AP7: sound trigger. Quiet on the first check (login), counts only new red alerts.
T("NewAlerts: first check quiet, new alerts counted once", function()
    local a = { { id = "+A", level = "alert" }, { id = "+B", level = "warn" } }
    local n, set = L.NewAlerts(nil, a)
    eq(n, 0, "first check after login is quiet"); eq(set["+A"], true); eq(set["+B"], nil, "warnings never sound")
    n, set = L.NewAlerts(set, a); eq(n, 0, "still alerting, no repeat")
    n, set = L.NewAlerts(set, { { id = "+A", level = "alert" }, { id = "-C", level = "alert" } }); eq(n, 1)
    n, set = L.NewAlerts(set, {}); eq(n, 0)
    n = L.NewAlerts(set, { { id = "+A", level = "alert" } }); eq(n, 1, "comes back after clearing")
    eq((L.NewAlerts(nil, nil)), 0, "nil inputs")
end)
-- AP8b: bar icon size clamp
T("ClampBuffIconSize keeps bar icons between 16 and 44 px", function()
    eq(L.ClampBuffIconSize(nil), 22, "unset -> 0.6.0 size"); eq(L.ClampBuffIconSize(30), 30)
    eq(L.ClampBuffIconSize(4), 16); eq(L.ClampBuffIconSize(500), 44); eq(L.ClampBuffIconSize("x"), 22)
    for _, v in ipairs(L.BUFF_ICON_SIZES) do eq(L.ClampBuffIconSize(v), v, "every choice is in range") end
end)
-- AP8: warning time is 10 to 30 s; older saved values (off, 60) and junk are clamped
T("ClampWarn keeps the warning between 10 and 30 seconds", function()
    eq(table.concat(L.WARN_CHOICES, ","), "10,15,20,25,30")
    eq(L.ClampWarn(15), 15); eq(L.ClampWarn(10), 10); eq(L.ClampWarn(30), 30)
    eq(L.ClampWarn(0), 10, "off from a test build"); eq(L.ClampWarn(60), 30, "60 from a test build")
    eq(L.ClampWarn(nil), 30, "unset -> default"); eq(L.ClampWarn("x"), 30, "junk -> default")
    eq(L.ClampWarn(17.6), 18)
end)
-- AP9: the sound list: eight shipped sounds, the game's raid warning, off; no own-file option
T("Alert sound list and saved-choice fallback", function()
    local keys = {}
    for _, x in ipairs(D.alertSounds) do keys[#keys + 1] = x.key; assert(not x.custom, "no own-file entry") end
    eq(table.concat(keys, ","), "trombone,duck,boing,kazoo,cuckoo,slide,honk,awooga,raid,off")
    eq(L.ValidSound(D.alertSounds, "awooga"), "awooga")
    eq(L.ValidSound(D.alertSounds, "custom"), "trombone", "test build's own-file choice falls back")
    eq(L.ValidSound(D.alertSounds, nil), "trombone"); eq(L.ValidSound(nil, "x"), nil)
end)
-- AP10: what to play for each choice
T("AlertSound resolves file, game sound, off", function()
    local list = D.alertSounds
    local k, v = L.AlertSound(list, "trombone"); eq(k, "file"); eq(v, "Interface\\AddOns\\SanctumMini\\Sounds\\SadTrombone.ogg")
    k, v = L.AlertSound(list, "honk"); eq(k, "file"); eq(v, "Interface\\AddOns\\SanctumMini\\Sounds\\HonkHonk.ogg")
    k, v = L.AlertSound(list, "raid"); eq(k, "kit"); eq(v, 8959)
    eq(L.AlertSound(list, "custom"), nil, "removed option plays nothing")
    eq(L.AlertSound(list, "off"), nil); eq(L.AlertSound(nil, "trombone"), nil)
end)
-- AP11: every shipped sound file exists on disk
T("Shipped alert sounds exist", function()
    for _, s in ipairs(D.alertSounds) do
        if s.file then
            local rel = s.file:gsub("^Interface\\AddOns\\SanctumMini\\", ""):gsub("\\", "/")
            local h = io.open(rel, "rb"); assert(h, "missing " .. rel); h:close()
        end
    end
end)
-- AP13: debuff rows: class list, then ALL, kept tracked, then anything harmful on you now
T("DebuffWatchCandidates", function()
    local tracked = { { key = "Weakened Soul", harmful = true }, { key = "Curse of Agony", harmful = true },
                      { key = "Inner Fire" } }
    local rows = L.DebuffWatchCandidates(D.debuffWatch.PRIEST, D.debuffWatch.ALL, { ["Poison"] = 77, ["Weakened Soul"] = 1 }, tracked)
    local labels = {}
    for _, r in ipairs(rows) do labels[#labels + 1] = r.label; eq(r.harmful, true) end
    eq(table.concat(labels, ","), "Weakened Soul,Resurrection Sickness,Recently Bandaged,Curse of Agony,Poison")
    eq(rows[1].checked, true); eq(rows[2].checked, false); eq(rows[4].checked, true); eq(rows[5].icon, 77)
    eq(#L.DebuffWatchCandidates(nil, nil, nil, nil), 0, "nil inputs")
    -- the buff list never re-adds a tracked debuff as a buff
    local brows = L.BuffWatchCandidates(D.buffWatch.PRIEST, {}, {}, tracked)
    for _, r in ipairs(brows) do assert(r.key ~= "Curse of Agony", "debuff leaked into buff rows") end
end)
-- AP14: invalid inputs never error
T("AlertState: nil and short inputs", function()
    eq(#L.AlertState(nil, nil, 30), 0)
    eq(#L.AlertState({ { key = "A", alert = "missing" } }, {}, 30), 0, "no state for entry")
end)

print("== Logic: talents for every healing class")
local HEALERS = { "PRIEST", "DRUID", "PALADIN", "SHAMAN" }
for _, cls in ipairs(HEALERS) do
    local cd = ns.TalentData[cls]
    -- C1: the class has talent data at all (the planner showed "Priest only" before 0.5.0)
    T(cls .. ": has talent data", function()
        assert(cd, "no TalentData for " .. cls)
        assert(cd.builds and #cd.builds > 0, "no builds")
        eq(#cd.trees, 3)
    end)
    if cd then
        -- C2: every talent sits in a real tree and row, has a sane max, and its prerequisite exists in the same tree
        T(cls .. ": talent table well formed", function()
            local n = 0
            for abbr, t in pairs(cd.talents) do
                n = n + 1
                assert(t.tree >= 1 and t.tree <= 3, abbr .. " tree")
                assert(t.row >= 1 and t.row <= 7, abbr .. " row")
                assert(t.max >= 1 and t.max <= 5, abbr .. " max")
                if t.pre then
                    local p = cd.talents[t.pre]
                    assert(p, abbr .. " prerequisite " .. t.pre .. " missing")
                    eq(p.tree, t.tree, abbr .. " prerequisite in another tree")
                    assert(p.row <= t.row, abbr .. " prerequisite below it")
                end
            end
            assert(n >= 40, "only " .. n .. " talents")
        end)
        -- C3: talent names are unique, so reading spent ranks by name can't mix two talents up
        T(cls .. ": talent names unique", function()
            local seen = {}
            for abbr, t in pairs(cd.talents) do
                assert(not seen[t.name], t.name .. " used by " .. abbr .. " and " .. tostring(seen[t.name]))
                seen[t.name] = abbr
            end
        end)
        -- C4: every build is legal (row gates, maxed prerequisites, max ranks, <= 51 points)
        for _, b in ipairs(cd.builds) do
            T(cls .. " build legal: " .. b.key, function()
                local pts = L.ExpandBuild(b.order)
                local errs = L.ValidateBuild(pts, cd.talents, 10)
                eq(#errs, 0, table.concat(errs, "; "))
                assert(#pts <= 51)
            end)
            -- C5: the split shown in the planner title matches the real points per tree
            T(cls .. " build split: " .. b.key, function()
                local c = { 0, 0, 0 }
                for _, a in ipairs(L.ExpandBuild(b.order)) do c[cd.talents[a].tree] = c[cd.talents[a].tree] + 1 end
                eq(table.concat(c, "/"), b.split)
            end)
            -- C6: published text rules - sourced, no em or en dashes
            T(cls .. " build text: " .. b.key, function()
                assert(b.source and #b.source > 0, "no source")
                for _, f in ipairs({ b.label, b.source }) do
                    assert(not f:find("\226\128\147") and not f:find("\226\128\148"), "dash in: " .. f)
                end
            end)
        end
        -- C7: build keys unique and the default build exists
        T(cls .. ": build keys unique, default exists", function()
            local seen, hasDefault = {}, false
            for _, b in ipairs(cd.builds) do
                assert(not seen[b.key], "duplicate key " .. b.key); seen[b.key] = true
                if b.key == cd.defaultBuild then hasDefault = true end
            end
            eq(hasDefault, true, "defaultBuild " .. tostring(cd.defaultBuild))
        end)
        -- C8: every active talent is a real talent
        T(cls .. ": activeTalents exist", function()
            for _, a in ipairs(cd.activeTalents) do assert(cd.talents[a], a) end
        end)
        -- C9: every build maps to a template, and the template builds within the macro limit
        T(cls .. ": every build has a working sequence", function()
            local active = {}
            for _, a in ipairs(cd.activeTalents) do active[cd.talents[a].name] = a end
            for _, b in ipairs(cd.builds) do
                local tpl = cd.sequences[cd.buildSequence[b.key]]
                assert(tpl, b.key .. " has no sequence template")
                local seq = L.SequenceFromTemplate(tpl, L.ExpandBuild(b.order), active)
                assert(#seq.steps > 0, b.key .. " sequence is empty")
                local _, e = L.BuildSequenceMacros(seq)
                eq(#e, 0, b.key .. ": " .. table.concat(e, "; "))
            end
        end)
        -- C10: trainer table has level-1 spells and nothing past 60
        T(cls .. ": trainer levels sane", function()
            local ones = 0
            for spell, lvl in pairs(cd.trainer) do
                assert(lvl >= 1 and lvl <= 60, spell .. " level " .. lvl)
                if lvl == 1 then ones = ones + 1 end
            end
            assert(ones >= 2, "no level 1 spells")
        end)
    end
    -- C11: first-login default sequence exists for the class and fits the macro limit
    T(cls .. ": default sequence builds", function()
        local seq = D.defaultSequences[cls]
        assert(seq, "no default sequence")
        local m, e = L.BuildSequenceMacros(seq)
        eq(#e, 0, table.concat(e, "; ")); eq(#m, #seq.steps)
    end)
    -- C12: frames track at least one aura for every healer
    T(cls .. ": tracked auras present", function()
        assert(#(D.trackedAuras[cls] or {}) > 0, "no tracked auras")
    end)
end
-- C13: non-Priest classes carry their own tree letters for the planner
T("Tree tags for non-Priest healers", function()
    for _, cls in ipairs({ "DRUID", "PALADIN", "SHAMAN" }) do eq(#ns.TalentData[cls].treeTags, 3, cls) end
end)
-- C14: a level 25 Druid on the default build has Swiftmend planned, Wild Growth still future
T("Druid plan at 25", function()
    local cd = ns.TalentData.DRUID
    local plan = L.TalentPlan(L.ExpandBuild(cd.builds[1].order), 25, nil, 10)
    eq(plan.pointsNow, 16)
    local st = {}
    for _, r in ipairs(plan.rows) do st[r.abbr] = r.status end
    eq(st.Swiftm, "future", "Swiftmend is point 19, not yet planned")
    eq(st.IRejuv, "done"); eq(st.WGrowth, "future")
end)
-- C15: Shaman Riptide is only reachable after Healing Way is maxed
T("Shaman Riptide needs Healing Way 3/3", function()
    local cd = ns.TalentData.SHAMAN
    local bad = "IHW*5 TidF*5 HFocus*3 WS NGrace TotF*2 MTT RT*2 HWay*2 NS RT Purif*5 Rip"
    eq(#L.ValidateBuild(L.ExpandBuild(bad), cd.talents) > 0, true)
end)
-- C16: Paladin seals in templates are once-per-target steps, never spammed every press
T("Paladin seals are dot steps", function()
    for _, tpl in pairs(ns.TalentData.PALADIN.sequences) do
        for _, s in ipairs(tpl.steps) do
            if s[1]:find("^Seal of") then eq(s[2], "dot", s[1]) end
        end
        for _, l in ipairs(tpl.keyPress) do assert(not l:find("Seal of"), "seal in keyPress") end
    end
end)

print("== Smoke: load all files against a mocked WoW API")
---------------------------------------------------------------------------
local function mockEnv()
    local env = setmetatable({}, { __index = _G })
    local events = {}
    local frames = {}
    local function newObj(kind, name)
        local o = { _attrs = {}, _shown = true, _kind = kind, _scripts = {} }
        local mt = {}
        mt.__index = function(t, k)
            local fixed = {
                GetAttribute = function(self, a) return self._attrs[a] end,
                SetAttribute = function(self, a, v) self._attrs[a] = v end,
                IsShown = function(self) return self._shown end,
                Show = function(self) self._shown = true; if self._scripts.OnShow then self._scripts.OnShow(self) end end,
                Hide = function(self) self._shown = false end,
                SetShown = function(self, v) if v then self:Show() else self:Hide() end end,
                GetWidth = function(self) return self._w or 120 end, GetHeight = function(self) return self._h or 30 end,
                SetWidth = function(self, w) self._w = w end,
                SetHeight = function(self, h) self._h = h end,
                -- 6 px per character; wraps when a width is set (0 = unwrapped)
                GetStringWidth = function(self) return #(self._text or "") * 6 end,
                GetStringHeight = function(self)
                    local tw = #(self._text or "") * 6
                    if self._w and self._w > 0 and tw > self._w then return 13 * math.ceil(tw / self._w) end
                    return 13
                end,
                GetFrameLevel = function() return 1 end,
                GetPoint = function() return "CENTER", nil, "CENTER", 0, 0 end,
                GetText = function(self) return self._text or "" end,
                SetText = function(self, v) self._text = v end,
                HasFocus = function() return false end,
                GetChecked = function(self) return self._checked or false end,
                SetChecked = function(self, v) self._checked = v and true or false end,
                SetScript = function(self, s, f) self._scripts[s] = f end,
                GetScript = function(self, s) return self._scripts[s] end,
                GetEffectiveScale = function() return 1 end,
                HookScript = function(self, s, f) self._scripts[s] = f end,
                RegisterEvent = function(self, e) events[e] = self end,
                CreateTexture = function() return newObj("Texture") end,
                CreateFontString = function() return newObj("FontString") end,
            }
            if fixed[k] then return fixed[k] end
            if type(k) == "string" and k:match("^%u") then return function() end end
            return nil
        end
        setmetatable(o, mt)
        if name then env[name] = o end
        frames[#frames + 1] = o
        return o
    end
    env.CreateFrame = function(kind, name) return newObj(kind, name) end
    env.UIParent = newObj("Frame")
    env.GameTooltip = newObj("GameTooltip")
    env.GameTooltip_SetDefaultAnchor = function() end
    env.UISpecialFrames = {}
    env.tinsert = table.insert
    env.SlashCmdList = {}
    env.print = function() end
    env.InCombatLockdown = function() return false end
    env.UnitAffectingCombat = function() return false end
    env.UnitClass = function() return "Priest", "PRIEST" end
    env.UnitLevel = function() return 20 end
    env.UnitExists = function(u) return u == "player" end
    env.UnitName = function() return "Haruspex" end
    env.UnitHealth = function() return 800 end
    env.UnitHealthMax = function() return 1000 end
    env.UnitPowerType = function() return 0 end
    env.UnitPower = function() return 500 end
    env.UnitPowerMax = function() return 1000 end
    env.UnitIsDeadOrGhost = function() return false end
    env.UnitIsGhost = function() return false end
    env.UnitIsConnected = function() return true end
    env.UnitGUID = function(u) return u end
    env.UnitThreatSituation = function() return 0 end
    env.UnitInRange = function() return true, true end
    env.IsInInstance = function() return false, "none" end
    env.GetInventoryItemLink = function(_, slot) if slot == 5 then return "|Hitem:123:0:0|h[Robe]|h" end end
    env.GetInventoryItemDurability = function() return 40, 50 end
    env.GetItemInfo = function() return "x", "y", 2, 22, 17 end
    env.GetItemCount = function() return 3 end
    env.GetContainerNumFreeSlots = function() return 5, 0 end
    env.GetNumSpellTabs = function() return 1 end
    env.GetSpellTabInfo = function() return "General", nil, 0, 3 end
    local book = { "Lesser Heal", "Renew", "Power Word: Fortitude" }
    env.GetSpellBookItemName = function(i) return book[i] end
    env.GetSpellBookItemInfo = function() return "SPELL" end
    env.GetBuildInfo = function() return "1.60.1", "70205", "", 16001 end
    env.RegisterUnitWatch = function() end
    env.UnregisterUnitWatch = function() end
    env.SecureHandlerWrapScript = function() end
    env.ClearOverrideBindings = function() end
    env.SetOverrideBindingClick = function(_, _, key, btn) env._bound = key .. ">" .. btn end
    env.GetCVarBool = function() return false end
    env.C_Timer = { After = function(_, fn) fn() end }
    env.RAID_CLASS_COLORS = { PRIEST = { r = 1, g = 1, b = 1 } }
    env.ChatFontNormal = {}
    env.Minimap = newObj("Frame")
    env.GetCursorPosition = function() return 0, 0 end
    env.IsShiftKeyDown = function() return env._shift end
    env.HideUIPanel = function() end
    env.Settings = { RegisterCanvasLayoutCategory = function() return {} end, RegisterAddOnCategory = function() env._settings = true end }
    env.GetSpellBookItemTexture = function() return "icon" end
    env.IsPassiveSpell = function(i) return i == 99 end
    -- Secret-value simulation: arithmetic / ordering on these raises, like Forever.
    local SECRET_MT = {
        __add = function() error("attempt to perform arithmetic on a secret number value") end,
        __sub = function() error("attempt to perform arithmetic on a secret number value") end,
        __div = function() error("attempt to perform arithmetic on a secret number value") end,
        __mul = function() error("attempt to perform arithmetic on a secret number value") end,
        __lt = function() error("attempt to compare a secret value") end,
        __le = function() error("attempt to compare a secret value") end,
        __concat = function() error("attempt to concatenate a secret value") end,
    }
    env.secret = function(v) return setmetatable({ v = v }, SECRET_MT) end
    env.issecretvalue = function(v) return type(v) == "table" and getmetatable(v) == SECRET_MT end
    env.GetNumTalentTabs = function() return 2 end
    env.GetNumTalents = function() return 1 end
    env.GetTalentInfo = function(tab) if tab == 2 then return "Improved Renew", nil, 1, 2, 3, 3 end return "Wand Specialization", nil, 1, 2, 0, 2 end
    env.IsControlKeyDown = function() return false end
    env.date = os.date
    env.time = os.time
    env.GetTime = function() return 1000.25 end
    env._events = events
    return env
end

local env = mockEnv()
local sns = {}
T("All files load in TOC order", function()
    for line in io.lines((function() for _, f in ipairs({"SanctumMini_Camelot.toc", "Sanctum_Camelot.toc", "Sanctum.toc"}) do local h = io.open(f); if h then h:close(); return f end end end)()) do
        if line:match("%.lua$") then
            local chunk = assert(loadfile(line))
            setfenv(chunk, env)
            chunk("Sanctum", sns)
        end
    end
end)
local function fire(event, ...)
    for _, fn in ipairs(sns.handlers[event] or {}) do fn(event, ...) end
end
env.SanctumDB = { goals = { enchantFromLevel = 20 } }   -- a 0.5.0 user who had set 20
T("ADDON_LOADED creates saved vars with priest kit", function()
    fire("ADDON_LOADED", "Sanctum")
    eq(env.SanctumDB.goals.enchantFromLevel, 15, "0.5.1 lowers enchant checks to 15 once")
    eq(env.SanctumDB.goals.enchant15, true)
    eq(env.SanctumCharDB.bindings["2"], "Renew")
    eq(env.SanctumCharDB.sequence.name, "Priest levelling DPS")
end)
T("PLAYER_LOGIN builds frames, bindings, sequence, goals", function()
    fire("PLAYER_LOGIN")
    eq(#sns.Frames.buttons, 5)
    local b = sns.Frames.buttons[1]
    eq(b:GetAttribute("unit"), "player")
    eq(b:GetAttribute("spell1"), "Lesser Heal")
    eq(b:GetAttribute("spell2"), "Renew")
    eq(b:GetAttribute("shift-spell3"), "Power Word: Fortitude")
    -- mock spellbook has no attack spells: only the !Shoot step is active
    eq(sns.Sequence.count, 1)
    eq(env.SanctumSeqButton:GetAttribute("sanc-n"), 1)
end)
T("Learning a spell re-applies bindings", function()
    env.GetSpellTabInfo = function() return "General", nil, 0, 4 end
    env.GetSpellBookItemName = function(i) return ({ "Lesser Heal", "Renew", "Power Word: Fortitude", "Heal" })[i] end
    fire("SPELLS_CHANGED")
    eq(sns.Frames.buttons[1]:GetAttribute("spell1"), "Heal")
end)
T("Unit events and test mode run", function()
    fire("UNIT_HEALTH", "player"); fire("UNIT_AURA", "player"); fire("GROUP_ROSTER_UPDATE")
    env.SlashCmdList.SANCTUM("test"); env.SlashCmdList.SANCTUM("test")
end)
-- G1: the goals panel widens to fit long lines, caps at 420 and wraps beyond that
T("Goals panel fits its text", function()
    local G2 = sns.Goals
    G2.Draw({ { title = "Consumables", status = 1, items = {
        { text = "Healing Potion: 6, lower tier - upgrade to Healing Potion", status = 1 } } } }, 1)
    local w = G2.frame:GetWidth()
    assert(w > 260 and w <= 420, "width " .. w)
    local fs = G2.frame.lines[2]
    assert(10 + fs:GetStringWidth() + 10 <= w + 1, "line fits inside the panel")
    G2.Draw({ { title = "Gear", status = 2, items = {
        { text = string.rep("x", 120), status = 2 } } } }, 2)
    eq(G2.frame:GetWidth(), 420, "capped")
    assert(G2.frame:GetHeight() >= 8 + 24 + 13 * 2, "wrapped line adds height")
    G2.Draw({ { title = "Gear", status = 0, items = {} } }, 0)
    eq(G2.frame:GetWidth(), 260, "shrinks back")
end)
-- G2: the X, the slash command and the Options tick always agree
T("Goals close button syncs Options checkbox", function()
    env.SlashCmdList.SANCTUM("")   -- open options
    local O = sns.Options
    assert(O.frame and O.frame:IsShown(), "options open")
    local goalsCb = O.frame.checks[5].cb   -- 5th Display option is "Goals panel"
    sns.Goals.SetShown(true)
    eq(goalsCb:GetChecked(), true)
    -- the panel's X
    sns.Goals.frame.closeButton:GetScript("OnClick")()
    eq(env.SanctumDB.goals.shown, false); eq(sns.Goals.frame:IsShown(), false)
    eq(goalsCb:GetChecked(), false, "tick cleared while Options is open")
    -- slash toggle back on updates the tick too
    env.SlashCmdList.SANCTUM("goals")
    eq(sns.Goals.frame:IsShown(), true); eq(goalsCb:GetChecked(), true)
    -- the checkbox setter is explicit, never inverts
    sns.Goals.SetShown(true)
    eq(sns.Goals.frame:IsShown(), true, "setting true twice stays shown")
    sns.Goals.SetShown(false); sns.Goals.SetShown(false)
    eq(sns.Goals.frame:IsShown(), false, "setting false twice stays hidden")
    sns.Goals.SetShown(true)
end)
T("Slash: options, goals, bind, probe, help", function()
    env.SlashCmdList.SANCTUM("")
    env.SlashCmdList.SANCTUM("goals"); env.SlashCmdList.SANCTUM("goals")
    env.SlashCmdList.SANCTUM("bind f")
    eq(env._bound, "F>SanctumSeqButton")
    eq(env.SanctumCharDB.seqKey, "F")
    env.SlashCmdList.SANCTUM("probe"); env.SlashCmdList.SANCTUM("seq"); env.SlashCmdList.SANCTUM("help")
    env.SlashCmdList.SANCTUM("lock"); env.SlashCmdList.SANCTUM("defaults")
end)
T("Combat queue defers protected work", function()
    local inCombat = true
    env.InCombatLockdown = function() return inCombat end
    env.SanctumCharDB.bindings["1"] = "Renew"
    sns.Frames.ApplyBindings()
    eq(sns.Frames.buttons[1]:GetAttribute("spell1"), "Heal", "unchanged in combat")
    inCombat = false
    fire("PLAYER_REGEN_ENABLED")
    eq(sns.Frames.buttons[1]:GetAttribute("spell1"), "Renew", "applied after combat")
end)

T("Spellbook scan builds sorted castable list", function()
    local names = {}
    for _, sp in ipairs(sns.spellList) do names[#names + 1] = sp.name end
    eq(table.concat(names, ","), "Heal,Lesser Heal,Power Word: Fortitude,Renew")
end)
T("Minimap button and Settings entry created", function()
    assert(env.SanctumMinimapButton, "minimap button")
    eq(env._settings, true)
    env.SlashCmdList.SANCTUM("minimap"); eq(env.SanctumDB.minimap.shown, false)
    env.SlashCmdList.SANCTUM("minimap"); eq(env.SanctumDB.minimap.shown, true)
end)
T("Lock/unlock via SetLocked", function()
    env.SlashCmdList.SANCTUM("unlock"); eq(env.SanctumDB.frames.locked, false)
    sns.Frames.SetLocked(true); eq(env.SanctumDB.frames.locked, true)
end)
T("Spell picker: pick, filter, shift-click fallback, clear", function()
    sns.Options.frame:Show()
    local captured
    sns.Options.OpenPicker(env.UIParent, "Left", function(item, shift) captured = { item, shift } end)
    local p = sns.Options.picker
    eq(#p.items, 3 + 4, "3 specials + 4 spells")
    p.filter:SetText("ren"); p:Fill()
    eq(#p.items, 1); eq(p.items[1].value, "Renew")
    p.rows[1]._scripts.OnClick(p.rows[1])
    eq(captured[1].value, "Renew")
    local row = sns.Options.frame.rows[3]
    row.pick({ value = "Heal", spell = true }, false)
    eq(env.SanctumCharDB.bindings["3"], "Heal")
    row.pick({ value = "Lesser Heal", spell = true }, true)
    eq(env.SanctumCharDB.bindings["3"], "Heal|Lesser Heal", "shift appends fallback")
    eq(sns.Frames.buttons[1]:GetAttribute("spell3"), "Heal", "applied to frames")
    row.pick({ value = "@target" }, true)
    eq(env.SanctumCharDB.bindings["3"], "@target", "special replaces even with shift")
    row.pick({ value = "" }, false)
    eq(env.SanctumCharDB.bindings["3"], "")
    eq(sns.Frames.buttons[1]:GetAttribute("type3"), nil, "cleared")
end)
T("Options refresh with picker icons does not error", function()
    sns.Options.Refresh()
end)

T("Secret UnitPower/UnitHealth/range do not error (Forever)", function()
    local errs = {}
    local oldPrint = sns.Print
    sns.Print = function(fmt, ...) errs[#errs + 1] = string.format(fmt, ...) end
    env.UnitPower = function() return env.secret(400) end
    env.UnitHealth = function() return env.secret(700) end
    env.UnitThreatSituation = function() return env.secret(3) end
    env.UnitExists = function(u) return u == "player" or u == "party1" end
    env.UnitInRange = function() return env.secret(true), env.secret(true) end
    env.C_Spell = { IsSpellInRange = function() return env.secret(false) end }
    local b = sns.Frames.buttons[2]
    local alphaSecret
    b.SetAlphaFromBoolean = function(_, v) alphaSecret = v end
    sns.Frames.UpdateUnit(sns.Frames.buttons[1])
    sns.Frames.UpdateUnit(b); sns.Frames.UpdateAuras(b); sns.Frames.UpdateBorder(b); sns.Frames.UpdateRange(b)
    sns.Print = oldPrint
    eq(#errs, 0, table.concat(errs, " | "))
    assert(env.issecretvalue(alphaSecret), "range went through SetAlphaFromBoolean")
    env.C_Spell = nil
end)
T("Talent planner opens, reads talents, cycles builds", function()
    env.SlashCmdList.SANCTUM("talents")
    local f = sns.Talents.frame
    assert(f and f:IsShown())
    local plan = sns.Talents.Plan()
    eq(plan.pointsNow, 11, "level 20 mock")
    eq(plan.rows[1].actual, 3, "Improved Renew read from GetTalentInfo")
    local first = sns.Talents.CurrentBuild().key
    sns.Talents.Refresh()
end)
-- S1: the planner renders for every healing class with its own tree letters,
-- and a non-healer gets the healing-classes message, not "Priest only"
T("Talent planner renders for every healer, explains non-healers", function()
    local f = sns.Talents.frame
    local oldClass, oldBuild = sns.class, sns.cdb.talentBuild
    sns.cdb.talentBuild = nil
    for cls, tag in pairs({ DRUID = "R|r", PALADIN = "H|r", SHAMAN = "R|r" }) do
        sns.class = cls
        sns.Talents.Refresh()
        local b = sns.Talents.CurrentBuild()
        eq(b.key, ns.TalentData[cls].defaultBuild, cls)
        local row = f.rows[1]:GetText()
        assert(row and row:find(tag, 1, true), cls .. " row: " .. tostring(row))
    end
    sns.class = "WARRIOR"
    sns.Talents.Refresh()
    local src = f.source:GetText()
    assert(src:find("healing classes"), src)
    assert(not src:find("Priest only"), src)
    sns.class, sns.cdb.talentBuild = oldClass, oldBuild
    sns.Talents.Refresh()
end)
T("Level-up prints next talent", function()
    local msgs = {}
    local oldPrint = sns.Print
    sns.Print = function(fmt, ...) msgs[#msgs + 1] = string.format(fmt, ...) end
    fire("PLAYER_LEVEL_UP", 16)
    sns.Print = oldPrint
    assert(msgs[1] and msgs[1]:find("Divine Fury 2/5"), tostring(msgs[1]))
end)
T("Sequence holds back unknown spells and announces when learned", function()
    env.SanctumCharDB.sequence = sns.Copy(sns.Data.defaultSequences.PRIEST)
    sns.Sequence.Build()
    local w = table.concat(sns.Sequence.waiting, ",")
    assert(w:find("Mind Flay"), w)
    local msgs = {}
    local oldPrint = sns.Print
    sns.Print = function(fmt, ...) msgs[#msgs + 1] = string.format(fmt, ...) end
    env.GetSpellTabInfo = function() return "General", nil, 0, 5 end
    env.GetSpellBookItemName = function(i) return ({ "Lesser Heal", "Renew", "Power Word: Fortitude", "Heal", "Mind Flay" })[i] end
    fire("SPELLS_CHANGED")
    sns.Print = oldPrint
    local found = false
    for _, m in ipairs(msgs) do if m:find("Mind Flay is now active") then found = true end end
    assert(found, table.concat(msgs, " | "))
end)

T("Blocked aura reads stop quietly", function()
    env.C_UnitAuras = { GetAuraDataByIndex = function() error("GetAuraDataByIndex(): Auras cannot be accessed when secret while tainted by 'Sanctum'") end }
    local n = 0
    sns.C.ForEachAura("party1", "HELPFUL", function() n = n + 1 end)
    eq(n, 0); assert((sns.C.auraBlocked or 0) >= 1)
    env.C_UnitAuras = nil
end)

T("Resize grip drags bar size, blocked in combat", function()
    local g = sns.Frames.grip
    assert(g, "grip exists")
    local cx, cy = 100, 100
    env.GetCursorPosition = function() return cx, cy end
    g._scripts.OnMouseDown(g)
    cx, cy = 150, 50   -- +50 wide, 50 down over 5 bars = +10 high
    g._scripts.OnUpdate(g, 0.2)
    g._scripts.OnMouseUp(g)
    eq(env.SanctumDB.frames.width, 180); eq(env.SanctumDB.frames.height, 50)
    env.InCombatLockdown = function() return true end
    g._scripts.OnMouseDown(g)
    eq(g._scripts.OnUpdate, nil, "no drag in combat")
    env.InCombatLockdown = function() return false end
end)

T("Grip follows the last visible bar (solo)", function()
    local F = sns.Frames
    for i = 2, 5 do F.buttons[i]._shown = false end
    local n, last = F.VisibleBars()
    eq(n, 1); eq(last, F.buttons[1])
    for i = 2, 3 do F.buttons[i]._shown = true end
    n, last = F.VisibleBars()
    eq(n, 3); eq(last, F.buttons[3])
    F.PlaceGrip()
    for i = 4, 5 do F.buttons[i]._shown = true end
end)

T("Step rows: add, cycle target, move, remove", function()
    sns.Options.frame:Show()
    env.SanctumCharDB.sequence.steps = { "/cast [harm,nodead] Mind Blast" }
    sns.Options.RefreshSteps()
    local f = sns.Options.frame
    -- add Power Word: Shield via the + Add step picker
    local onPick
    local orig = sns.Options.OpenPicker
    sns.Options.OpenPicker = function(a, t, fn, ns2) onPick = fn; eq(ns2, true, "no specials for steps"); orig(a, t, fn, ns2) end
    f.stepAdd._scripts.OnClick(f.stepAdd)
    onPick({ value = "Power Word: Shield" })
    sns.Options.OpenPicker = orig
    local st = env.SanctumCharDB.sequence.steps
    eq(#st, 2); eq(st[2], "/cast [@player] Power Word: Shield", "helpful spell defaults to On me")
    -- cycle target mode on row 2: self -> heal
    local row2 = f.stepRows[2]
    eq(row2.modeKey, "self")
    row2.mode._scripts.OnClick(row2.mode)
    eq(st[2], "/cast [@mouseover,help,nodead][@player] Power Word: Shield")
    -- move row 2 up
    local up
    for _, c in ipairs({}) do end
    st[1], st[2] = st[2], st[1]; sns.Options.RefreshSteps()
    eq(f.stepRows[1].spell, "Power Word: Shield")
    -- remove via table and rebuild
    table.remove(st, 1); sns.Options.RefreshSteps()
    eq(#st, 1); eq(f.stepRows[2]._shown, false)
end)

T("Build default loads the right sequence; notices fire once", function()
    env.SanctumCharDB.talentBuild = "holy_dungeon"
    local seq = sns.Talents.DefaultSequence()
    eq(seq.name, "Holy levelling")
    for _, l in ipairs(seq.steps) do assert(not l:find("Mind Flay")) end
    env.SanctumCharDB.sequence = { name = "x", keyPress = {}, steps = { "/cast [harm,nodead] Mind Flay" }, postMacro = {} }
    env.GetSpellTabInfo = function() return "General", nil, 0, 1 end
    env.GetSpellBookItemName = function() return "Lesser Heal" end
    fire("SPELLS_CHANGED")
    local msgs = {}
    local oldPrint = sns.Print
    sns.Print = function(fmt, ...) msgs[#msgs + 1] = string.format(fmt, ...) end
    sns.Talents.ResetNotices()
    sns.Talents.CheckAndNotify(); sns.Talents.CheckAndNotify()
    sns.Print = oldPrint
    local n = 0
    for _, m in ipairs(msgs) do if m:find("Mind Flay is a Shadow talent") then n = n + 1 end end
    eq(n, 1, "told exactly once: " .. table.concat(msgs, " | "))
    sns.Options.RefreshSteps()
    assert(sns.Options.frame.stepRows[1].name:GetText():find("not in build"))
end)

T("Cast log records presses, casts, fails, errors and persists", function()
    env.SanctumCharDB.seqLog = {}
    env.C_Spell = { GetSpellName = function(id) return ({ [589] = "Shadow Word: Pain", [5019] = "Shoot" })[id] end }
    sns.Sequence.stepLabels = { "Shadow Word: Pain", "Shoot" }
    env.SanctumSeqButton.SanctumOnStep(env.SanctumSeqButton, 1)
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 589)
    fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "g", 589)
    env.SanctumSeqButton.SanctumOnStep(env.SanctumSeqButton, 2)
    fire("UI_ERROR_MESSAGE", 51, "Spell is not ready yet.")
    fire("UNIT_SPELLCAST_FAILED", "player", "g", 5019)
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 5019)
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 5019)
    local log = env.SanctumCharDB.seqLog
    eq(#log, 6, "party cast ignored, wand shots collapsed")
    eq(log[1].kind, "press"); eq(log[1].spell, "Shadow Word: Pain")
    eq(log[2].kind, "cast")
    eq(log[4].kind, "error"); eq(log[4].reason, "Spell is not ready yet.")
    eq(log[6].count, 2)
    env.SlashCmdList.SANCTUM("log")
    assert(sns.Sequence.logFrame:IsShown())
    env.C_Spell = nil
end)

T("Priority mode builds a single macro and logs as priority", function()
    env.time = os.time
    env.SanctumCharDB.sequence = { name = "p", keyPress = {}, steps = { "/cast [harm,nodead] !Shoot", "/cast [harm,nodead] !Shoot" }, postMacro = {}, mode = "priority" }
    sns.Sequence.Build()
    eq(env.SanctumSeqButton:GetAttribute("sanc-n"), 1)
    assert(env.SanctumSeqButton:GetAttribute("sanc-m1"):find("Shoot\n/cast"), "both steps in one macro")
    eq(sns.Sequence.stepLabels[1], "priority (first usable)")
    env.SanctumCharDB.sequence.mode = "sequential"
    sns.Sequence.Build()
    eq(env.SanctumSeqButton:GetAttribute("sanc-n"), 2)
end)


print("== Smoke: training scan and buff watch (0.6.0)")
T("Trainer visit is cached and the goals panel lists the ready rank", function()
    env.UnitLevel = function() return 20 end
    local svc = {
        { "Renew", "Rank 3", "available", 20, 1000 },
        { "Heal", "Rank 2", "unavailable", 22, 1500 },
        { "Staves", "", "available", 1, 1000 },
    }
    local filters = { available = 1, unavailable = 0 }
    env.GetNumTrainerServices = function() return #svc end
    env.GetTrainerServiceInfo = function(i)
        local s = svc[i]
        if s[3] == "unavailable" and filters.unavailable == 0 then return nil end
        return s[1], s[2], s[3]
    end
    env.GetTrainerServiceLevelReq = function(i) return svc[i][4] end
    env.GetTrainerServiceCost = function(i) return svc[i][5] end
    env.GetTrainerServiceTypeFilter = function(t) return filters[t] end
    env.SetTrainerServiceTypeFilter = function(t, v) filters[t] = v end
    env.IsTradeskillTrainer = function() return false end
    fire("TRAINER_SHOW")
    local c = env.SanctumCharDB.trainer
    assert(c and c.services, "cached")
    eq(#c.services, 2, "weapon skill dropped"); eq(c.services[2].name, "Heal", "unavailable read too")
    eq(filters.unavailable, 0, "player's filter put back")
    sns.Goals.SetShown(true)
    local snap = sns.Goals.Snapshot()
    local sec = sns.Logic.EvaluateTraining(snap, sns.Data.goals, "PRIEST")
    eq(sec.items[1].text, "Trainer: Renew (Rank 3) - level 20")
    -- the panel draws it
    sns.Goals.Refresh()
    local seen = false
    for _, fs in ipairs(sns.Goals.frame.lines) do if fs:GetText():find("Renew %(Rank 3%)") then seen = true end end
    assert(seen, "Training line drawn")
    -- a profession trainer never overwrites the cache
    env.IsTradeskillTrainer = function() return true end
    svc = {}
    fire("TRAINER_SHOW")
    eq(#env.SanctumCharDB.trainer.services, 2)
    env.IsTradeskillTrainer = function() return false end
end)

T("Buff watch: pick from dropdown, icon shows, flashes when missing", function()
    local BWm = sns.BuffWatch
    assert(BWm.ready and BWm.holder, "buff watch started")
    eq(BWm.holder:IsShown(), false, "nothing tracked, nothing shown")
    -- the aura API: Inner Fire up for 10 minutes
    local auras = { { name = "Inner Fire", icon = 135926, expirationTime = 1600.25 } }
    env.C_UnitAuras = { GetAuraDataByIndex = function(_, i, filter) if filter == "HELPFUL" then return auras[i] end end }
    env.SlashCmdList.SANCTUM("buffs")
    local m = BWm.menu
    assert(m and m:IsShown(), "dropdown open")
    local row
    for _, r in ipairs(m.rows) do if r.row and r.row.key == "Inner Fire" then row = r end end
    assert(row, "Inner Fire offered (currently on you)")
    row:SetChecked(true); row:GetScript("OnClick")(row)
    eq(env.SanctumCharDB.buffWatch.list[1].key, "Inner Fire")
    eq(BWm.holder:IsShown(), true)
    local icon = BWm.icons[1]
    eq(icon:IsShown(), true); eq(icon.state.up, true); eq(icon.time:GetText(), "10m")
    eq(BWm.flashing, false)
    -- it falls off -> missing, flashing
    auras = {}
    fire("UNIT_AURA", "player")
    eq(icon.state.up, false); eq(BWm.flashing, true); eq(icon.time:GetText(), "")
    -- party aura events never touch it
    auras = { { name = "Inner Fire", icon = 135926, expirationTime = 1600.25 } }
    fire("UNIT_AURA", "party1")
    eq(icon.state.up, false, "party1 aura ignored")
    fire("UNIT_AURA", "player")
    eq(icon.state.up, true)
    -- hide while up
    env.SanctumCharDB.buffWatch.hideWhileUp = true
    BWm.Update()
    eq(BWm.holder:IsShown(), false, "all up and hidden")
    env.SanctumCharDB.buffWatch.hideWhileUp = false
    -- combat block: an unreadable aura list keeps the last state instead of flashing
    env.C_UnitAuras = { GetAuraDataByIndex = function() error("Auras cannot be accessed when secret") end }
    BWm.Update()
    eq(icon.state.up, true, "blocked read keeps last known state")
    -- untick (rows re-sort once something is tracked, so find it again)
    for _, r in ipairs(m.rows) do if r.row and r.row.key == "Inner Fire" then row = r end end
    eq(row:GetChecked(), true, "shown ticked")
    row:SetChecked(false); row:GetScript("OnClick")(row)
    eq(#env.SanctumCharDB.buffWatch.list, 0); eq(BWm.holder:IsShown(), false)
    m:Hide()
    env.C_UnitAuras = nil
end)

T("Buff watch sits above your bar, below it when you're at the bottom", function()
    local BWm, Fr = sns.BuffWatch, sns.Frames
    local where
    BWm.holder.SetPoint = function(_, p, rel, rp, x, y) where = { p, rel, rp, x, y } end
    env.SanctumDB.frames.showSelfFirst = true; Fr.Layout()
    eq(where[1], "BOTTOMLEFT"); eq(where[2], Fr.byUnit.player)
    Fr.SetLocked(false); eq(where[5], 19, "clears the drag header when unlocked")
    Fr.SetLocked(true); eq(where[5], 3)
    env.SanctumDB.frames.showSelfFirst = false; Fr.Layout()
    eq(where[1], "TOPLEFT"); eq(where[3], "BOTTOMLEFT")
    env.SanctumDB.frames.showSelfFirst = true; Fr.Layout()
end)

T("Options has a Buff watch button that opens the dropdown", function()
    sns.Options.frame:Show()
    local b = sns.Options.frame.buffWatchButton
    assert(b, "button"); b:GetScript("OnClick")(b)
    assert(sns.BuffWatch.menu:IsShown())
    sns.Options.frame:GetScript("OnHide")()
    eq(sns.BuffWatch.menu:IsShown(), false, "closing Options closes the dropdown")
end)

print("== Smoke: alert panel (0.7.0)")
local function findRow(m, key, harmful)
    for _, r in ipairs(m.rows) do
        if r.row and r.row.key == key and (r.row.harmful and true or false) == (harmful and true or false) then return r end
    end
end
env._sounds = {}
env.PlaySoundFile = function(path) env._sounds[#env._sounds + 1] = path; return true end
env.PlaySound = function(kit) env._sounds[#env._sounds + 1] = kit; return true end

-- SM1: an upgraded character gets a locked, hidden panel: nothing appears until opted in
T("Alert panel: defaults after upgrade, locked and hidden", function()
    local p = env.SanctumCharDB.buffWatch.panel
    eq(p.locked, true); eq(p.size, 44); eq(p.sound, "trombone"); eq(p.warnSecs, 30); eq(p.soundFile, nil, "no own-file setting")
    assert(sns.BuffWatch.panel, "panel built")
    eq(sns.BuffWatch.panel:IsShown(), false)
end)

-- SM2: a buff moved to the panel: first use unlocks for placing, then flashes when it falls off
T("Alert panel: buff on 'Panel: gone' flashes red when it falls off, one sound", function()
    local BWm = sns.BuffWatch
    local p = env.SanctumCharDB.buffWatch.panel
    local auras = { { name = "Inner Fire", icon = 135926, expirationTime = 1600.25 } }
    env.C_UnitAuras = { GetAuraDataByIndex = function(_, i, filter) if filter == "HELPFUL" then return auras[i] end end }
    env.SlashCmdList.SANCTUM("buffs")
    local m = BWm.menu
    local row = findRow(m, "Inner Fire")
    row:SetChecked(true); row:GetScript("OnClick")(row)
    row = findRow(m, "Inner Fire")
    eq(row.mode:IsShown(), true, "mode button shows once ticked"); eq(row.mode.text:GetText(), "Bar")
    eq(BWm.icons[1]:IsShown(), true, "starts on the bar")
    row.mode:GetScript("OnClick")(row.mode)
    eq(env.SanctumCharDB.buffWatch.list[1].alert, "missing")
    eq(findRow(m, "Inner Fire").mode.text:GetText(), "Panel: gone")
    eq(BWm.icons[1]:IsShown(), false, "left the bar")
    eq(p.locked, false, "first use unlocks the panel for placing")
    eq(BWm.panel:IsShown(), true, "unlocked preview shows")
    eq(BWm.panel.icons[1].alert.key, "Inner Fire")
    eq(BWm.panel.icons[1].alert.level, "idle", "buff is up: dimmed in the preview, not flashing")
    eq(BWm.panel.flashing, false)
    -- "Hide icons while the buff is up" applies to the preview too
    m.hideCheck:SetChecked(true); m.hideCheck:GetScript("OnClick")(m.hideCheck)
    eq(env.SanctumCharDB.buffWatch.hideWhileUp, true)
    eq(BWm.panel.icons[1].alert.label, "Alerts show here", "up buff hidden, placeholder kept for dragging")
    m.hideCheck:SetChecked(false); m.hideCheck:GetScript("OnClick")(m.hideCheck)
    eq(BWm.panel.icons[1].alert.key, "Inner Fire", "unticked: back")
    -- lock it from the dropdown
    m.lockCheck:SetChecked(true); m.lockCheck:GetScript("OnClick")(m.lockCheck)
    eq(p.locked, true); eq(p.placed, true)
    eq(BWm.panel:IsShown(), false, "locked and the buff is up: hidden")
    -- it falls off
    env._sounds = {}
    auras = {}
    fire("UNIT_AURA", "player")
    eq(BWm.panel:IsShown(), true, "pops up")
    local icon = BWm.panel.icons[1]
    eq(icon.alert.level, "alert"); eq(icon.glow:IsShown(), true); eq(BWm.panel.flashing, true)
    eq(#env._sounds, 1); eq(env._sounds[1], "Interface\\AddOns\\SanctumMini\\Sounds\\SadTrombone.ogg")
    BWm.PanelTick(0.1)   -- pulse runs without error
    fire("UNIT_AURA", "player")
    eq(#env._sounds, 1, "no repeat while still missing")
    -- recast with 20s left: amber warning inside the 30s window, no flash, no sound
    auras = { { name = "Inner Fire", icon = 135926, expirationTime = 1020.25 } }
    fire("UNIT_AURA", "player")
    eq(BWm.panel:IsShown(), true); eq(icon.alert.level, "warn"); eq(icon.time:GetText(), "20s")
    eq(icon.glow:IsShown(), false); eq(BWm.panel.flashing, false); eq(#env._sounds, 1)
    -- full duration: hidden again
    auras = { { name = "Inner Fire", icon = 135926, expirationTime = 1600.25 } }
    fire("UNIT_AURA", "player")
    eq(BWm.panel:IsShown(), false)
    -- dead: hidden even if missing
    auras = {}
    env.UnitIsDeadOrGhost = function() return true end
    BWm.Update(); eq(BWm.panel:IsShown(), false, "hidden while dead")
    env.UnitIsDeadOrGhost = function() return false end
    BWm.Update(); eq(BWm.panel:IsShown(), true)
    m:Hide()
end)

-- SM3: expiry fallback on the bar: a stale read with a timed-out buff shows missing
T("Expiry fallback: blocked read after the buff timed out shows it missing", function()
    local BWm = sns.BuffWatch
    local list = env.SanctumCharDB.buffWatch.list
    list[1].alert = nil                       -- back to the bar
    local auras = { { name = "Inner Fire", icon = 135926, expirationTime = 1010 } }
    env.C_UnitAuras = { GetAuraDataByIndex = function(_, i, filter) if filter == "HELPFUL" then return auras[i] end end }
    BWm.Update()
    eq(BWm.icons[1].state.up, true)
    env.C_UnitAuras = { GetAuraDataByIndex = function() error("Auras cannot be accessed when secret") end }
    local oldTime = env.GetTime
    env.GetTime = function() return 1011 end
    BWm.Update()
    eq(BWm.icons[1].state.up, false, "timed out while reads were blocked")
    eq(BWm.flashing, true)
    env.GetTime = oldTime
end)

-- SM4: debuffs on you: offered, default 'Panel: on', flash while present
T("Debuff watch: Weakened Soul offered, flashes while on you", function()
    local BWm = sns.BuffWatch
    local harm = {}
    env.C_UnitAuras = { GetAuraDataByIndex = function(_, i, filter) if filter == "HARMFUL" then return harm[i] end end }
    env.SanctumCharDB.buffWatch.list = {}
    BWm.Update()
    env.SlashCmdList.SANCTUM("buffs")
    local m = BWm.menu
    local row = findRow(m, "Weakened Soul", true)
    assert(row, "offered to a priest")
    eq(row.text:GetText(), "|cffff8080Weakened Soul|r", "debuffs shown in red")
    row:SetChecked(true); row:GetScript("OnClick")(row)
    local e = env.SanctumCharDB.buffWatch.list[1]
    eq(e.harmful, true); eq(e.alert, "present")
    eq(findRow(m, "Weakened Soul", true).mode.text:GetText(), "Panel: on")
    eq(BWm.holder:IsShown(), false, "debuffs never on the bar")
    eq(BWm.panel:IsShown(), false, "not on you: hidden")
    env._sounds = {}
    BWm.lastSound = nil   -- the mock clock never moves; clear the 2 s sound throttle
    harm = { { name = "Weakened Soul", icon = 136193, expirationTime = 1015.25 } }
    fire("UNIT_AURA", "player")
    eq(BWm.panel:IsShown(), true); eq(BWm.panel.icons[1].alert.level, "alert"); eq(#env._sounds, 1)
    -- flip to 'Panel: gone' (vice versa)
    row = findRow(m, "Weakened Soul", true)
    row.mode:GetScript("OnClick")(row.mode)
    eq(e.alert, "missing")
    eq(BWm.panel.icons[1].alert.level, "warn", "on you with 15s left: amber, about to drop")
    harm = { { name = "Weakened Soul", icon = 136193, expirationTime = 1100.25 } }
    fire("UNIT_AURA", "player")
    eq(BWm.panel:IsShown(), false, "on you with plenty left: hidden")
    harm = {}
    fire("UNIT_AURA", "player")
    eq(BWm.panel:IsShown(), true)
    row = findRow(m, "Weakened Soul", true)
    row:SetChecked(false); row:GetScript("OnClick")(row)
    eq(#env.SanctumCharDB.buffWatch.list, 0); eq(BWm.panel:IsShown(), false)
    m:Hide()
end)

-- SM5: sound, warning and bar size dropdowns
T("Sound, warning and bar size dropdowns", function()
    local BWm = sns.BuffWatch
    local p = env.SanctumCharDB.buffWatch.panel
    env.SlashCmdList.SANCTUM("buffs")
    local m = BWm.menu
    eq(m.soundButton.text:GetText(), "Sound: Sad Trombone"); eq(m.warnButton.text:GetText(), "Warn: 30s")
    -- sound dropdown: every sound listed by name, picking one plays it
    eq(m.soundList:IsShown(), false)
    m.soundButton:GetScript("OnClick")(m.soundButton); eq(m.soundList:IsShown(), true)
    eq(#m.soundList.items, 10); eq(m.soundList.items[4].text:GetText(), "Kazoo Fanfare")
    eq(m.soundList.items[8].text:GetText(), "Awooga"); eq(m.soundList.items[10].text:GetText(), "Off")
    env._sounds = {}
    local si = m.soundList.items[7]
    si:GetScript("OnClick")(si)
    eq(p.sound, "honk"); eq(m.soundButton.text:GetText(), "Sound: Honk Honk"); eq(m.soundList:IsShown(), false)
    eq(env._sounds[1], "Interface\\AddOns\\SanctumMini\\Sounds\\HonkHonk.ogg", "previewed on pick")
    eq(m.fileBox, nil, "no own-file box")
    -- warning dropdown: 10 to 30 s
    eq(m.warnList:IsShown(), false)
    m.warnButton:GetScript("OnClick")(m.warnButton); eq(m.warnList:IsShown(), true, "dropdown opens")
    eq(#m.warnList.items, 5); eq(m.warnList.items[1].text:GetText(), "10 seconds")
    eq(m.warnList.items[5].text:GetText(), "30 seconds")
    local it = m.warnList.items[2]
    it:GetScript("OnClick")(it)
    eq(p.warnSecs, 15); eq(m.warnList:IsShown(), false, "closes on pick"); eq(m.warnButton.text:GetText(), "Warn: 15s")
    m.warnButton:GetScript("OnClick")(m.warnButton); m.warnButton:GetScript("OnClick")(m.warnButton)
    eq(m.warnList:IsShown(), false, "second click closes")
    p.warnSecs = 30
    -- game sound, off, and the removed /sanc alert sound command does nothing harmful
    env._sounds = {}
    p.sound = "raid"; BWm.PlayAlert(true); eq(env._sounds[1], 8959)
    env.SlashCmdList.SANCTUM("alert sound readme.txt"); eq(p.sound, "raid", "no own-file command")
    p.sound = "off"; env._sounds = {}; BWm.PlayAlert(true); eq(#env._sounds, 0)
    p.sound = "trombone"
    -- bar icon size dropdown: default 22, pick 30, icons follow
    eq(BWm.BarSize(), 22, "0.6.0 size by default"); eq(m.barSizeButton.text:GetText(), "Bar: 22 px")
    m.barSizeButton:GetScript("OnClick")(m.barSizeButton); eq(m.barSizeList:IsShown(), true)
    eq(#m.barSizeList.items, 7); eq(m.barSizeList.items[1].text:GetText(), "16 px")
    local bi = m.barSizeList.items[5]; eq(bi.value, 30)
    bi:GetScript("OnClick")(bi)
    eq(env.SanctumCharDB.buffWatch.barSize, 30); eq(BWm.BarSize(), 30)
    eq(m.barSizeList:IsShown(), false); eq(m.barSizeButton.text:GetText(), "Bar: 30 px")
    env.SanctumCharDB.buffWatch.barSize = 99; eq(BWm.BarSize(), 44, "out of range clamped")
    env.SanctumCharDB.buffWatch.barSize = nil
    m:Hide()
end)

-- SM6: /sanc alert commands and the resize grip limits
T("/sanc alert lock/unlock/reset and resize grip limits", function()
    local BWm = sns.BuffWatch
    local p = env.SanctumCharDB.buffWatch.panel
    env.SlashCmdList.SANCTUM("alert unlock"); eq(p.locked, false)
    eq(BWm.panel:IsShown(), true, "unlocked with nothing set shows a placeholder")
    eq(BWm.panel.icons[1].alert.label, "No alerts set")
    eq(BWm.panel.grip:IsShown(), true)
    local cx = 0
    local oldCursor = env.GetCursorPosition
    env.GetCursorPosition = function() return cx, 0 end
    BWm.panel.grip:GetScript("OnMouseDown")(BWm.panel.grip)
    cx = 30; BWm.PanelTick(0.01); eq(p.size, 74)
    cx = 500; BWm.PanelTick(0.01); eq(p.size, 96, "max")
    cx = -500; BWm.PanelTick(0.01); eq(p.size, 24, "min")
    BWm.panel.grip:GetScript("OnMouseUp")(BWm.panel.grip)
    cx = 200; BWm.PanelTick(0.01); eq(p.size, 24, "grip released")
    env.GetCursorPosition = oldCursor
    env.SlashCmdList.SANCTUM("alert reset"); eq(p.size, 44); eq(p.y, 180)
    env.SlashCmdList.SANCTUM("alert"); eq(p.locked, true, "bare /sanc alert toggles")
    eq(BWm.panel:IsShown(), false); eq(BWm.panel.grip:IsShown(), false)
    env.SlashCmdList.SANCTUM("alert lock"); eq(p.locked, true)
    env.SlashCmdList.SANCTUM("alert nonsense")   -- prints help, no error
    env.C_UnitAuras = nil
end)

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)

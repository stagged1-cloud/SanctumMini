-- Sanctum / Logic.lua
-- Pure functions only: no WoW API calls, no globals written.
-- Everything here is covered by tests/run.lua (plain Lua 5.1).

local ADDON, ns = ...
ns.Logic = ns.Logic or {}
local L = ns.Logic

L.OK, L.WARN, L.BAD = 0, 1, 2

function L.Trim(s)
    if type(s) ~= "string" then return "" end
    s = s:gsub("^%s+", "")
    s = s:gsub("%s+$", "")
    return s
end

-- "A | B|C" -> { "A", "B", "C" }
function L.SplitPriority(value)
    local out = {}
    if type(value) ~= "string" then return out end
    for part in value:gmatch("[^|]+") do
        local p = L.Trim(part)
        if p ~= "" then out[#out + 1] = p end
    end
    return out
end

-- Multi-line text -> list of non-empty trimmed lines.
function L.ParseLines(text)
    local out = {}
    if type(text) ~= "string" then return out end
    text = text:gsub("\r", "")
    for line in (text .. "\n"):gmatch("(.-)\n") do
        local t = L.Trim(line)
        if t ~= "" then out[#out + 1] = t end
    end
    return out
end

-- Resolve one binding value.
-- returns kind ("none"|"target"|"menu"|"spell"), spell (resolved name or nil), status ("ok"|"unknown"|"none")
function L.ResolveBinding(value, isKnown)
    local v = L.Trim(value)
    if v == "" then return "none", nil, "none" end
    local lower = v:lower()
    if lower == "@target" then return "target", nil, "ok" end
    if lower == "@menu" then return "menu", nil, "ok" end
    local list = L.SplitPriority(v)
    for _, name in ipairs(list) do
        if isKnown(name) then return "spell", name, "ok" end
    end
    return "spell", nil, "unknown"
end

-- Every attribute key a slot can own, so stale ones can be cleared.
function L.SlotAttributeKeys(slot)
    return { slot.mod .. "type" .. slot.button, slot.mod .. "spell" .. slot.button }
end

-- bindings: { [slot.key] = value }, slots: Data.clickSlots
-- returns attrs { [attrKey] = value }, report { {slot, value, kind, spell, status} }
function L.BuildClickAttributes(bindings, slots, isKnown)
    local attrs, report = {}, {}
    bindings = bindings or {}
    for _, slot in ipairs(slots) do
        local value = bindings[slot.key]
        local kind, spell, status = L.ResolveBinding(value, isKnown)
        local tKey = slot.mod .. "type" .. slot.button
        if kind == "spell" and spell then
            attrs[tKey] = "spell"
            attrs[slot.mod .. "spell" .. slot.button] = spell
        elseif kind == "target" then
            attrs[tKey] = "target"
        elseif kind == "menu" then
            attrs[tKey] = "togglemenu"
        end
        report[#report + 1] = { slot = slot, value = value, kind = kind, spell = spell, status = status }
    end
    -- Safety net: a plain left click must always do something.
    if not attrs["type1"] then attrs["type1"] = "target" end
    return attrs, report
end

-- Set of dispel types the player can remove, from known spells.
function L.DispelTypes(dispelSpells, isKnown)
    local out = {}
    for spell, types in pairs(dispelSpells) do
        if isKnown(spell) then
            for t in pairs(types) do out[t] = true end
        end
    end
    return out
end

-- Pick the debuff to highlight: first dispellable one wins.
-- debuffs: list of { dispelName = "Magic" | ... }
function L.PickDispel(debuffs, canDispel)
    for _, d in ipairs(debuffs or {}) do
        if d.dispelName and canDispel[d.dispelName] then return d.dispelName end
    end
    return nil
end

L.MACRO_LIMIT = 1023

-- seq = { keyPress = {...}, steps = {...}, postMacro = {...} }
-- returns list of macrotext strings (one per step) and a list of error strings.
function L.BuildSequenceMacros(seq)
    local macros, errors = {}, {}
    if type(seq) ~= "table" or type(seq.steps) ~= "table" then
        errors[#errors + 1] = "sequence has no steps"
        return macros, errors
    end
    for i, step in ipairs(seq.steps) do
        local s = L.Trim(step)
        if s ~= "" then
            local lines = {}
            for _, l in ipairs(seq.keyPress or {}) do
                local t = L.Trim(l); if t ~= "" then lines[#lines + 1] = t end
            end
            lines[#lines + 1] = s
            for _, l in ipairs(seq.postMacro or {}) do
                local t = L.Trim(l); if t ~= "" then lines[#lines + 1] = t end
            end
            local text = table.concat(lines, "\n")
            if #text > L.MACRO_LIMIT then
                errors[#errors + 1] = ("step %d is %d chars (limit %d) - skipped"):format(i, #text, L.MACRO_LIMIT)
            else
                macros[#macros + 1] = text
            end
        end
    end
    if #macros == 0 and #errors == 0 then errors[#errors + 1] = "sequence has no steps" end
    return macros, errors
end

---------------------------------------------------------------------------
-- Goals
---------------------------------------------------------------------------
local WAND_CLASSES = { PRIEST = true, MAGE = true, WARLOCK = true }
local NO_MANA = { WARRIOR = true, ROGUE = true }

local function worst(a, b) if b > a then return b end return a end

local function tierLevel(tier, snap)
    local live = snap.itemReqLevel and snap.itemReqLevel[tier.id]
    if live and live > 0 then return live end
    return tier.lvl
end

-- Effective "level" of a worn item: its required level, or ilvl-5 when it has none.
function L.EffectiveItemLevel(s)
    if s.reqLevel and s.reqLevel > 0 then return s.reqLevel end
    if s.itemLevel and s.itemLevel > 0 then return math.max(1, s.itemLevel - 5) end
    return nil
end

function L.EvaluateGear(snap, G, class)
    local items, status = {}, L.OK
    local level = snap.level
    local checked = 0
    for _, slot in ipairs(G.gearSlots) do
        if not (slot.id == 18 and not WAND_CLASSES[class]) then
            checked = checked + 1
            local s = snap.slots and snap.slots[slot.id]
            local st, msgs = L.OK, {}
            if not s or s.empty then
                if level >= slot.emptyFrom then st = L.BAD; msgs[#msgs + 1] = "empty" end
            else
                local eff = L.EffectiveItemLevel(s)
                if eff then
                    local gap = level - eff
                    if gap >= G.staleBad then st = worst(st, L.BAD); msgs[#msgs + 1] = ("lvl %d item - replace"):format(eff)
                    elseif gap >= G.staleWarn then st = worst(st, L.WARN); msgs[#msgs + 1] = ("lvl %d item - aging"):format(eff) end
                end
                if s.durMax and s.durMax > 0 and s.durCur then
                    local pct = s.durCur / s.durMax
                    if pct <= G.durBad then st = worst(st, L.BAD); msgs[#msgs + 1] = ("durability %d%%"):format(pct * 100)
                    elseif pct <= G.durWarn then st = worst(st, L.WARN); msgs[#msgs + 1] = ("durability %d%%"):format(pct * 100) end
                end
                if slot.enchant and level >= (snap.enchantFromLevel or G.enchantFromLevel) and not s.enchanted then
                    -- With a suggestion list, only flag once something on it is reachable at this level.
                    local list = L.EnchantList(G, slot, s)
                    local pick = L.EnchantFor(list, level)
                    if not list then
                        st = worst(st, L.BAD); msgs[#msgs + 1] = "no enchant"
                    elseif pick then
                        st = worst(st, L.BAD); msgs[#msgs + 1] = "no enchant - get " .. pick
                    end
                end
            end
            if st ~= L.OK then
                items[#items + 1] = { text = slot.name .. ": " .. table.concat(msgs, ", "), status = st }
                status = worst(status, st)
            end
        end
    end
    return { title = "Gear", status = status, items = items, compact = true, checked = checked }
end

-- Suggestion list for a gear slot (two-handers have their own), or nil.
function L.EnchantList(G, slot, s)
    local e = G and G.enchants
    if not e then return nil end
    if slot.id == 16 and s and s.twoHand then return e["Two-Hand"] end
    return e[slot.name]
end

-- Best enchant on the list available at this level, or nil.
function L.EnchantFor(list, level)
    local best
    for _, t in ipairs(list or {}) do
        if level >= t.lvl and (not best or t.lvl >= best.lvl) then best = t end
    end
    return best and best.name
end

function L.EvaluateConsumables(snap, G, class)
    local items, status = {}, L.OK
    local level = snap.level
    if level < G.consumablesFrom then return nil end
    for _, c in ipairs(G.consumables) do
        local skip = (c.from and level < c.from)
            or ((c.label == "Mana Potion" or c.label == "Drink") and NO_MANA[class])
        if not skip then
            local bestLvl, bestName = nil, nil
            for _, t in ipairs(c.tiers) do
                local tl = tierLevel(t, snap)
                if tl <= level and (not bestLvl or tl > bestLvl) then bestLvl, bestName = tl, t.name end
            end
            if bestLvl then
                local countBest, countAny = 0, 0
                for _, t in ipairs(c.tiers) do
                    local tl = tierLevel(t, snap)
                    local n = (snap.counts and snap.counts[t.id]) or 0
                    if tl <= level then countAny = countAny + n end
                    if tl == bestLvl then countBest = countBest + n end
                end
                local st, text
                if countBest >= c.min then
                    st, text = L.OK, ("%s: %d"):format(c.label, countBest)
                elseif countAny >= c.min then
                    st, text = L.WARN, ("%s: %d, lower tier - upgrade to %s"):format(c.label, countAny, bestName)
                elseif countAny > 0 then
                    st, text = L.BAD, ("%s: only %d (want %d) - %s"):format(c.label, countAny, c.min, bestName)
                else
                    st, text = L.BAD, ("%s: none - get %s"):format(c.label, bestName)
                end
                items[#items + 1] = { text = text, status = st }
                status = worst(status, st)
            end
        end
    end
    if #items == 0 then return nil end
    return { title = "Consumables", status = status, items = items }
end

function L.EvaluateBuffs(snap, G, class)
    local items, status = {}, L.OK
    if snap.inCombat then return nil end
    local list = G.selfBuffs[class] or {}
    for _, b in ipairs(list) do
        if snap.known and snap.known[b.spell] then
            local has = false
            for _, a in ipairs(b.accept) do if snap.buffs and snap.buffs[a] then has = true end end
            local st = has and L.OK or L.BAD
            items[#items + 1] = { text = b.spell .. (has and ": up" or ": missing"), status = st }
            status = worst(status, st)
        end
    end
    if snap.inInstance and snap.level >= 10 then
        local has = snap.buffs and snap.buffs["Well Fed"]
        local st = has and L.OK or L.WARN
        items[#items + 1] = { text = "Well Fed" .. (has and ": up" or ": not active"), status = st }
        status = worst(status, st)
    end
    if #items == 0 then return nil end
    return { title = "Buffs", status = status, items = items }
end

function L.EvaluateReagents(snap, G, class)
    local items, status = {}, L.OK
    for _, r in ipairs(G.reagents[class] or {}) do
        if snap.known and snap.known[r.spell] then
            local n = 0
            for _, id in ipairs(r.ids) do n = n + ((snap.counts and snap.counts[id]) or 0) end
            local st = (n >= r.min and L.OK) or (n > 0 and L.WARN) or L.BAD
            items[#items + 1] = { text = ("%s: %d"):format(r.label, n), status = st }
            status = worst(status, st)
        end
    end
    if snap.freeSlots and snap.freeSlots < G.minFreeBagSlots then
        items[#items + 1] = { text = ("Bag space: %d free"):format(snap.freeSlots), status = L.WARN }
        status = worst(status, L.WARN)
    end
    if #items == 0 then return nil end
    return { title = "Reagents & bags", status = status, items = items }
end

-- Training: what you can learn now.
-- snap.training = {
--   levels = { [spell] = level }  rank-1 trainer levels (TalentData),
--   skip   = { [spell] = true }   racials (not every race gets them),
--   quest  = { [spell] = true }   learned from a class quest, not the trainer,
--   cache  = { services = { { name, rank, req, state, cost } } } from the last trainer visit,
-- }
-- With a trainer cache, the cache is the source of truth for trainer spells and ranks.
-- Without one, rank 1 spells come from the static levels and a one-off nudge asks you
-- to open the trainer so higher ranks can be tracked.
L.TRAINING_MAX_LINES = 6

function L.EvaluateTraining(snap, G, class)
    local tr = snap.training
    if not tr or not tr.levels then return nil end
    local level, known = snap.level or 1, snap.known or {}
    local ready, quests, cost = {}, {}, 0
    local cache = tr.cache and tr.cache.services
    if cache then
        for _, s in ipairs(cache) do
            local req = tonumber(s.req) or 0
            local trained = s.state == "used" or ((s.rank == nil or s.rank == "") and known[s.name])
            if not trained and req <= level and s.name then
                ready[#ready + 1] = { name = s.name, rank = s.rank, req = req }
                cost = cost + (tonumber(s.cost) or 0)
            end
        end
    end
    for spell, lvl in pairs(tr.levels) do
        if lvl <= level and not known[spell] and not (tr.skip and tr.skip[spell]) then
            if tr.quest and tr.quest[spell] then
                quests[#quests + 1] = { name = spell, req = lvl }
            elseif not cache then
                ready[#ready + 1] = { name = spell, req = lvl }
            end
        end
    end
    local function byLevel(a, b)
        if a.req ~= b.req then return a.req < b.req end
        if a.name ~= b.name then return a.name < b.name end
        return (a.rank or "") < (b.rank or "")
    end
    table.sort(ready, byLevel); table.sort(quests, byLevel)

    local items, status = {}, L.OK
    local shown = 0
    for _, r in ipairs(ready) do
        shown = shown + 1
        if shown <= L.TRAINING_MAX_LINES then
            local rank = (r.rank and r.rank ~= "") and (" (" .. r.rank .. ")") or ""
            items[#items + 1] = { text = ("Trainer: %s%s - level %d"):format(r.name, rank, r.req), status = L.BAD }
        end
    end
    if #ready > L.TRAINING_MAX_LINES then
        items[#items + 1] = { text = ("...and %d more at your trainer"):format(#ready - L.TRAINING_MAX_LINES), status = L.BAD }
    end
    if #ready > 0 then status = L.BAD end
    for _, q in ipairs(quests) do
        items[#items + 1] = { text = ("Class quest: %s - from level %d"):format(q.name, q.req), status = L.WARN }
        status = worst(status, L.WARN)
    end
    if not cache then
        items[#items + 1] = { text = "Open your class trainer once to track new ranks", status = L.WARN }
        status = worst(status, L.WARN)
    elseif #items == 0 then
        items[#items + 1] = { text = "Nothing new to train", status = L.OK }
    end
    local title = "Training"
    if #ready > 0 and cost > 0 then title = ("Training (%d ready, %s)"):format(#ready, L.FormatMoney(cost)) end
    return { title = title, status = status, items = items, cost = cost, ready = #ready }
end

-- Copper -> "1g 20s 5c" (zero parts dropped).
function L.FormatMoney(copper)
    copper = math.floor(tonumber(copper) or 0)
    if copper <= 0 then return "0c" end
    local g, sv, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if sv > 0 then parts[#parts + 1] = sv .. "s" end
    if c > 0 then parts[#parts + 1] = c .. "c" end
    return table.concat(parts, " ")
end

-- Trainer service list -> cache entries. services = { { name, rank, state, req, cost } }
-- as read from the trainer window. Keeps class spells only: names the static trainer
-- table knows, spells already in the spellbook, or anything with a rank.
-- Returns nil when nothing looks like a class spell (weapon master, profession trainer).
function L.TrainerCacheFrom(services, levels, known)
    local out, classLike = {}, false
    for _, s in ipairs(services or {}) do
        if s.name and s.state ~= "header" then
            local isRank = type(s.rank) == "string" and s.rank:find("%d") ~= nil
            local inTable = levels and levels[s.name] ~= nil
            if inTable then classLike = true end
            if inTable or isRank or (known and known[s.name]) then
                out[#out + 1] = { name = s.name, rank = (s.rank ~= "" and s.rank) or nil, state = s.state,
                                  req = tonumber(s.req) or 0, cost = tonumber(s.cost) or 0 }
            end
        end
    end
    if not classLike then return nil end
    return { services = out }
end

---------------------------------------------------------------------------
-- Buff watch (self only)
---------------------------------------------------------------------------
-- Seconds -> short label: 1h, 12m, 45s.
function L.FormatRemaining(sec)
    if type(sec) ~= "number" or sec <= 0 then return "" end
    if sec >= 3600 then return ("%dh"):format(math.floor(sec / 3600 + 0.5)) end
    if sec >= 60 then return ("%dm"):format(math.floor(sec / 60 + 0.5)) end
    return ("%ds"):format(math.floor(sec))
end

-- tracked = { { key, label, accept = {names}, weapon = bool, icon } }
-- auras   = { [name] = { icon, expirationTime, duration } } (your helpful auras)
-- weapon  = { mainHand = bool, mainHandMs = number } (temporary weapon enchant)
-- Returns { { key, label, icon, up, remaining } } in tracked order.
function L.BuffWatchState(tracked, auras, now, weapon)
    local out = {}
    auras = auras or {}
    for _, t in ipairs(tracked or {}) do
        local st = { key = t.key, label = t.label or t.key, icon = t.icon, up = false }
        if t.weapon then
            st.up = weapon and weapon.mainHand and true or false
            if st.up and weapon.mainHandMs then st.remaining = weapon.mainHandMs / 1000 end
        else
            for _, name in ipairs(t.accept or { t.key }) do
                local a = auras[name]
                if a then
                    st.up = true
                    st.icon = a.icon or st.icon
                    local exp = tonumber(a.expirationTime)
                    if exp and exp > 0 and now then st.remaining = math.max(0, exp - now) end
                    break
                end
            end
        end
        out[#out + 1] = st
    end
    return out
end

-- Rows for the Buff watch dropdown.
-- classList = D.buffWatch[class]; known = set of spell names; current = { [name] = icon }
-- tracked = saved list. Class buffs show once you know any spell that casts them
-- (or when already tracked); then Well Fed; then anything currently on you.
-- Returns { { key, label, accept, weapon, icon, checked } }.
function L.BuffWatchCandidates(classList, known, current, tracked)
    local isTracked = {}
    for _, t in ipairs(tracked or {}) do isTracked[t.key] = true end
    local rows, covered = {}, {}
    local function add(e)
        if covered[e.key] then return end
        e.checked = isTracked[e.key] or false
        rows[#rows + 1] = e
        covered[e.key] = true
        for _, n in ipairs(e.accept or {}) do covered[n] = true end
    end
    for _, e in ipairs(classList or {}) do
        local learnt = false
        for _, n in ipairs(e.needs or e.accept or {}) do if known and known[n] then learnt = true end end
        if learnt or isTracked[e.key] then
            add({ key = e.key, label = e.label or e.key, accept = e.accept, weapon = e.weapon, icon = e.icon })
        end
    end
    add({ key = "Well Fed", label = "Well Fed", accept = { "Well Fed" } })
    -- Tracked entries that came from "currently on you" stay listed after they fall off.
    for _, t in ipairs(tracked or {}) do
        if not covered[t.key] then add({ key = t.key, label = t.label or t.key, accept = t.accept or { t.key },
                                         weapon = t.weapon, icon = t.icon }) end
    end
    local names = {}
    for name in pairs(current or {}) do if not covered[name] then names[#names + 1] = name end end
    table.sort(names)
    for _, name in ipairs(names) do
        local icon = current[name]
        add({ key = name, label = name, accept = { name }, icon = icon ~= true and icon or nil })
    end
    return rows
end

-- Returns ordered list of sections plus overall status.
function L.EvaluateGoals(snap, G, class)
    local sections, overall = {}, L.OK
    local fns = { L.EvaluateGear, L.EvaluateTraining, L.EvaluateConsumables, L.EvaluateBuffs, L.EvaluateReagents }
    for _, fn in ipairs(fns) do
        local sec = fn(snap, G, class)
        if sec then
            sections[#sections + 1] = sec
            overall = worst(overall, sec.status)
        end
    end
    return sections, overall
end

---------------------------------------------------------------------------
-- Sequence spell awareness
---------------------------------------------------------------------------
-- Spells that are always usable even if a spellbook scan misses them.
L.ALWAYS_KNOWN = { ["Shoot"] = true, ["Attack"] = true, ["Auto Shot"] = true }

-- Spell names referenced by a /cast or /castsequence line.
function L.SpellsInMacroLine(line)
    local out = {}
    if type(line) ~= "string" then return out end
    for sub in (line .. "\n"):gmatch("(.-)\n") do
        local cmd, rest = sub:match("^%s*/(%S+)%s*(.*)$")
        cmd = cmd and cmd:lower()
        if cmd == "cast" or cmd == "castsequence" then
            for clause in (rest .. ";"):gmatch("([^;]*);") do
                clause = (clause:gsub("%b[]", ""))
                clause = (clause:gsub("reset=%S+", ""))
                for part in clause:gmatch("[^,]+") do
                    local n = L.Trim(part)
                    n = (n:gsub("^!", ""))
                    n = L.Trim((n:gsub("%(.-%)%s*$", "")))
                    if n ~= "" and n:lower() ~= "null" then out[#out + 1] = n end
                end
            end
        end
    end
    return out
end

-- Drops lines that reference spells you don't know yet. Returns the filtered
-- sequence plus a sorted list of the spells it is waiting for.
function L.FilterSequence(seq, isKnown)
    local waitingSet = {}
    local function ok(line)
        local good = true
        for _, n in ipairs(L.SpellsInMacroLine(line)) do
            if not (L.ALWAYS_KNOWN[n] or isKnown(n)) then waitingSet[n] = true; good = false end
        end
        return good
    end
    local function filter(list)
        local o = {}
        for _, l in ipairs(list or {}) do if ok(l) then o[#o + 1] = l end end
        return o
    end
    local J = L.JoinContinuations
    local out = { name = seq and seq.name, keyPress = filter(J(seq and seq.keyPress)),
                  steps = filter(J(seq and seq.steps)), postMacro = filter(J(seq and seq.postMacro)) }
    local waiting = {}
    for n in pairs(waitingSet) do waiting[#waiting + 1] = n end
    table.sort(waiting)
    return out, waiting
end

---------------------------------------------------------------------------
-- Talent plans
---------------------------------------------------------------------------
-- "Wand*2 ST*5 MF" -> { "Wand", "Wand", "ST", "ST", ... } (one entry per point)
function L.ExpandBuild(str)
    local pts = {}
    for tok in (str or ""):gmatch("%S+") do
        local n, k = tok:match("^([^*]+)%*?(%d*)$")
        for _ = 1, tonumber(k) or 1 do pts[#pts + 1] = n end
    end
    return pts
end

-- talents: { [abbr] = { tree=, row=, max=, pre= } }. Returns list of errors.
function L.ValidateBuild(points, talents, startLevel)
    local errs, ranks, spent = {}, {}, {}
    startLevel = startLevel or 10
    for i, a in ipairs(points) do
        local t = talents[a]
        local lvl = startLevel + i - 1
        if not t then
            errs[#errs + 1] = ("L%d unknown talent %s"):format(lvl, a)
        else
            local inTree = spent[t.tree] or 0
            if inTree < 5 * (t.row - 1) then errs[#errs + 1] = ("L%d %s row %d needs %d points in tree"):format(lvl, a, t.row, 5 * (t.row - 1)) end
            if t.pre and (ranks[t.pre] or 0) < talents[t.pre].max then errs[#errs + 1] = ("L%d %s needs %s maxed"):format(lvl, a, t.pre) end
            if (ranks[a] or 0) >= t.max then errs[#errs + 1] = ("L%d %s over max rank"):format(lvl, a) end
            ranks[a] = (ranks[a] or 0) + 1
            spent[t.tree] = inTree + 1
        end
    end
    if #points > 51 then errs[#errs + 1] = ("%d points (max 51)"):format(#points) end
    return errs
end

-- Plan state at a level.
-- actual: { [abbr] = rank } or nil when the talent API is unavailable.
-- Returns { rows = { {abbr, planned (by now), total, actual, firstLevel, status} },
--           pointsNow, nextLevel, nextAbbr, nextRank }
-- status: "done" | "missing" | "partial" | "future"
function L.TalentPlan(points, level, actual, startLevel)
    startLevel = startLevel or 10
    local pointsNow = math.max(0, math.min(#points, level - startLevel + 1))
    local order, rowsBy = {}, {}
    for i, a in ipairs(points) do
        local r = rowsBy[a]
        if not r then
            r = { abbr = a, planned = 0, total = 0, firstLevel = startLevel + i - 1 }
            rowsBy[a] = r
            order[#order + 1] = r
        end
        r.total = r.total + 1
        if i <= pointsNow then r.planned = r.planned + 1 end
    end
    for _, r in ipairs(order) do
        r.actual = actual and (actual[r.abbr] or 0) or nil
        if r.planned == 0 then r.status = "future"
        elseif r.actual == nil then r.status = "done"
        elseif r.actual >= r.planned then r.status = "done"
        elseif r.actual > 0 then r.status = "partial"
        else r.status = "missing" end
    end
    local plan = { rows = order, pointsNow = pointsNow }
    local nxt = pointsNow + 1
    if points[nxt] then
        plan.nextLevel = startLevel + nxt - 1
        plan.nextAbbr = points[nxt]
        local rank = 0
        for i = 1, nxt do if points[i] == points[nxt] then rank = rank + 1 end end
        plan.nextRank = rank
    end
    -- Points the player has spent off-plan (only when actual ranks are known).
    if actual then
        local offPlan = {}
        for a, rk in pairs(actual) do
            local planned = rowsBy[a] and rowsBy[a].planned or 0
            if rk > planned then offPlan[#offPlan + 1] = a end
        end
        table.sort(offPlan)
        plan.offPlan = offPlan
    end
    return plan
end

-- Bar size limits for the resize grip.
L.BAR_W_MIN, L.BAR_W_MAX, L.BAR_H_MIN, L.BAR_H_MAX = 60, 300, 18, 80
function L.ClampBarSize(w, h)
    w = math.floor((w or 0) + 0.5)
    h = math.floor((h or 0) + 0.5)
    w = math.max(L.BAR_W_MIN, math.min(L.BAR_W_MAX, w))
    h = math.max(L.BAR_H_MIN, math.min(L.BAR_H_MAX, h))
    return w, h
end

-- Key capture for the sequence binding. Returns a binding string such as
-- "SHIFT-F" or "1", "cancel" for Escape, or nil for a bare modifier press.
local MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
                        LMETA = true, RMETA = true, UNKNOWN = true }
function L.KeyFromInput(key, alt, ctrl, shift)
    if type(key) ~= "string" or key == "" or MODIFIER_KEYS[key] then return nil end
    if key == "ESCAPE" then return "cancel" end
    return (alt and "ALT-" or "") .. (ctrl and "CTRL-" or "") .. (shift and "SHIFT-" or "") .. key
end

---------------------------------------------------------------------------
-- Sequence step builder (used by the step picker rows)
---------------------------------------------------------------------------
L.STEP_MODES = {
    { key = "enemy", label = "On enemy" },
    { key = "dot",   label = "Enemy, once" },
    { key = "self",  label = "On me" },
    { key = "heal",  label = "Mouseover/me" },
}
-- Damage-over-time spells: default to "once per target" so they aren't recast every loop.
L.DOT_SPELLS = { ["Shadow Word: Pain"] = true, ["Devouring Plague"] = true, ["Hex of Weakness"] = true,
                 ["Vampiric Touch"] = true, ["Corruption"] = true, ["Curse of Agony"] = true,
                 ["Immolate"] = true, ["Moonfire"] = true, ["Insect Swarm"] = true, ["Serpent Sting"] = true }

function L.BuildStep(spell, mode)
    spell = L.Trim(spell)
    if spell == "" then return nil end
    if mode == "dot" then return ("/castsequence [harm,nodead] reset=target %s, null"):format(spell) end
    if mode == "self" then return "/cast [@player] " .. spell end
    if mode == "heal" then return "/cast [@mouseover,help,nodead][@player] " .. spell end
    -- "!" stops a repeat press toggling auto-repeat (wand) off.
    if spell == "Shoot" then spell = "!Shoot" end
    return "/cast [harm,nodead] " .. spell
end

-- Recognises lines the builder wrote. Returns spell, mode or nil (custom line).
function L.ParseStep(line)
    line = L.Trim(line)
    local s = line:match("^/castsequence %[harm,nodead%] reset=target (.-), null$")
    if s then return s, "dot" end
    s = line:match("^/cast %[@mouseover,help,nodead%]%[@player%] (.+)$")
    if s then return s, "heal" end
    s = line:match("^/cast %[@player%] (.+)$")
    if s then return s, "self" end
    s = line:match("^/cast %[harm,nodead%] (.+)$")
    if s then return (s:gsub("^!", "")), "enemy" end
    return nil
end

function L.DefaultStepMode(spell, helpful)
    if L.DOT_SPELLS[spell] then return "dot" end
    if helpful then return "self" end
    return "enemy"
end

function L.NextStepMode(mode)
    for i, m in ipairs(L.STEP_MODES) do
        if m.key == mode then return L.STEP_MODES[i % #L.STEP_MODES + 1].key end
    end
    return L.STEP_MODES[1].key
end

function L.StepModeLabel(mode)
    for _, m in ipairs(L.STEP_MODES) do if m.key == mode then return m.label end end
    return "Custom"
end

-- A macro line that doesn't start with "/" or "#" would be *said in chat*.
-- Treat it as a wrapped continuation of the previous line.
function L.JoinContinuations(lines)
    local out = {}
    for _, l in ipairs(lines or {}) do
        local t = L.Trim(l)
        if t ~= "" then
            local c = t:sub(1, 1)
            if c ~= "/" and c ~= "#" and #out > 0 then
                out[#out] = out[#out] .. " " .. t
            else
                out[#out + 1] = t
            end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Why isn't a spell usable yet? (level, trainer, talent)
---------------------------------------------------------------------------
-- Level at which a build first takes a talent, or nil.
function L.BuildLevelOf(points, abbr, startLevel)
    startLevel = startLevel or 10
    for i, a in ipairs(points or {}) do if a == abbr then return startLevel + i - 1 end end
    return nil
end

-- ctx = { level, isKnown(fn), trainer = {name=lvl}, activeTalents = {name=abbr},
--         talents = TalentData talents, points = expanded build, buildLabel }
-- Returns { state, text, level, abbr }
--   known | level (not high enough) | trainer (go train) | talent_later |
--   talent_due (spend the point) | talent_notinbuild | unknown
function L.SpellStatus(spell, ctx)
    if ctx.isKnown(spell) or L.ALWAYS_KNOWN[spell] then return { state = "known", text = "" } end
    local abbr = ctx.activeTalents and ctx.activeTalents[spell]
    if abbr then
        local t = ctx.talents[abbr]
        local treeName = ({ "Discipline", "Holy", "Shadow" })[t.tree] or "?"
        local at = L.BuildLevelOf(ctx.points, abbr, 10)
        if not at then
            return { state = "talent_notinbuild", abbr = abbr,
                text = ("%s is a %s talent your build (%s) never takes - remove this step or pick a build that has it"):format(
                    spell, treeName, ctx.buildLabel or "?") }
        end
        if ctx.level >= at then
            return { state = "talent_due", abbr = abbr, level = at,
                text = ("Spend a talent point: %s (%s, row %d) - your build takes it at level %d"):format(
                    spell, treeName, t.row, at) }
        end
        return { state = "talent_later", abbr = abbr, level = at,
            text = ("%s talent - your build takes it at level %d"):format(spell, at) }
    end
    local lvl = ctx.trainer and ctx.trainer[spell]
    if lvl then
        if ctx.level >= lvl then
            return { state = "trainer", level = lvl, text = ("Train %s at your class trainer (available from level %d)"):format(spell, lvl) }
        end
        return { state = "level", level = lvl, text = ("%s is learned at level %d"):format(spell, lvl) }
    end
    return { state = "unknown", text = spell .. " is not in your spellbook" }
end

-- Short label for a greyed step row.
function L.SpellStatusShort(st)
    if st.state == "level" then return "lvl " .. st.level end
    if st.state == "trainer" then return "train it" end
    if st.state == "talent_later" then return "talent @" .. st.level end
    if st.state == "talent_due" then return "spend talent" end
    if st.state == "talent_notinbuild" then return "not in build" end
    if st.state == "unknown" then return "unknown" end
    return ""
end

-- Builds a sequence from a template, dropping steps whose talent spell the
-- build never takes.
function L.SequenceFromTemplate(tpl, points, activeTalents)
    local inBuild = {}
    for _, a in ipairs(points or {}) do inBuild[a] = true end
    local steps = {}
    for _, s in ipairs(tpl.steps) do
        local abbr = activeTalents and activeTalents[s[1]]
        if not abbr or inBuild[abbr] then steps[#steps + 1] = L.BuildStep(s[1], s[2]) end
    end
    local kp = {}
    for _, l in ipairs(tpl.keyPress or {}) do kp[#kp + 1] = l end
    return { name = tpl.name, keyPress = kp, steps = steps, postMacro = {} }
end

---------------------------------------------------------------------------
-- Cast log ring buffer (oldest first). Repeated successful casts of the same
-- spell in a row (wand shots) collapse into one entry with a count.
---------------------------------------------------------------------------
function L.LogPush(log, entry, max)
    local last = log[#log]
    if entry.kind == "cast" and last and last.kind == "cast" and last.spell == entry.spell then
        last.count = (last.count or 1) + 1
        last.time = entry.time
        return log
    end
    log[#log + 1] = entry
    while #log > (max or 80) do table.remove(log, 1) end
    return log
end

-- Newest first, at most n entries.
function L.LogLines(log, n)
    local out = {}
    for i = #log, math.max(1, #log - n + 1), -1 do out[#out + 1] = log[i] end
    return out
end

-- Priority mode: every step goes into ONE macro, top to bottom. On each press
-- WoW tries the lines in order; a line that can't cast (cooldown, no mana,
-- castsequence already on "null") falls through to the next, so the first
-- usable spell fires. Returns { macro } and errors.
function L.BuildPriorityMacro(seq)
    local lines = {}
    local function add(list)
        for _, l in ipairs(list or {}) do
            local t = L.Trim(l); if t ~= "" then lines[#lines + 1] = t end
        end
    end
    add(seq and seq.keyPress); add(seq and seq.steps); add(seq and seq.postMacro)
    local hasStep = false
    for _, l in ipairs((seq and seq.steps) or {}) do if L.Trim(l) ~= "" then hasStep = true end end
    if not hasStep then return {}, { "sequence has no steps" } end
    local text = table.concat(lines, "\n")
    if #text > L.MACRO_LIMIT then
        return {}, { ("priority macro is %d chars (limit %d) - remove a step"):format(#text, L.MACRO_LIMIT) }
    end
    return { text }, {}
end

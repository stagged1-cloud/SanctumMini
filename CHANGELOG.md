# Changelog

## [0.7.0] - 2026-10-07 (Beta, WoW: Forever 1.60.1)

- Alert panel: a big, moveable, resizable, lockable panel for the buffs you care about most. In the Buff watch dropdown each ticked entry has a mode button: Bar (the small icon, as before), Panel: gone (flashes red when it is NOT on you) or Panel: on (flashes red while it IS on you)
- Debuffs on you can now be tracked (shown in red in the dropdown): Weakened Soul (Priest), Forbearance (Paladin), Resurrection Sickness, Recently Bandaged, and anything harmful currently on you. Debuffs always use the panel
- Amber warning before a Panel: gone buff runs out (pick 10, 15, 20, 25 or 30 seconds from a dropdown; default 30) so you can recast before it drops
- Bar icon size: pick 16 to 44 px from the Bar size dropdown next to the hide tick (default 22, as before)
- "Hide icons while the buff is up" also applies to the unlocked alert panel preview, and its label is now clickable as well as the box
- Alert sounds, played once when an alert starts, picked from the Sound dropdown (each plays when picked): Sad Trombone, Panic Duck, Boing Bonk, Kazoo Fanfare, Cuckoo Clock, Slide Whistle, Honk Honk, Awooga, the game's raid warning, or off. Restart the game (not just /reload) after updating so it loads the new sound files
- The panel is locked and hidden until you first move something to it, then unlocks so you can place it. /sanc alert locks or unlocks it; /sanc alert reset puts it back in the middle; /sanc alert test plays the sound
- Buff watch now treats a buff as gone once its timer has run out, even while Forever blocks reading auras in combat (the bar icon used to sit at 0s until combat ended). A buff removed early in combat (charges used up, dispelled) still shows from the next readable update
- Test suite: 263 tests

## [0.6.0] - 2026-10-06 (Beta, WoW: Forever 1.60.1)

- Goals panel: new Training section. Lists spells you can learn now ("Trainer: Renew - level 8") straight away, and once you have opened your class trainer it also tracks every new rank and its level, with the total cost in the heading
- Class quest spells (Druid Bear Form and Aquatic Form, Paladin Redemption) are flagged as quests, not trainer visits; race-only Priest spells are never asked for
- Buff watch: pick self buffs from a dropdown (Options > Buff watch, or /sanc buffs). Icons sit on your own bar, show time left while up and flash red when a buff is missing or falls off. Offers your class buffs (Paladin auras, blessings and seals as "any"; Shaman main-hand imbue), Well Fed, and anything currently on you. Optional: hide icons while the buff is up
- Buff watch keeps the last known state when Forever blocks reading auras in combat, so icons never flash falsely
- Test suite: 243 tests

## [0.5.1] - 2026-10-06 (Beta, WoW: Forever 1.60.1)

- Goals panel widens to fit its text (up to 420 px) and wraps anything longer, so lines no longer run off the edge
- Closing the goals panel with its X now clears the Options tick straight away; the tick and the panel can no longer get out of step
- Enchant suggestions: a missing enchant now names the best healer enchant for your level (Forever names, e.g. Lesser Intellect chest, Lesser Healing Power bracers, Revelation weapon)
- Enchant checks start at level 15 (was 40). Existing settings above 15 are lowered once on upgrade; change it back in Options if you prefer
- Slots with nothing worth enchanting yet are skipped: gloves until 60, one-handed weapons until 22. Staves get their own list
- Options explains the enchant setting under the level box
- Test suite: 221 tests

## [0.5.0] - 2026-10-05 (Beta, WoW: Forever 1.60.1)

All four healing classes are now fully supported.

- Talent planner for Druid, Paladin and Shaman: full Forever talent trees, six builds each (dungeon and raid healing, solo levelling, hybrids), next point on level-up and off-plan warnings
- Each class gets its own tree letters in the planner
- Sequence templates per build: Feral and Balance (Druid), Ret, Holy and Prot (Paladin), Enhancement, Elemental and Resto (Shaman)
- First-login default sequences for Druid, Paladin and Shaman, replacing the empty /startattack sequence
- Frame indicators: Wild Growth (Druid), Light's Vigil and Forbearance (Paladin), Riptide and Ancestral Fortitude (Shaman)
- Non-healers opening the planner now see which classes it covers, instead of "Priest only"
- Test suite: 213 tests, including legality checks on every shipped build for all four classes

Known: talent data is datamined beta data (client 1.60.1.70009 to 70205). Several guide builds predate the 24 Sep beta update, which removed Crusade, Improved Holy Strike and King of the Jungle; those builds were adapted and are marked in the planner.

## [0.4.3] - 2026-10-05 (Beta, WoW: Forever 1.60.1)

- Cast log hint text tidied. No behaviour change

## [0.4.2] - 2026-10-05 (Beta, WoW: Forever 1.60.1)

First public build, published as **Sanctum Mini** (addon folder `SanctumMini`).

- Own party frames (player + party1-4) with click-casting and class kits for Priest, Druid, Paladin and Shaman
- Dispellable debuff and tracked buff indicators
- GSE-style sequence button with KeyPress/PostMacro, priority mode, key binding and persistent cast log
- Talent planner with recommended WoW: Forever Priest builds and level-up prompts
- Per-level goals checklist (gear, enchants, consumables, buff food, reagents)
- Minimap button, options window, test mode, `/sanc probe` diagnostic
- Headless test suite (97 tests)

Known: item IDs are vanilla 1.12 references, unverified on Forever; required levels self-correct from the client when cached.

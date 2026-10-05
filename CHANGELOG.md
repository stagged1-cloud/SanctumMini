# Changelog

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

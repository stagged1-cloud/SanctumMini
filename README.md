# Sanctum Mini

Healer party frames with click-casting, a GSE-style sequence button, a talent planner and a per-level goals checklist. Built for **WoW: Forever** (Interface 16001, levels 5-60). Supports all four healing classes: Priest, Druid, Paladin and Shaman.

> Beta. WoW: Forever is in beta and so is this. Spell, item and talent data are researched against build 1.60.1 and may shift between patches.

## Features

- **Own party frames** - player + party1-4 as secure unit buttons. Health, mana, dispellable debuffs and tracked buffs. Click-cast any mouse button / modifier combination. Nothing protected is touched in combat.
- **Sequence button** - GSE-style stepping macro (KeyPress / steps / PostMacro). Steps advance in a secure snippet, so it works in combat. Priority mode for a single smart macro. Bind a key with `/sanc bind F` or use `/click SanctumSeqButton`.
- **Cast log** - every press, cast, fail and error, persisted between sessions (`/sanc log`).
- **Talent planner** - recommended Forever builds for Priest, Druid, Paladin and Shaman, what you should have at your level, what you actually have, and the next point printed on every level-up.
- **Goals checklist** - per-level gear, enchants, consumables, buff food and reagents; anything missing or wrong shows in red. From level 15 (configurable) a missing enchant names the best healer enchant for your level, e.g. "Wrist: no enchant - get Minor Spirit". Gloves are not checked before 60, as there is no healer glove enchant until then.
- **Training** - the goals panel lists spells and ranks you can learn now. Open your class trainer once per character so new ranks are tracked too.
- **Buff watch** - pick self buffs to track (Options > Buff watch or `/sanc buffs`); icons sit on your own bar and flash when a buff is missing or falls off.
- **Minimap button** - left-click options, right-click lock/unlock, shift-click goals, drag to move.
- **Forever-safe** - prefers `C_*` APIs, falls back to legacy globals, and degrades quietly on secret or blocked values. `/sanc probe` reports what the client exposes.

## Commands

| Command | Does |
|---|---|
| `/sanc` | Options window |
| `/sanc lock` / `unlock` | Lock or move the frames |
| `/sanc test` | Test mode (fake party) |
| `/sanc goals` | Goals checklist |
| `/sanc buffs` | Buff watch dropdown |
| `/sanc talents` | Talent planner |
| `/sanc bind <KEY>` / `unbind` | Bind the sequence button |
| `/sanc seq` | Sequence status |
| `/sanc log` | Sequence cast log |
| `/sanc defaults` | Reset click bindings to your class kit |
| `/sanc reset` | Reset frame positions |
| `/sanc minimap` | Show or hide the minimap icon |
| `/sanc probe` | API diagnostic for the Forever client |

## Install

CurseForge app (Forever flavour, search **Sanctum Mini**), or unzip into `World of Warcraft\_classic_beta_\Interface\AddOns\` so you end up with `AddOns\SanctumMini\SanctumMini_Camelot.toc`.

## Development

Pure logic lives in `Logic.lua` and is tested headless:

```
lua5.1 tests/run.lua
```

The suite covers the logic, the secure step snippet, and a smoke-load of every file against a mocked WoW API.

Releases: push a `v*` tag. GitHub Actions runs the tests, packages with the BigWigs packager and uploads to CurseForge (needs the `CF_API_TOKEN` repo secret and `X-Curse-Project-ID` in the TOC).

## Licence

MIT - see [LICENSE](LICENSE).

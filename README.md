# Warmane Group Builder (WGB)

LFM advertisement, auto-invite, inspection, and loot-rule manager for Warmane (WoW 3.3.5a) PUG raid leaders. Built for the actual workflow: configure roles + loot once, spam `/global`, auto-invite whisperers, inspect on join, kick failures, fill the raid.

## Install

1. Drop the `WarmaneGroupBuilder/` folder into `World of Warcraft/Interface/AddOns/`.
2. Restart the client (or `/reload`).
3. `/wgb` to open.

## Optional dependencies

- **GearScore2** or **GearScore** — used as a backend if loaded. Without one, WGB falls back to a coarse iLvl average labeled "(approx)".

## Slash commands

| Command | Action |
|---|---|
| `/wgb` | Toggle main window |
| `/wgb help` | Print all commands |
| `/wgb advert` | Send advertisement now |
| `/wgb start` | Enable auto-invite + auto-repeat |
| `/wgb stop` | Disable auto-invite + auto-repeat |
| `/wgb lock` | Stop accepting new invites; keep group |
| `/wgb kick <name>` | Kick (queued if in combat) |
| `/wgb approve <name>` | Mark player approved |
| `/wgb config` | Open config panel |
| `/wgb reset` | Reset settings (with confirmation) |
| `/wgb debug` | Toggle debug output |

## Workflow

1. Open `/wgb`, **Requirements** tab — pick activity (e.g. ICC 25), tweak role counts and min GS.
2. **Loot Rules** tab — toggle commodities (Primos, Crusader Orbs etc.), pick BoE rule, add custom item reservations (drag from bag).
3. **Advertisement** tab — review preview, click **Send Now**, or enable **Auto-Repeat**.
4. **Group Status** — auto-populates as players join. Click any row to re-open the inspection popup.
5. Inspection popup pops on each join after gear/gem/enchant scan completes — Approve, Kick, or Skip.

## Module map

```
Core/        bootstrap, event bus, utils, slash dispatcher
Modules/     non-UI domain logic, all communicating via the event bus
UI/          panels, popup, minimap button — read state, fire commands
Locales/     enUS default with deDE stub (fallback through __index)
```

All modules talk through `WGB.Events` only. No direct cross-module calls.

## Known limitations

- 3.3.5a `NotifyInspect` is rate-limited server-side (~1.5s). Inspections are strictly serialized with a 5s timeout fallback.
- No spec-driven role inference for shared specs (Feral, Blood DK) without inspect data — initial guess uses class.
- The `/global` channel must already be joined (`/join global`) before sending adverts.
- BoE detection / PvP gear detection is heuristic (item-name pattern match for PvP, gem socket diff for missing gems).

## License

Use it, modify it, ship it.

# Celebi Event — Crystal's GS Ball quest, on Gold, Silver and Crystal

Crystal's Celebi quest does not exist in Gold. This mod puts it there: the
**GS BALL**, **Kurt's** study of it, and **Celebi** at the Ilex Forest shrine --
on all three Gen 2 carts.

Nothing is invented that the cart did not already say. Every line of dialogue,
every coordinate, movement, flag transition and sound is transcribed from
`pret/pokecrystal`; the mod's job is only to supply the scripts Gold never got.

## Try it

Enable it (`celebi_event = true` under `mods` in `options.lua`, or the F10
manager), then walk the quest:

```
  GOLDENROD POKéMON CENTER            KURT'S HOUSE, AZALEA
  ┌───────────────────────┐          ┌───────────────────────┐
  │  step out the door    │          │  KURT                 │
  │  (6,6)                │          │  (3,2) or (14,3)      │
  └───────────────────────┘          └───────────┬───────────┘
                                     a day later │  GS BALL back
                                                 ▼
                                     ILEX FOREST SHRINE (8,22)
                                     press A ──▶ CELEBI, Lv30
```

## The quest, stage by stage

Quest state lives in the mod's **own save bucket** (`mod.save`, backed by
`save.modData[celebi_event]`), never in the event-flag space.
`EVENT_FOREST_IS_RESTLESS`, `EVENT_CAN_GIVE_GS_BALL_TO_KURT` and friends are
Crystal-only ids, and in Gold those numbers belong to unrelated events, so
writing them would corrupt a real save.

| stage | trigger | what happens |
| --- | --- | --- |
| -- | step out through the Goldenrod Poké Center door | the receptionist walks over with Crystal's own lines; `verbosegiveitem GS_BALL`. Nothing at all before the Hall of Fame, and nothing either if a GS BALL is already in the bag |
| `have` | talk to Kurt | "Wh-what is that? … Let me check it for you." -- the ball is taken |
| `given` | talk to Kurt the same day | "I'm checking it now." / "Ah-ha! I see! So…". He is at his BENCH (14,3) and the granddaughter has moved to (11,4) beside him |
| `given` | talk to Kurt after the day rolls over | "This BALL started to shake…" -- the house tune fades, he is shocked, and he **runs out of the house** with the ball, the whoosh on his steps and the exit cue at the door |
| `left` | step out of KURT's house | the world is taken on the doorstep: the player is walked DOWN onto the cart's own trigger tile (9,6), then LEFT, LEFT, UP to him, the three `AzaleaTownKurtText` lines play, and `verbosegiveitem GS_BALL` hands the ball back. Talking to him out there is ONE line and gives nothing |
| `restless` | press A at the Ilex Forest shrine (8,22) | the shrine asks, the ball goes in, the whole of `special CelebiShrineEvent` plays -- the "!", the step back, the descent -- and then **CELEBI Lv30** |
| `caught` | -- | `save.crystal.celebiCaught` is banked; Kurt has his closing line |

### What it leaves alone

A press is only ever intercepted where this mod owns the answer.
`World.interactBody` is the one funnel every press goes through, so the mod
wraps it and answers first -- and returns false, falling through to the engine,
for the shrine before the quest or after Celebi is caught, for Kurt unless the
ball is actually in play, for every press in the Goldenrod Pokémon Center (the
hand-over is a doorway scene, not a conversation), and for every other NPC and
map. That is what keeps Gold's own shrine text and Gold's own Kurt conversation
-- apricorns, the Lure Ball, the granddaughter -- exactly as they were, and the
tests assert the fall-through, not just the interception.

## Two switches, if you would rather not grind

Under **MODS ▸ Celebi Event**. Both default off, so an untouched install is the
cart's behaviour.

| option | what it removes |
| --- | --- |
| `Reach the event without the HALL OF FAME` | the Elite Four run before the receptionist will hand the ball over |
| `Skip KURT's 24-hour wait` | the day between handing Kurt the ball and getting it back |

By default the receptionist only hands the ball over once you have **entered the
Hall of Fame** -- the Virtual Console release's own gate, read through the
engine's `HallOfFame.hasEntered`. Crystal reaches the same place via
`BattleTowerAction GSBALL` returning `GS_BALL_AVAILABLE`, which the engine reads
out of `save.crystal.gsBall`.

The wait is read off the **device clock** (`Clock.weekday`), which is why the
skip exists -- the alternative is changing the system clock and changing it
back. It removes the day and nothing else: the hand-over, the re-talk and every
line still run, so what you see is the real sequence with the wait collapsed.

## Which carts it runs on

**All three Gen 2 carts.**

**Gold and Silver** are one engine (`GameVersion.engine` is `"gs"` for each) and
share their map scripts, so every coordinate, object index and item row this mod
reads is the same on the two. That is checkable rather than assumed: the engine
derives `tools/rom_manifest_silver.json` from Gold's, and `constants.itemOrder`
and `constants.spriteOrder` are byte-identical between them.

**Crystal** runs it too, and there the mod does **not register a second GS
BALL** -- the cart already carries one, so the cart's own record is used. That
is the one thing that changes: `content.items:register` refuses a duplicate id
(`items already registered: GS_BALL`), so registering on Crystal would fail the
mod outright rather than run it. Everything else -- the press interception, the
doorway scene, the shrine, both switches -- runs the same.

The question the code asks is the **capability**, not the cart: *does this ROM
already carry the GS BALL?* `extractItems` keys its table by item name, so
`items["GS_BALL"]` is present on Crystal and nil on both GS carts. A version
string would be the weaker test, and `modkit gen2check` reports it as **MK409**
-- so it was written, measured and removed again.

### The bag is the authority

Two rules, both because Crystal defines the GS BALL natively -- the cart's own
event can hand one over without this mod's stage ever moving:

- **KURT answers to the ball**, not to this mod's stage: a GS BALL in the bag
  *is* the `have` state, which is how the cart reads it too
  (`KurtsHouseKurtScript` is gated on `checkitem GS_BALL`). So a Crystal player
  carrying the ball the *cart's* event gave them gets the mod's conversation
  rather than a fall-through.
- **The receptionist declines** when the bag already holds a GS BALL, from
  either source. That is what stops a second ball on Crystal -- and declining
  means the player simply walks out, because the exit warp is not stood down for
  a scene that never starts.

Both balls are the **same key** (`save.inventory["GS_BALL"]`), which is why one
test covers them.

## The descent sprite

`assets/celebi.png` is the only picture the mod ships: four 16×16 frames, the
cart's own `gfx/overworld/celebi.2bpp` re-cut in the four-shade form the engine
bakes. One sheet draws correctly on Gold, Silver and Crystal alike, because the
colours come from the sprite's own palette (`PAL_OW_GREEN`) and not from the
file.

It is Nintendo's art, and carrying it is a knowing trade rather than an
oversight: the engine's extractor cannot produce the sheet -- Gold has no Celebi
overworld sprite for it to cut, because the cart copies this graphic into
`vTiles0` for that one animation -- so the choice was never "ship it or derive
it", it was "ship it or ship a descent with no Celebi in it". `assets/README.md`
records the trade, and `tools/author_celebi_sheet.py` re-derives the file byte
for byte from a cart's own copy, for anyone who would rather build it than
download it.

Nothing depends on it being there. Delete the file and the shrine event still
runs end to end -- the "!", the step back, the descent, the tear-down and the
Lv30 battle are all code -- the descent simply has no sprite in it, and the mod
says so once in the log. The event is the cutscene and the battle, not the
picture.

## Divergences from Crystal

Three, each forced by what the carts do and do not share:

- **The Azalea hand-back is a tile watch, not a coord event.** Crystal runs
  `AzaleaTownCelebiScene` from `coord_event 9, 6`. A Gen 2 mod cannot add a
  coord event, so the tile is watched through `world.stepped` -- and the scene
  is also taken from the house's own doorway tile, `warp_event 9, 5`, so leaving
  KURT's house starts it whether or not the player happens to find (9,6).
  Everything else is the cart's: `SPRITE_KURT` standing at (6,5), the player
  walked LEFT, LEFT, UP to him, and `verbosegiveitem GS_BALL`.
- **The Goldenrod hand-over is the cart's doorway scene**, reached the same way.
  Crystal's `coord_event 3,7` / `4,7` sit on `COLL_WARP_CARPET_DOWN`, a
  *directional* warp the cart's `CheckWarpTile` declines -- so the coord event is
  what runs when the player steps onto one. `world.stepped` watches the same
  tiles, and since the step onto them is the step OUT of the Center, the
  hand-over happens on the way out rather than on the way in. The scene's
  opening `playsound SFX_EXIT_BUILDING` is the **one command deliberately left
  out**: in the cart it belongs to the hero walking out of the building, and
  here he stops on the tile instead so the receptionist can reach him, so
  nothing has left to make the sound. The closing one is hers and stays.
- **The PokéCom Center itself is the only part Gold lacks.** It is a
  Crystal-only *map* -- but `SPRITE_LINK_RECEPTIONIST` is id 55 of Gold's own
  162-entry `spriteOrder`, the same index as in Crystal's. So the receptionist
  wears the cart's sprite and the Goldenrod Pokémon Center stands in for the
  PokéCom Center's floor.

## Flags and files

| seam | where |
| --- | --- |
| `mod.content.items:register` | the GS BALL (index 251, `KEY_ITEM`, untossable) |
| `mod.world:spawnNpc` | the receptionist, spawned for the doorway scene |
| `world.stepped` | the Center's doorway tile, and AZALEA's (9,6) as a fallback |
| `map.entered` | KURT's house doorway, which starts the Azalea hand-back |
| `World.interactBody` wrap | the press |
| `World:showText` / `World:askYesNo` | every box |
| `World:startBattle` | the CELEBI battle |
| `World:specialSound` | the item-acquisition jingle on both hand-overs |
| `World:step` | the per-frame tick that drives the descent |
| `World:busy` | held true for the cutscene's duration |
| `SpriteRenderer:draw` | the mirror and the flap frame for the Celebi sprite |
| `mod.save` | the quest stage and the day the ball was handed over |
| `mod.options:define` | the two switches |

## Releasing it, and the launcher's auto-update

A release is a **tag**, not a committed file. Pushing `v1.4.8` runs
`.github/workflows/release.yml`, which builds the zip from the tagged tree and
attaches it to the GitHub Release:

```sh
git tag v1.4.8
git push origin v1.4.8
```

The tag and `manifest.json`'s `version` have to agree, and the workflow refuses
to build if they do not -- a release whose tag disagrees with its manifest is
read by the launcher as a different version than it actually is.

The release **body** is `RELEASE_NOTES.md`, committed and published with
`--notes-file`. That body is the only changelog text the launcher renders -- its
**What's New?** modal reads the release, never `CHANGELOG.md` -- so it is written
for a player, and the workflow fails if it is missing or does not name the
version. `CHANGELOG.md` carries the full history and the reasoning behind the
port.

**The asset name matters more here than it looks.** The launcher's mod updater
(`src/mods/ModUpdate.lua`) reads *Releases*, not tags, and looks for an asset
named **exactly** `<mod-id>-<version>.zip`. This mod's id is `celebi_event` --
**with an underscore** -- while the repo and the mod folder are `celebi-event`.
`pickZipAsset` compares the asset name to the id exactly, and its only other
rule is a lowercase prefix match on the id, so `celebi-event-1.4.8.zip`
satisfies neither and survives only on the last-resort "any .zip" branch --
which works while the release carries one zip and starts picking the wrong file
the moment a second one is attached. The workflow derives the name from the
manifest's own `id`, so it cannot drift, and `tests/launcher_update_test.lua`
asserts both halves.

**No hash file is needed.** The mod updater does **not** verify a checksum:
`_pumpModInstall` checks one only `if spec.sha256`, and the single call site that
passes a sha256 is the **cart** install path -- every plain mod update, install,
install-a-version and update-all passes none. `sha256sums.txt` belongs to the
engine's own self-updater, which is a separate mechanism entirely. Adding a hash
file is harmless, but the launcher will never read it, so it cannot be why an
update fails.

**The `github` field has to be in the *installed* copy**, so a build without it
never checks for updates at all. The first release that carries it has to be
installed by hand once; after that the launcher offers updates on its own,
cached six hours per repo.

### Verifying it

Run from the engine checkout, with this repo cloned beside it:

```sh
python3 tools/modkit.py validate  ../celebi-event --strict
python3 tools/modkit.py lint      ../celebi-event
python3 tools/modkit.py gen2check ../celebi-event --strict
luajit ../celebi-event/tests/celebi_event_test.lua
luajit ../celebi-event/tests/launcher_update_test.lua
```

Both suites exit non-zero on any failure, so they drop straight into CI.
`tools/build_release.py` is vendored into this repo because the engine does not
ship it -- a release has to be buildable from the tagged tree alone.

## Credits

- **pret/pokecrystal** -- the event's scripts, text and coordinates. Every line
  in `main.lua`'s `T` table is transcribed from `maps/IlexForest.asm`,
  `maps/KurtsHouse.asm`, `maps/AzaleaTown.asm` and
  `maps/GoldenrodPokecenter1F.asm`.
- **pret/pokegold** -- the map events this mod reads to decide what Gold is
  missing.

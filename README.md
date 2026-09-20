# Celebi Event — Crystal's GS Ball quest, for Gold, Silver and Crystal

Crystal's Celebi quest does not exist in Gold. This mod puts it there: the  
**GS BALL**, **Kurt's** study of it, and **Celebi** at the Ilex Forest shrine.

Persona: **the Archivist.** Nothing is invented that the cart did not already  
say — every line of dialogue, every coordinate and every flag transition below  
is transcribed from `pret/pokecrystal`, and the mod's job is only to supply the  
scripts Gold never got.

## Try it

```sh
python3 tools/modkit.py validate ../celebi-event --strict
python3 tools/modkit.py lint     ../celebi-event
python3 tools/modkit.py gen2check ../celebi-event --notes
luajit ../celebi-event/tests/celebi_event_test.lua
luajit ../celebi-event/tests/launcher_update_test.lua
```

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

## Why this is possible at all

Gold and Crystal are far closer here than they look. Comparing the two carts'  
map events, object by object:

|                         | Crystal                                        | Gold                                           |
| ----------------------- | ---------------------------------------------- | ---------------------------------------------- |
| `ILEX_FOREST` bg event  | `8,22 BGEVENT_UP IlexForestShrineScript`       | `8,22 BGEVENT_READ **IlexForestShrineScript**` |
| what that label does    | the whole Celebi event                         | `jumptext Text_IlexForestShrine`               |
| `KURTS_HOUSE` objects   | KURT 3,2 · TWIN 5,3 · SLOWPOKE 6,3 · KURT 14,3 | **identical**                                  |
| `KURTS_HOUSE` bg events | 7, incl. the Celebi statue at 4,1              | **identical, statue included**                 |
| `AZALEA_TOWN`           | 8 warps, 11 objects                            | **identical**                                  |

So the shrine tile, the statue, the object positions and the map geometry are  
already in Gold. **Only the scripts differ** — and the shrine carries the very  
same label in both carts. This mod supplies the bodies.

## How it reaches the press

A Gen 2 mod **cannot author a script**. `map_scripts` has no Gen 2 home  
(`docs/mod-api-gen2-compat.md`): `data.gen2Scripts` is the cart's own bytecode  
pool, and a Lua row list is not something `src/script/gen2/Vm.lua` can run.  
`mod.world:queueScript` is a five-verb allowlist, and `give_item` is not on it.

What a mod *can* do is bracket the A press. `World.interactBody` is the one  
funnel every press goes through, so this mod wraps it and answers first.

The important half is what it does **not** answer. `tryInteract` returns false —  
falling through to the engine's own body — for:

- the shrine before the quest, or after Celebi is caught;
- Kurt unless the ball is actually in play;
- **every press in the Goldenrod Pokémon Center** — the hand-over is the cart's
  doorway scene, not a conversation, so there is nobody to talk to there;
- every NPC that is not this mod's Kurt;
- every other map.

That is what keeps Gold's own `Text_IlexForestShrine` and Gold's own Kurt  
conversation (apricorns, the Lure Ball, the granddaughter) exactly as they were.  
The test asserts the fall-through on each of those paths, not just the  
interception.

## What the mod does, stage by stage

Quest state lives in this mod's **own save bucket** (`mod.save`, backed by  
`save.modData[celebi_event]`), not in the event-flag space. That is deliberate:  
`EVENT_FOREST_IS_RESTLESS`, `EVENT_CAN_GIVE_GS_BALL_TO_KURT` and friends are  
Crystal-only ids, and in Gold those numbers belong to unrelated events — writing  
them would corrupt a real save.

| stage      | trigger                                            | what happens                                                                     |
| ---------- | -------------------------------------------------- | -------------------------------------------------------------------------------- |
| —          | step out through the Goldenrod Poké Center door | the receptionist walks over with Crystal's own lines; `verbosegiveitem GS_BALL`. Nothing at all before the Hall of Fame — the cart's bare `end` — and nothing either if a GS BALL is already in the bag |
| `have`     | talk to Kurt                                       | "Wh-what is that? … Let me check it for you." — the ball is taken                |
| `given`    | talk to Kurt the same day | "I'm checking it now." / "Ah-ha! I see! So…". He is at his BENCH (14,3) and the granddaughter has moved to (11,4) beside him |
| `given`    | talk to Kurt after the day rolls over              | "This BALL started to shake…" — then the house tune fades, he is shocked, and he **runs out of the house** with the ball, the whoosh on his steps and the exit cue at the door |
| `left`     | walk onto Azalea Town (9,6) | the player is walked LEFT, LEFT, UP to him, the three `AzaleaTownKurtText` lines play, and `verbosegiveitem GS_BALL` hands it back. Talking to him there is ONE line and gives nothing -- the coord tile is the only trigger |
| `restless` | press A at the Ilex Forest shrine (8,22)           | the shrine asks, the ball goes in, **CELEBI Lv30**                               |
| `caught`   | —                                                  | `save.crystal.celebiCaught` is banked; Kurt has his closing line                 |

### The shrine cutscene

Placing the ball does not cut straight to the battle. `special CelebiShrineEvent`
(`pokecrystal/engine/events/celebi.asm`) is not a one-line battle-type setter —
it is the whole descent, and the script steps the player back before calling it:

```
applymovement PLAYER, IlexForestPlayerStepsDownMovement
    fix_facing / slow_step DOWN / remove_fixed_facing
pause 30 / turnobject PLAYER, DOWN / pause 20
special CelebiShrineEvent          <- 161 frames of two, the last one the countdown
loadwildmon CELEBI, 30 / startbattle
```

What the port reproduces, from that file:

| cart | port |
|---|---|
| `ld a, 160`, `ld c, 2 / call DelayFrames` | 160 iterations, one every 2 logic frames, plus the frame `CountDown` runs after the last one |
| `inc [SPRITEANIMSTRUCT_YCOORD]` | one pixel of descent per iteration |
| `cp 10 * TILE_WIDTH + 2` freeze | descends for 74 iterations, then hovers |
| `VAR4` = `$80`, `sub $3` while `> $3a` | the cosine amplitude decays the same way |
| `call CelebiEvent_Cosine` | `SpriteAnims.cosine` — the engine's transcription of the same `calc_sine_wave` |
| `.float_up` / `.float_down` | the same two-arm test on `XCOORD + XOFFSET` |
| facing by `XCOORD + XOFFSET` vs the centre | the same test against `10 * 8` |
| `GetCelebiSpriteTile` | the cart's four-frame graphic, supplied as `assets/celebi.png`, stepped on the cart's own 3/6/9/12 counter |
| `.RestorePlayerSprite_DespawnLeaves` | the spawned object is removed |The animation is driven from `World:step` — the one per-frame seam the overworld
offers a mod (`src/core/Game2.lua:1272`) — and the world reports **busy** for its
duration, so no press, menu or second step can land mid-descent.

The forest theme is gone before the descent starts: `special FadeOutMusic` sits
between the player's `!` and the step back in `IlexForestShrineScript`, so it is
called there, and the map music is handed back by the battle's own
`reloadmapafterbattle`. The wing beat is the cart's too —
`GetCelebiSpriteTile` only picks a new tile when its counter reaches 0, 3, 6 or
9, and at 12 it wraps instead of advancing, so one beat is four tiles over
thirteen iterations. And because `UpdateCelebiPosition` runs inside
`DoNextFrameForAllSprites`, the anim function has already moved the sprite
before the frame's OAM is written, which is why the first drawn frame is the one
the cart draws.


**Two deliberate deviations**, both forced by Gold having none of this content:

- The cart's descent sprite is a bespoke 16-tile, 4-frame graphic
  (`gfx/overworld/celebi.2bpp`), loaded into `vTiles0` for this one animation,
  and Gold has neither it nor the event. The port needs that graphic --
  `assets/celebi.png`, four 16x16 frames stacked, re-cut in the four-shade form
  this engine bakes (see *Celebi's colours* below) -- and it is the one thing
  the mod does **not** ship, because it is Nintendo's art. `assets/README.md`
  says what to drop in and where, and `tools/author_celebi_sheet.py` is the
  recipe that makes it from your own copy of the cart's sheet. Every earlier
  version used the species' extracted **16x16 party icon** instead, which is a
  two-frame front-facing party picture and never looked like the sprite in the
  game. The cart's left/right facing is shown by mirroring the frame rather than
  by the cart's `FRAMESET_CELEBI_LEFT`/`RIGHT`, and with no sheet at all the
  descent still runs -- it simply has no sprite in it.
- The cart's coordinates are absolute **screen** pixels (`depixel 0, 10` →
  OAM 88, 8). The port anchors to the shrine tile instead, which is the same
  position with the camera factored out — the camera is static for the whole
  animation, because the player is scripted and cannot move.

### Celebi's colours

The sheet carries **no colour of its own** — it is white, two greys and
black. `SpriteRenderer:resolveImage` runs it through `getObpImage`, which is the
same bake every other overworld sprite goes through:

```
shade 0 (white) -> OBJ colour 0 -> alpha 0  (hardware: colour 0 is transparent)
shade 1 (grey)  -> OBJ colour 1
shade 2 (grey)  -> OBJ colour 2
shade 3 (black) -> OBJ colour 3
```

and the sprite definition names its palette, `PAL_OW_GREEN`. Read out of the
real Gold ROM through the engine's own resolver (`Palettes.spritePalette`), its
colours 1-3 are **#FF9C52 (orange)**, **#3ABD19 (green)** and black at *every*
time of day — and those are exactly the colours the sprite wears in a capture of
the real event (orange body, green accents, black outline), which is what
settles the choice rather than a guess about which of the eight OW palettes a
Celebi would take.

Versions 1.4.0 and 1.4.1 set `trueColor` on the definition instead. That makes
`resolveImage` hand the sheet back **untouched**: no palette bake, so the
colours were whatever the PNG happened to contain, and a raw blit would have put
a white box behind the sprite anywhere the shades were not already keyed. It is
the one opt-out this mod does not want.

One thing worth flagging: the ASM's sway amplitude is `$80`, which is ±128
pixels — wider than the 160-pixel screen. The transcription is literal, so the
first ~24 iterations sweep wide before the amplitude decays to `$3a` and it
settles. I could not verify that against the footage (the video's storyboards
are blocked and only three frames were obtainable), so if it reads as too
violent on hardware, `DESCENT.AMPLITUDE_START` is the single knob.

Three pieces of engine machinery are reused rather than reinvented:

- **`BATTLETYPE_CELEBI`.** `special CelebiShrineEvent` only writes `wBattleType`  
  (`src/script/gen2/specials/crystal_story.lua:278`). Gold's battle engine  
  already carries the same id (`Battle.BATTLETYPE_CELEBI = 11`) and its  
  no-escape rule, so passing `battleType = "celebi"` to `startBattle` is the  
  whole of that special.
- **`save.crystal.celebiCaught`.** `special CheckCaughtCelebi` reads the caught  
  bit and banks it there; the mod writes the same field on a caught outcome.
- **`World:specialSound`** — the acquisition jingle. Every `verbosegiveitem` in  
  the game rings it (`GiveItemScript`, `engine/overworld/scripting.asm:441-449`),  
  so it is the BICYCLE, the rods, the ITEMFINDER and every gym TM. The engine  
  wires it into the script VM at `src/world/gen2/World.lua:1165` and it picks  
  `Sfx_GetTm` for the TM/HM pocket and `Sfx_Item` for every other one. This mod  
  hands the ball over with `Bag.add` rather than through a script, so it calls  
  the cue itself — with the item's **own index**, read off the merged record, so  
  the pocket test stays the engine's and the ball rings `Sfx_Item` like any  
  other item. Placement is the cart's: `writetext .ReceivedItemText` and then  
  `waitsfx / specialsound`, so the jingle starts with the received line already  
  on screen.

### The one file you supply

Everything above describes a sheet that is **not in this repo**. It is the cart's
own graphic, so it is Nintendo's, and the mod leaves it to the player:
`assets/README.md` says exactly what the file has to be and where it goes, and
`tools/author_celebi_sheet.py` is the recipe that produces it from your own copy
of the cart's sheet.

Nothing else depends on it. The shrine event runs end to end without the file --
the "!", the step back, the 160-iteration descent, the tear-down and the Lv30
battle are all code -- the descent simply has no sprite in it, and the mod says
so once in the log. The event is the cutscene and the battle, not the picture.

### The house swap

`KurtsHouseKurtCallback` is a `MAPCALLBACK_OBJECTS`: while he studies the
ball it hides KURT1 (3,2) and shows KURT2 (14,3), and the twin moves with
him. Gold has both Kurts — event flags 1854 and 1855 — but only ONE twin
object, at (5,3) with no visibility flag, so the cart's TWIN1/TWIN2 swap is
done by relocating her to (11,4). Same thing on screen, and there is no
second copy that could outlive the scene.

### Kurt's exit

His run-out is a **script**, not a movement stream, and the order is what keeps
the sound on the animation. `KurtsHouseCelebiScene` (`maps/KurtsHouse.asm`)
writes `special FadeOutMusic` / `pause 20` / `showemote EMOTE_SHOCK, ..., 30` /
`playsound SFX_FLY` / `applymovement KURT1, KurtsHouseKurtLeavesMovement` /
`playsound SFX_EXIT_BUILDING` / `disappear KURT1` / `waitsfx` /
`special RestartMapMusic`, and the port queues those rows in that order. So the
house tune fades first, the "!" holds for its 30 units, the whoosh starts **as**
the walk does rather than before it, and the exit cue waits at the door for him
before the map music returns.

Both halves of that `showemote` are the cart's and both are easy to get wrong.
It is **silent** — `Script_showemote` is `loademote` plus two `applymovement`s
and a `pause 0`, with no `playsound` in it at all
(`engine/overworld/scripting.asm:1065-1095`) — and it **holds**: that `pause 0`
takes `Script_pause`'s `and a / jr z` arm, leaving `wScriptDelay` as the `time`
operand, and then loops at two frames a unit. So the 30 here is 60 frames with
the bubble up, and nothing behind the `showemote` runs until it is down. The
shrine's `showemote EMOTE_SHOCK, PLAYER, 20` is the same command, so it is
silent and holds 40 frames the same way.

The route is the one thing that is not the stream. `applymovement` refuses a
step the object cannot take; this port's scripted step is forced, so the route
has to be right before it is handed over. The cart's `five big_step DOWN` are
written for **KURT1 at the door end**, and from **KURT2 at the bench** — where
the player finds him when the 24-hour wait is switched on mid-visit — those five
steps go straight into the wall. The port therefore routes him over the map's
own collision (`Map:objectStepPermitted`, the port of
`CanObjectMoveInDirection`): from the bench that is down and then left, across
the room, to the door tile, and from KURT1 it is the cart's own five steps (or
its one-step go-around when the player is below him) unchanged.

### The granddaughter

She is the cart's TWIN1, and her line is chosen by what the house is doing, not
by what the mod has done: the lonely line plays only while KURT is really gone.
The cart's callback returns without touching anything once
`EVENT_FOREST_IS_RESTLESS` is set, so he stays disappeared until the shrine
clears it — and the shrine records that (`"shrine"`) even when CELEBI is not
caught, the same way its own `clearevent` does. A finished save therefore has
him back at the door, and every press in a state the cart's TWIN1 answers from
flags this mod does not own falls through to Gold's own conversation.

## Known divergences from Crystal

One, forced by what Gold has:

1. **The Azalea Town trigger is a tile watch, not a coord event.** Crystal runs  
   `AzaleaTownCelebiScene` from `coord_event 9,6`. A Gen 2 mod cannot add a coord  
   event, so `world.stepped` watches the same tile — and talking to Kurt works as  
   well, so the scene cannot be missed. Everything else is the cart's:  
   `SPRITE_KURT` standing at (6,5), the player walked LEFT, LEFT, UP to him, and  
   `verbosegiveitem GS_BALL`.  

Two things that *used* to diverge and no longer do:

- **The Goldenrod hand-over is the cart's doorway scene now.** Crystal fires  
  `coord_event 3,7` / `4,7` on the two doorway tiles. Those tiles are  
  `COLL_WARP_CARPET_DOWN` — a *directional* warp — and the cart's `CheckWarpTile`  
  declines a directional warp, so the coord event is what runs when the player  
  steps onto one. A Gen 2 mod cannot add a coord event, so `world.stepped`  
  watches the same tiles; the step onto them is the step OUT of the Center, so  
  the hand-over happens on the way out rather than on the way in. The receptionist  
  walks up from the stairs tile, hands the ball over and walks back, with the  
  cart's music and lines — and her `PAL_NPC_BLUE`, which is what her blue hair  
  is. The scene's opening `playsound SFX_EXIT_BUILDING` is the **one command
  deliberately left out**: in the cart it belongs to the hero walking out of the
  building, and here he stops on the tile instead so the receptionist can reach
  him, so nothing has left to make the sound. The closing `SFX_EXIT_BUILDING` is
  hers and stays.
- **The PokéCom Center itself is the only part Gold lacks.** It is a Crystal-only  
  *map* — but `SPRITE_LINK_RECEPTIONIST` is not a Crystal-only sprite: it is id 55  
  of Gold's own 162-entry `spriteOrder`, the same index as in Crystal's. So the  
  receptionist wears the cart's sprite and the Goldenrod Pokémon Center stands in  
  for the PokéCom Center's floor.

## The gate

By default the receptionist only hands the ball over once you have **entered the  
Hall  
of Fame** — the Virtual Console release's own gate, read through the engine's  
`HallOfFame.hasEntered`. Crystal reaches the same place via  
`BattleTowerAction GSBALL` returning `GS_BALL_AVAILABLE`, which the engine reads  
out of `save.crystal.gsBall` (`src/script/gen2/specials/battle_tower.lua:132`).

If you would rather see the event without beating the Elite Four, turn on  
**MODS ▸ Celebi Event ▸ Reach the event without the HALL OF FAME**.

## Debugging it

The event has two waits that make it awkward to test, and both have a switch
under **MODS ▸ Celebi Event**. Both default off, so an untouched install is the
cart's behaviour.

| option | what it removes |
|---|---|
| `Reach the event without the HALL OF FAME` | the Elite Four run before the receptionist will hand the ball over |
| `Skip KURT's 24-hour wait` | the day between handing Kurt the ball and getting it back |

With both on, the whole quest is walkable in one sitting:

```
  GOLDENROD POKéMON CENTER  →  step out the door      (ball in hand)
  KURT'S HOUSE              →  talk to Kurt            (he takes it)
                            →  talk to him again       (he hands it back)
  ILEX FOREST (8,22)        →  press A at the shrine   (the descent, then CELEBI)
```

`Skip KURT's 24-hour wait` removes the wait and nothing else — the
hand-over, the re-talk and every line still run, so what you see is the real
sequence with the day collapsed. It exists because the day is read off the
**device clock** (`Clock.weekday`), so the alternative is changing the system
clock and changing it back.

## Which carts it runs on

**All three Gen 2 carts.**

**Gold and Silver.** They are one engine (`GameVersion.engine` is `"gs"` for
each) and they share their map scripts, so every coordinate, object index and
item row this mod reads is the same on the two. That is checkable rather than
assumed: the engine derives `tools/rom_manifest_silver.json` from Gold's, and
`constants.itemOrder` and `constants.spriteOrder` are **byte-identical** between
them — so `items["GS_BALL"]` and `SPRITE_LINK_RECEPTIONIST` resolve the same way
on both. `/.probe/cart_detect_probe.lua` prints that comparison.

**Crystal** runs the mod too. It already carries the GS BALL in its own item list,
so there the mod **does not register a second one** — the cart's own record is
used, which is the one `Bag.add`, `Bag.remove` and the item jingle all read
anyway — and everything else runs: the same press interception, the same
doorway scene, the same shrine, and both switches under MODS.
`/.probe/faithful_boot_probe.lua` drives the whole load for each cart and prints
what the MODS menu would draw.

Why the registration is the one thing that changes: `content.items:register`
refuses a duplicate id (`items already registered: GS_BALL`,
`src/mods/Registry.lua:103`), so registering on Crystal fails the mod outright
rather than running it. Returning early instead — which is what earlier builds
did — meant the entry chunk never reached `mod.options:define`, and the mod
showed up in the manager with **no options at all**. It now runs and skips just
the one call.

### The bag is the authority

Two rules, and both exist because Crystal defines the GS BALL natively — the
cart's own event can hand one over without this mod's stage ever moving:

- **KURT answers to the ball**, not to this mod's stage: a GS BALL in the bag IS
  the `have` state. The cart reads it the same way (`KurtsHouseKurtScript` is
  gated on `checkitem GS_BALL`). So a Crystal player carrying the ball the
  *cart's* event gave them gets the mod's Kurt conversation rather than a
  fall-through to Crystal's own script.
- **The receptionist scene declines** when the bag already holds a GS BALL, from
  either source. That is what stops a second ball on Crystal. Declining means the
  player simply walks out — the exit warp is not stood down for a scene that
  never starts.

Both balls are the **same key**, which is why one test covers them: `data.items`
and `save.inventory` are keyed by the item's ID, and the engine's own scripts
resolve their item operand through `World:itemIdByIndex`
(`src/world/gen2/World.lua:2764`) before touching the bag — so Crystal's native
`GS_BALL` and this mod's registered one both live at `save.inventory["GS_BALL"]`.

### What it does not do on Crystal

It cannot *replace* Crystal's own scripts — `map_scripts` has no Gen 2 home, so
the cart's own `IlexForestShrineScript` and `KurtsHouseCelebiScene` are still
there. The mod's own entry points pre-empt them instead: the press interception
answers before the cart's script, and the doorway scene holds `World:busy()` true
while it runs, which is what makes `World:tryCoordScript` stand down
(`src/world/gen2/World.lua:7865`). So Crystal gets the mod's version of the
event, not two overlapping ones.

### How the cart is identified

The question the mod asks is the **capability**, not the cart: *does this ROM
already carry the GS BALL?* That is what decides whether the ball has to be
registered.

| signal | how it reads |
|---|---|
| the cart's own data | `extractItems` keys its table by item NAME, so `items["GS_BALL"]` is present on Crystal and nil on both GS carts — `constants.itemOrder[114]` is `GS_BALL` on Crystal, `ITEM_73`/`ITEM_74` on the GS carts |

A version-string test (`GameVersion.get() == "crystal"`) was written, measured and
**removed again**: it is the shape `modkit gen2check` reports as **MK409** —
"allow-lists a Gen 1 version string … test for the capability the code needs
instead of the version" — and it is the weaker question anyway. A ROM whose item
table has been edited still answers the capability honestly, where a version
string would not. The engine's version id is the right question for the gate,
below, which is where it is asked.

### The gate

The manifest claims `games: ["gen2"]` rather than the three ids spelled out, and
that token is what makes the gate cover all three: `ModTargets.normalize`
expands it to `gold, silver, crystal`, which is exactly what
`Loader:_gateGeneration` matches on. Spelling them out instead makes
`modkit gen2check` report **MK400 "no Gen 2 game in games"** against a manifest
that is correct — tried, not assumed — so the token stays and Crystal is handled
in code. `/.probe/targets_probe.lua` runs the engine's own gate for each game.

## Flags and files

| seam                                | where                                                |
| ----------------------------------- | ---------------------------------------------------- |
| `mod.content.items:register`        | the GS BALL (index 251, `KEY_ITEM`, untossable)      |
| `mod.world:spawnNpc`                | the receptionist, spawned for the doorway scene      |
| `world.stepped`                     | the step out onto a doorway tile that runs it        |
| `World.interactBody` wrap           | the press                                            |
| `World:showText` / `World:askYesNo` | every box                                            |
| `World:startBattle`                 | the CELEBI battle                                    |
| `World:specialSound`                | the item-acquisition jingle on both hand-overs       |
| `World:step`                        | the per-frame tick that drives the descent           |
| `World:busy`                        | held true for the cutscene's duration                |
| `SpriteRenderer:draw`               | the mirror and the flap frame for the Celebi sprite  |
| `mod.save`                          | the quest stage and the day the ball was handed over |
| `mod.options:define`                | the Hall of Fame bypass                              |

## Releasing it, and the launcher's auto-update

A release is a **tag**, not a committed file. Pushing `v1.4.6` runs
`.github/workflows/release.yml`, which builds the zip from the tagged tree and
attaches it to the GitHub Release:

```sh
git tag v1.4.6
git push origin v1.4.6
```

The tag and `manifest.json`'s `version` have to agree, and the workflow refuses
to build if they do not -- a release whose tag disagrees with its manifest is
read by the launcher as a different version than it actually is.

### The asset name matters more here than it looks

The launcher's mod updater (`src/mods/ModUpdate.lua`) reads **Releases**, not
tags, and looks for an asset named **exactly** `<mod-id>-<version>.zip`.
This mod's id is `celebi_event` -- **with an underscore** -- while the repo and
the mod folder are `celebi-event`. That is not cosmetic. `pickZipAsset`
compares the asset name to the id exactly, and its only other rule is a
lowercase prefix match on the id, so `celebi-event-1.4.6.zip` satisfies
neither and survives only on the last-resort "any .zip" branch, which returns
whichever `.zip` comes first in the release's asset array. That works while the
release carries one zip and starts picking the wrong file the moment a second
one is attached.

The workflow derives the name from the manifest's own `id`, so it cannot drift.
`tests/launcher_update_test.lua` asserts both halves: that the id spelling wins
past a decoy, and that the hyphenated one does not.

### No hash file is needed

Worth saying, because it is a natural thing to reach for: the mod updater does
**not** verify a checksum. `_pumpModInstall` checks one only `if spec.sha256`,
and the single call site that passes a sha256 is the **cart** install path --
every plain mod update, install, install-a-version and update-all passes none.
The `sha256sums.txt` asset belongs to the engine's own self-updater, which is a
separate mechanism entirely. Adding a hash file is harmless, but the launcher
will never read it, so it cannot be why an update fails.

### The part that only works from here on

The `github` field has to be in the *installed* copy, so a build without it
never checks for updates at all. The first release that carries it has to be
installed by hand once; after that the launcher offers updates on its own,
cached six hours per repo.

### Verifying it

```sh
python3 tools/modkit.py validate . --strict
python3 tools/modkit.py lint     .
python3 tools/modkit.py gen2check . --strict
luajit tests/celebi_event_test.lua
luajit tests/launcher_update_test.lua
```

Both suites exit non-zero on any failure, so they drop straight into CI.
`tools/build_release.py` is vendored into this repo because the engine does not
ship it -- a release has to be buildable from the tagged tree alone.

## Credits

- **pret/pokecrystal** — the event's scripts, text and coordinates. Every line  
  in `main.lua`'s `T` table is transcribed from `maps/IlexForest.asm`,  
  `maps/KurtsHouse.asm`, `maps/AzaleaTown.asm` and  
  `maps/GoldenrodPokecenter1F.asm`.
- **pret/pokegold** — the map events this mod reads to decide what Gold is  
  missing.

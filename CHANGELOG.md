# Changelog

All notable changes to this mod are documented here. The format is
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## What's New?

Newest first, one short list per version, so the recent history can be read
without reading the entries below it. The same summary in the form the game
launcher shows it is `RELEASE_NOTES.md` -- that file is the release *body*, and
the body is the only changelog text the launcher renders (its **What's New?**
modal reads the release, never this file).

### 1.4.9 -- runs alongside Wilds of Kanto

- With Wilds of Kanto installed, the GOLDENROD POKeMON CENTER receptionist
  used to appear at the stairs and never move, and her scene never ended:
  the other mod reclaims the engine's per-frame step while it loads, which
  took this mod's own tick away with it. The tick is now put back
  automatically, whichever mod loads last.
- The scene itself is unchanged -- the same lines, the same movements and
  the same tiles. Only the engine seam it runs on is re-asserted.

### 1.4.8 -- KURT's exit and the GS BALL hand-back are one scene

- The world stays locked from the moment KURT runs out of his house until the
  GS BALL is back in your bag. There is no longer a window where control comes
  back in between.
- The hand-back starts on the doorstep: leave the house and the mod walks you
  down onto the cart's own trigger tile, over to KURT, and plays the lines.
- Walking out and turning away no longer strands the scene on a tile you might
  never step on.

### 1.4.7 -- the descent has a sprite again

- `assets/celebi.png` is back in the package. 1.4.5 left it to the player, and
  the engine's extractor cannot produce it, so the real choice was between
  carrying the file and shipping a descent with no Celebi in it.
- The no-sheet path stays, and is tested: delete the file and the event still
  runs end to end, minus the sprite.

### 1.4.6 -- renamed to Celebi Event

- The name in **MODS** is the manifest's `name` field, and it now says what the
  quest is rather than which item it is about.
- The **id** is deliberately unchanged, so every existing install still updates.

### 1.4.5 -- the bag is the authority

- KURT answers to a GS BALL in the bag rather than to this mod's own stage, so
  the ball Crystal's own event gave is recognised too.
- The receptionist declines to hand over a second one.
- The exit warp out of the GOLDENROD POKeMON CENTER is stood down for the frame
  the scene starts, and only for a scene that actually starts.

## History

## [1.4.8] - 2026-09-20

The hand-back outside KURT's house is one unbroken scene, and the world is never
walkable in the middle of it.

### Fixed

**The player could move between KURT's exit and the hand-back.** The cart lets
the player walk out of KURT's house on their own, and the hand-back is a
separate `coord_event 9, 6` that only runs once they step on it -- so from the
moment KURT runs out until the player happens to find the trigger tile, the
world is walkable. A player who turned left at the door instead of down wandered
off mid-quest, and the scene then played from wherever they came back to. The
mod now takes the world on the doorway: `warp_event 9, 5` is the house door, so
(9,5) is the tile the map load finds them standing on, and `beginAzaleaScene` is
called from the `map.entered` handler with the step down onto the trigger, the
walk over to KURT and the hand-back all scripted from there. `cutscene` -- which
`World:busy` reports -- is what holds the player, and it is never released in
between.

The cart's own arm is untouched: the `world.stepped` trigger still runs the
scene for a save already standing on (9,6), and it is still the step ONTO the
tile rather than the arrival through the door. Tested both ways, plus a
frame-by-frame assertion that `World:busy` never answers false between the
doorway and the first line.

### Changed

**`RELEASE_NOTES.md` is the release body, and CI publishes it.** The workflow
used `gh release create --generate-notes`, so the launcher's **What's New?**
modal was rendering GitHub's generated commit list rather than anything written
for a player. The body is the only changelog text the launcher shows, so the
notes are now a file, guarded by the workflow (it must exist and must name the
version), and published with `--notes-file`.

**This changelog opens with a scannable "What's New?" block**, and the README is
condensed to the essentials -- install, what the quest does, which carts it runs
on, and how to release it. The reasoning the old README carried lives here,
where it belongs.

**The 1.2.0 note about the descent's sway is corrected in place.** It said the
sway had been scaled into the cart's "in window" band; the code says the
opposite, and `main.lua`'s `DESCENT` comment is explicit that the amplitude is
a pixel count and is **not** scaled. That reversal was documented only in the
old README, which this release condenses, so the correction moves to where the
history lives.

## [1.4.7] - 2026-09-20

The descent sprite is shipped again, and that is a reversal of 1.4.5.

### Changed

**`assets/celebi.png` is back in the package.** 1.4.5 left it to the player on
the grounds that it is a re-cut of the cart's own overworld graphic and so
Nintendo's art. That was the wrong trade, and the reasoning behind it did not
survive contact with the code: the engine's extractor cannot produce the sheet,
because Celebi's graphic is not a row of `OverworldSprites` -- `SpecialCelebiGFX`
copies it into `vTiles0` for the one animation -- so Gold has nothing to cut and
no import ever contains one. The choice was never "ship it or derive it". It was
"ship it or ship a descent with no Celebi in it", and 1.4.5 and 1.4.6 chose the
second without saying so plainly enough.

The sheet is 16x64, four 16x16 frames, in the four shades the bake reads. One
file, and it draws correctly on Gold, Silver and Crystal alike, because the
colours come from `PAL_OW_GREEN` rather than from the file. `assets/README.md`
records where it comes from and what it has to be, and
`tools/author_celebi_sheet.py` -- vendored, and verified to reproduce it byte for
byte from a cart's own copy -- is the recipe for anyone who would rather build it
than download it.

The no-sheet path stays, and is tested: delete the file and the event still runs
end to end, minus the sprite, and the mod logs it once.

The version moves to 1.4.7 because 1.4.6 is published without the sheet.

### Fixed

**Celebi not appearing during the descent.** The symptom 1.4.5 introduced, and
the reason for the reversal above. The sprite is built from `assets/celebi.png`,
and that file was not in the package.

## [1.4.6] - 2026-09-20

The mod is called **Celebi Event**.

### Changed

**Renamed, from "The GS Ball" to "Celebi Event".** The name in **MODS**, and in
every launcher notice about the mod, is the manifest's `name` field
(`RomImporter.lua` reads `manifest.name or manifest.id`); it read "The GS Ball",
which names the item the quest is about rather than the quest.

The mod's **id is deliberately unchanged** -- `celebi_event`. The launcher
matches the release asset against the id, and the installer writes to
`mods/<id>`, so a new id would orphan every existing install and break the
update path this release exists to carry.

Nothing else changed: no script, no text, no asset. The version moves to 1.4.6
because 1.4.5 is already published with the old name and a release number is
not reusable.

## [1.4.5] - 2026-09-20

Two rules about the GS BALL, both of them about the bag being the authority
rather than this mod's own bookkeeping -- plus one change to what the mod ships.

### Changed

**The descent sprite is no longer shipped.** `assets/celebi.png` is a re-cut of
the cart's own 16x64 overworld graphic, so it is Nintendo's art, and the mod now
leaves it to the player instead of redistributing it. `assets/README.md` says
what the file has to be and where it goes, and `tools/author_celebi_sheet.py` --
vendored from the author's machine, and verified to reproduce the old sheet
byte for byte -- is the recipe that makes it from your own copy of the cart's
sheet.

Nothing else is affected. The shrine event still runs end to end without the
file: `beginShrineDescent` no longer abandons the cutscene when the sprite cannot
be built, it logs once and descends anyway. The "!", the step back, the 160
iterations, the tear-down and the Lv30 battle are all code; only the picture is
optional.

### Fixed

1. **KURT now recognises Crystal's own GS BALL, not just this mod's.** He was
   gated on this mod's stage alone, so a Crystal player carrying the ball the
   *cart's* event gave them got no reaction from him at all — the conversation
   fell through to Crystal's own Kurt script. He now answers to the ball:

   > A GS BALL in the bag IS the "have" state, whatever this mod's own stage
   > says. The cart reads it that way too — `KurtsHouseKurtScript` is gated on
   > `checkitem GS_BALL` — and it matters here because Crystal defines the item
   > natively.

   Both balls are the **same key**, which is why one test covers them:
   `data.items` and `save.inventory` are keyed by the item's ID, and the engine's
   own scripts resolve their item operand through `World:itemIdByIndex`
   (`src/world/gen2/World.lua:2764`) before touching the bag — so Crystal's
   native `GS_BALL` and this mod's registered one both live at
   `save.inventory["GS_BALL"]`. (`Bag.add` / `Bag.remove` write `inv[id]` for the
   same reason, `Bag.lua:131-167`.) On Gold and Silver the ball only ever arrives
   from this mod's receptionist, which sets `"have"` as it hands it over, so the
   rule is the same answer there.

2. **The receptionist no longer hands over a second GS BALL.** The doorway scene
   already declined once this mod's stage had moved on, but that stage cannot see
   a ball the *cart's* event gave — so on Crystal a player who had done the
   native event would walk out of the POKéMON CENTER and be handed another one.
   The scene now also declines when the bag already holds a GS BALL, from either
   source, which is the same rule KURT uses. Declining means the player simply
   walks out: the exit warp is not stood down for a scene that never starts.

### Tests

`tests/celebi_event_test.lua` **305 → 342 checks, 0 failures**. Both rules are
pinned directly:

- KURT with a ball in the bag and **no** stage answers `kurtWhatIsThat` and takes
  it (the Crystal case), while the same press with an empty bag still falls
  through to the cart's own conversation;
- the doorway scene is suppressed with a ball in the bag **and** with a stage set
  — the two cases separately — and still runs when neither is true;
- and a declined scene is asserted to leave `heldDir` alone, so the exit warp is
  not stood down for a scene that never started.

The descent **without** the player's sheet has a case of its own, because that is
the state a fresh install is in and it has to be a working state. The event is
driven end to end — the battle, the catch, Kurt's walk-out and the teardown — and
the frame count is asserted rather than just the outcome, so a cutscene that had
been skipped rather than descended cannot pass. The mod's one warning is checked
by name.

Writing that case turned up a bug in the suite, not in the mod. The block that
collects the mod's `mod.log:error` calls was hung off `run.mod.log`, and there is
no such field: `mod.log` is handed to `main.lua` as an argument, while the
loader's mod record carries `path`, `state`, `manifest` and `enabled`. So the
guard `if run.mod and run.mod.log then` was never true, both collectors were never
installed, and every assertion reading them — including the whole-run "nothing
went wrong quietly" check — passed without being able to fail. They now read the
engine's own `Logger.history`, which is its bounded record of everything emitted,
and each case scans from a mark so a warning from an earlier scenario cannot
satisfy a later one. Verified by counterfactual both ways: silencing the descent's
warning turns two checks red, and injecting a `mod.log:error` turns both error
assertions red with the message in the output.

...and so is the claim that nothing else moved. The Crystal start — a ball in the
bag with **no** stage — is walked past every other reader of the stage and each
one is asserted to answer as it did before:

- `applyKurtHouse` leaves the house in the quest-not-started arrangement (KURT1
  at the door, KURT2 off the map, the granddaughter at home at (5,3)), because
  the ball being KURT's trigger does not move anybody until he takes it;
- the shrine's gate is `stage == "restless" AND hasBall`, so the ball alone does
  not open it — the press still falls through to the cart's own "forest's
  protector" text and the ball stays in the bag.

### Packaging

Nothing about the quest changed; the mod learned how to be updated.

- `manifest.json` gained the `github` field the launcher reads for mod
  auto-update, so an installed copy is offered 1.4.6 and later in the mod
  manager instead of having to be replaced by hand. It only starts working
  from this build onward: the field has to be in the copy that is installed,
  so this release has to be installed once by hand before the launcher will
  ever offer the next one.
- The release asset is named `celebi_event-1.4.5.zip` -- with an
  **underscore**, after the manifest's `id`, not the hyphenated
  `celebi-event` that the repo and the mod folder use. The launcher matches
  that name exactly and otherwise falls back to a prefix match on the id, so
  the hyphenated spelling is rescued only by its last-resort "any .zip"
  branch. It is derived from the manifest rather than typed out, so it cannot
  drift.
- `.modkitignore` now also lists `tests/launcher_update_test.lua`,
  `tools/build_release.py`, `tools/author_celebi_sheet.py` and
  `assets/celebi.png`, so none of them reaches an installed mod.
- `tests/launcher_update_test.lua` is new (43 checks, 0 failures). It pins
  the shape of the release this repo publishes against the engine's own
  `ModUpdate` parser, with no network: the tag is semver, the asset is named
  for the manifest's id, an older install reports `available` while an equal
  or newer one does not. It exists because a release the launcher cannot see
  fails silently -- the mod simply never offers an update, and nothing says
  why.


## [1.4.4] - 2026-09-19

**Built on 1.4.3** — the whole of that release is in here, and this adds two
things: the GOLDENROD POKéMON CENTER hand-over is the cart's own scene at last,
and Kurt's last box gets a portrait. Four details of those sequences are then
matched to the cart as well — a dropped exit cue, the receptionist's blue
palette, and the two "!" emotes going silent and holding. The mod's cart support
is pinned down too: it runs on **all three** Gen 2 carts now, with Crystal
skipping only the duplicate GS BALL registration, and the `DEBUG:` prefix is off
the KURT wait switch. Nothing else was touched.

### Fixed

1. **The Goldenrod hand-over is the cart's entrance scene now, triggered on the
   way OUT.** `maps/GoldenrodPokecenter1F.asm` hands the GS BALL over from a
   **coord event on the two doorway tiles** — `coord_event 3, 7,
   SCENE_GOLDENRODPOKECENTER1F_GS_BALL, ...GSBallSceneLeft` and the same at
   `4, 7`. The receptionist has no script of her own on either cart (her
   `object_event` points at the shared `ObjectEvent`), and the mod's stand-in
   stood at `(6,6)` with a press-to-talk dialogue the cart does not have.

   The scene is transcribed: `playsound SFX_EXIT_BUILDING`, the receptionist
   placed at the stairs tile `(0,7)`, `playmusic MUSIC_SHOW_ME_AROUND`, her
   approach — `UP` then one `RIGHT` per tile to the door the player stepped out
   by, three for the left and four for the right, ending `turn_head DOWN` —
   `turnobject PLAYER, UP`, the two lines with `verbosegiveitem GS_BALL` between
   them, then the mirror walk back to `(0,7)`, `special RestartMapMusic`,
   `disappear` and one more `SFX_EXIT_BUILDING`. The two flags the cart sets
   together are the one stage value both later scenes already test.

   **The trigger is the STEP onto a doorway tile, not the arrival through the
   door**, and the cart agrees: those tiles are `COLL_WARP_CARPET_DOWN`, and
   `CheckWarpTile` declines a *directional* warp (`CheckDirectionalWarp` clears
   carry), so the coord event is what runs when the player steps onto one. Gold
   has the same map, tile for tile — the doorway warps at `(3,7)`/`(4,7)` to
   GOLDENROD_CITY and the stairs warp at `(0,7)` to POKECENTER_2F are identical,
   and every cell both of the cart's movements crosses is walkable there,
   checked through the engine's own `Map`/`Permissions` against the real ROM.

   Two engine details had to be got right, and both come out of the real ROM
   (see `/.probe/pokecenter_grid_probe.lua`):

   - **The exit warp has to be stood down, and `warpCooldown` is not the lever.**
     `World:step` emits `world.stepped` and only *then* asks
     `World:checkWarpOnArrive` (`World.lua:11106-11113`), and for a directional
     warp that test is `heldDir == carpetDirection(coll)` — so a player walking
     out with DOWN held was warped to GOLDENROD_CITY in the same frame the scene
     started. `warpsSuppressed()` is never consulted on that arm, so the mod
     drops the held direction for the frame instead. `Game2` polls input before
     `World:step` (`Game2.lua:1268-1271`), so that is in time; and once the scene
     owns the world, `World:busy` — which this mod holds true for the whole
     cutscene — keeps `movePlayer` (and with it `checkCarpetWhileStanding`) from
     reading the direction again until it ends. Afterwards the player is still on
     the tile, so holding DOWN again walks them out as before.
   - **The receptionist wears the cart's own sprite.** `SPRITE_LINK_RECEPTIONIST`
     is index 55 of Gold's own 162-entry sprite table, the same index as in
     Crystal's, so the earlier `SPRITE_COOLTRAINER_F` stand-in — and the belief
     that the sprite was Crystal-only — were both unnecessary.

   She is also not a standing object any more: on the cart she has no
   interaction script and exists only for the scene, so nothing is spawned until
   it runs and there is nobody to talk to in the Center.

2. **Kurt's last box had no dialogue portrait.** The dialogue-portraits mod names
   a speaker from the A press that started the conversation: `World:interactBody`
   resolves the object in front, sets `World.talkNpc` and brackets the box, and
   the mod reads the object back out. Kurt has three conversations behind a press
   here — the ball he is handed in his house, and the two follow-up talks — and
   they resolve. Two have no press behind them: the AZALEA hand-back runs off the
   coord tile (`world.stepped`) and the ILEX FOREST closing line — his **last**
   box — off the battle callback. Nothing resolved an object for either, so those
   boxes came out bare. (A mod cannot forge the engine's `world.interacted` to
   close the gap — `mod.events:emit` is sandboxed to the mod's own prefix,
   `Loader.lua:1281`.)

   Those four boxes now open with `"KURT: "`, which is the portraits mod's other
   route for a character the ROM has no art for: a box that names its speaker in
   the text resolves through `CustomArt/KURT.png`, the file that mod ships beside
   `CustomArt/SPRITE_KURT.png` for exactly this. It needs no press and no world
   state, so it works wherever the box is pushed from. And it is the game's own
   convention for him rather than a token invented here: the Gold ROM's own text
   opens **ten** of Kurt's boxes with `"KURT: "` — `"KURT: Hi, {PLAYER}! You
   handled yourself like a real hero at the WELL."`, `"KURT: Ah, {PLAYER}! I just
   finished your BALL. Here!"` — read out of the cart, not assumed. The three
   press-driven conversations are byte-for-byte as they were.

### Adjusted — four details, against the cart

Every sequence above is kept exactly as it was; these four are the only things
touched, and each is read out of the ROM rather than guessed.

1. **The Goldenrod scene no longer opens with `SFX_EXIT_BUILDING`.** `.gsball`
   does write `playsound SFX_EXIT_BUILDING` as its first command, but in the cart
   that cue goes with the hero actually walking out of the building: the coord
   event fires on the step onto the doorway tile and the step's own warp to
   GOLDENROD_CITY follows straight after it. Here the scene stands that warp down
   so the receptionist can reach him — he stops on the tile, at the last moment
   before she calls him — so nobody has left and the leaving cue has nothing
   behind it. The `SFX_EXIT_BUILDING` at the other end stays: that one is hers,
   and it rings as she vanishes back down the stairs.
2. **The receptionist has blue hair.** Her `object_event` names `PAL_NPC_BLUE`,
   and the spawn was passing `palette = 0`, which means "use the sprite's own
   default". The field is now 9 — `PAL_NPC_BLUE` is `const_def 1 << 3` over the
   eight `PAL_OW_*` names (`constants/sprite_data_constants.asm:15-38`), and
   `Palettes.objectPaletteId` takes `p % 8` = 1 and hands back that OBJ palette,
   which is the blue one. (`object_event` packs it as `dn \9, \<10>`, palette in
   the HIGH nybble, so 9 is what the runtime wants.)
3. **Kurt's "!" is silent and is waited on.** `Script_showemote` is `loademote`
   plus two `applymovement`s and a `pause 0`, with **no `playsound` anywhere in
   it** (`engine/overworld/scripting.asm:1065-1095`), so nothing rings with the
   bubble. An earlier build rang `SFX_BUMP` as an addition; the cue is gone. The
   wait is kept and is load-bearing: `pause 0` takes `Script_pause`'s
   `and a / jr z` arm, leaving `wScriptDelay` as the `time` operand, and then
   loops at two frames a unit — so the 30 here holds the script for 60 frames and
   nothing after the `showemote` runs until the bubble is down. His exit sound is
   untouched: `playsound SFX_FLY` as he starts running, `playsound
   SFX_EXIT_BUILDING` as he reaches the door, with the whole movement between
   them.
4. **The shrine's "!" is silent and waited the same way.** `showemote
   EMOTE_SHOCK, PLAYER, 20` loses the same added cue and keeps the same hold —
   40 frames — so the `FadeOutMusic` and the step back still wait for the bubble
   to come down.

There is no emote cue left anywhere in the mod, so the movement queue's `cue` /
`cueId` row fields are gone with them; `SFX_EMOTE` is gone too, replaced by the
note that the cart has no such sound.

### Cart support — Gold, Silver and Crystal

**Gold and Silver.** They are one engine (`GameVersion.engine` is `"gs"` for each)
and share their map scripts, so every coordinate, object index and item row this
mod reads is the same on the two. That is checkable rather than assumed: the
engine derives `tools/rom_manifest_silver.json` from Gold's, and
`constants.itemOrder` and `constants.spriteOrder` are **byte-identical** between
them — so `items["GS_BALL"]` and `SPRITE_LINK_RECEPTIONIST` resolve the same way
on both. `/.probe/cart_detect_probe.lua` prints the comparison, and the probe has
also been run over the **real Gold and Crystal ROMs** through the engine's own
extractor: Gold's item table has no `GS_BALL` key, Crystal's does.

**Crystal runs the mod too.** Earlier builds returned early on it, because the
event is already in that ROM. That is why the mod showed up in the manager on
Crystal with **no options at all**: the entry chunk never reached
`mod.options:define`, so `loader.optionSchemas[celebi_event]` stayed empty and
the MODS menu had nothing to draw (`ManagerState:schemaFor`). It also could not
simply run as-is — `content.items:register` refuses a duplicate id
(`items already registered: GS_BALL`, `src/mods/Registry.lua:103`), which fails
the mod outright rather than running it.

So the early return is gone and the decision now covers exactly one call. The
question asked is the **capability**, not the cart: *does this ROM already carry
the GS BALL?* On Crystal it does, so the mod skips `content.items:register` and
uses the cart's own record — which is the one `Bag.add`, `Bag.remove` and the
item jingle read anyway — and everything else runs: the press interception, the
doorway scene, the shrine, and both switches under MODS.
`/.probe/faithful_boot_probe.lua` drives the whole load per cart with the game
injected the way Game2 injects it, and prints `options the MODS menu would draw:
2 rows` for all three.

It cannot *replace* Crystal's own scripts — `map_scripts` has no Gen 2 home — so
the mod's entry points pre-empt them instead: the press interception answers
before the cart's script, and the doorway scene holds `World:busy()` true while it
runs, which is what makes `World:tryCoordScript` stand down
(`src/world/gen2/World.lua:7865`). Crystal gets the mod's version of the event,
not two overlapping ones. The mod's own stage is separate from the cart's flags,
so a Crystal player plays the mod's quest from the start — including a GS BALL
from the mod's receptionist even if the cart's own event already gave one.

A version-string test (`GameVersion.get() == "crystal"`) was written, measured
and **removed again**: it is the shape `modkit gen2check` reports as **MK409** —
"allow-lists a Gen 1 version string ... test for the capability the code needs
instead of the version" — and it is the weaker question anyway. A ROM whose item
table has been edited still answers the capability honestly, where a version
string would not. The engine's own version id is the right question for the
manifest's *gate*, which is where it is asked.

The manifest keeps claiming `games: ["gen2"]`, and that token is what makes the
gate cover all three: `ModTargets.normalize` expands it to
`gold, silver, crystal`, which is exactly what `Loader:_gateGeneration` matches
on. Spelling the three ids out instead makes `modkit gen2check` report **MK400
"no Gen 2 game in games"** against a manifest that is correct — tried, not
assumed — so the token stays and Crystal is handled in code.
`/.probe/targets_probe.lua` runs the engine's own gate for each game and prints
`LOADED` for all three.

### Changed

- **`DEBUG: skip KURT's 24-hour wait` is now `Skip KURT's 24-hour wait`.** The
  option is unchanged in what it does — it is still the switch that collapses the
  day — but it is not labelled as a debug switch under MODS any more. The
  manifest description's "two debug switches" is now "two switches", and the
  README's table and prose follow.

### Removed

- The standing attendant and its press dialogue, the `notYet` line it said
  before the HALL OF FAME, and the option help text describing both. The cart's
  scene does nothing at all when the ball is not available — a bare `end` — and
  the receptionist exists only for the scene, so there is nothing left to talk to
  and nothing left to say.

### Tests

`tests/celebi_event_test.lua` **239 → 299 checks, 0 failures**: the scene end to
end (both doorways, the music, the walk out and back, the despawn), the `heldDir`
stand-down on both doorway tiles and *not* on a declined scene, the bare `end`
before the HALL OF FAME, the `iftrue .cancel` on a second walk out, the stairs
tile and the middle of the room as non-triggers, and the `"KURT: "` token on all
four of the press-less boxes.

The four details are pinned rather than described: the scene rings **no** cue as
it opens and exactly two in all (`Sfx_Item`, then the closing
`Sfx_ExitBuilding`); the receptionist's `def.palette` is 9 and
`Palettes.objectPaletteId` resolves it to OBJ palette 1; and **both** emotes are
asserted silent *and* holding — one frame short of the hold nothing has been
cued, on the last frame nothing has been cued, and only then does the command
behind the `showemote` run.

Cart support is pinned per cart: Gold and Silver each register the GS BALL, a
Crystal-shaped item list skips that one call **but still defines the options and
installs the handlers**, and a GS item list still registers with the engine's
version id saying `"crystal"` — because the decision is the capability and not
the cart. The option labels are read out of `mod.options:define` and asserted to
carry no `DEBUG`. `/.probe/faithful_boot_probe.lua` checks the same three carts
through the real Loader with the game injected.

## [1.4.3] - 2026-09-19

**Five from play, all of them timing or transcription.**

### Fixed

1. **KURT's exit had its sound a whole cue ahead of the animation.** The
   sequence played `SFX_FLY` and THEN held the walk until it had finished, so he
   started running after the whoosh was over. The cart writes
   `special FadeOutMusic` / `pause 20` / `showemote EMOTE_SHOCK, ..., 30` /
   `playsound SFX_FLY` / `applymovement ...` / `playsound SFX_EXIT_BUILDING` /
   `disappear` / `waitsfx` / `special RestartMapMusic`, and that is now the
   order it runs in: the house tune fades, the "!" comes up and holds for its
   30 units, the whoosh starts AS the movement does, and the exit cue waits for
   him at the door before the map music comes back. The shrine's `!` and its
   `pause 20`/`showemote`/`FadeOutMusic` beats are transcribed the same way.
2. **KURT could walk out through the wall.** `applymovement` refuses a step the
   object cannot take, but this port's scripted step is a forced one, so the
   route has to be right before it is handed over. The cart's stream is written
   for KURT1 at the door end (five `big_step DOWN`); run from KURT2 at the bench
   -- which is where the player finds him when the skip-wait switch is turned on
   mid-visit -- those five steps go straight into the wall below the bench. The
   route is now a shortest walk to the door over the map's own collision
   (`Map:objectStepPermitted`, the port of `CanObjectMoveInDirection`), which
   from the bench is down and then left, across the room, to the door tile, and
   which from KURT1 is the cart's own five steps (or its one-step go-around when
   the player is below him) unchanged.
3. **The granddaughter said "Grandpa's gone… I'm so lonely…" with him back in
   the house.** KURT is now off the map for exactly the restless stretch he is
   actually away for -- the cart's callback returns without touching anything
   once `EVENT_FOREST_IS_RESTLESS` is set, so he stays disappeared until the
   shrine clears it -- and the shrine records that (`"shrine"`) even when CELEBI
   is not caught, the same way its own `clearevent` does. So the lonely line
   only plays while he is really gone, a finished save has him at the door
   again, and the press falls through to Gold's own granddaughter conversation
   in every state the cart's TWIN1 answers from flags this mod does not own.
4. **The forest music played on under the descent.** `special FadeOutMusic` is
   between the player's `!` and the step back in `IlexForestShrineScript`, so
   the theme is gone a good second before `special CelebiShrineEvent` runs. It
   is now called there, and the map music is handed back by the battle's own
   `reloadmapafterbattle`.
5. **Celebi's wing beat was about three times too fast.** `GetCelebiSpriteTile`
   only picks a new tile when its counter reaches 0, 3, 6 or 9 -- `.AddE`
   walks 3, 6, 9, 12 and every other value leaves the tile alone -- and at 12 it
   wraps the counter instead of advancing it, so one beat is four tiles over
   THIRTEEN iterations (twenty-six frames). Stepping the frame every iteration,
   which is what this did, flapped the sprite once per two frames. The
   counter is followed now, and the first drawn frame is the one the cart draws:
   `UpdateCelebiPosition` runs inside `DoNextFrameForAllSprites`, so the anim
   function has already moved the sprite before the frame's OAM is written.
   Together with `CelebiEvent_CountDown` running AFTER the frame, that also
   makes the descent 161 frames rather than 160.

### Notes

- The step queue behind those exits now transcribes the script commands rather
  than just the steps: `pause n`, `showemote emote, object, time`, `playsound`,
  `waitsfx`, `turnobject` and `special FadeOutMusic` are rows, and a movement
  blocks the rows behind it (`applymovement` is a blocking command).
- Five new behaviour checks cover the route: KURT1's five steps, KURT2's fourteen
  tiles from the bench to the door, every tile of it replayed against a
  wall-mapped KURTS_HOUSE, and the ending warp tile.

## [1.4.2] - 2026-09-18

**Celebi's sprite was drawn true-colour, so it wore the PNG's own colours
instead of the game's.**

### Fixed

1. **The shrine sprite looked nothing like the event.** The sprite definition
   carried `trueColor = true`, which makes `SpriteRenderer:resolveImage` return
   the sheet **untouched** (`src/render/SpriteRenderer.lua:238`): the
   `getObpImage` bake never ran, so the colours were whatever the asset
   happened to hold, the object palette named on the definition
   (`PAL_OW_GREEN`) was never applied, and OBJ colour 0 was never keyed to
   alpha. The definition carries no `trueColor` now, so the sheet goes through
   the same bake as every other overworld sprite in the game. Read out of the
   real Gold ROM through the engine's own resolver
   (`Palettes.spritePalette`), that palette's colours 1-3 are **#FF9C52
   (orange)**, **#3ABD19 (green)** and black at *every* time of day — an
   orange-bodied, green-accented hover, which is what the cart's event shows.
2. **`assets/celebi.png` is the cart's own graphic now.** It is
   `gfx/overworld/celebi.2bpp` — the 16x64, four-frame overworld sheet
   `GetCelebiSpriteTile` indexes in `engine/events/celebi.asm` — re-cut as an
   opaque four-shade sheet, in place of a hand-drawn picture. The frames were
   already correct; the *shading* was what could not survive a true-colour
   blit.

### Notes

- `author_celebi_sheet.py` reproduces the sheet from the extracted graphic and
  refuses to write a file the bake cannot colour: 16x64, four 16x16 frames,
  exactly the four levels 255/170/85/0, fully opaque, every frame non-empty.
- Versions before 1.4.0 used the species' two-frame **party icon**, which had
  the opposite problem: a front-facing party picture with no side poses, so the
  descent was a party-icon bounce rather than the cart's four-tile flap.

## [1.4.1] - 2026-09-18

Seven more from play. Two of them were regressions 1.4.0 introduced.

### Fixed

1. **Celebi stopped descending entirely.** 1.4.0 pointed the sprite def at
   `assets/celebi.png`, but `Assets.resolve` returns a path **unchanged** unless
   it starts with `assets/generated/` (`src/render/Assets.lua:38`) — so the
   bare path went to `love.graphics.newImage` against the **game's** root,
   threw, and took the whole cutscene down with it. It now goes through
   `mod.assets:path`, which joins the mod's own directory. This is why the
   shrine produced no interaction at all.
2. **Kurt vanished without reaching the door.** The bench swap was keyed on the
   *stage*, but `ENGINE_KURT_MAKING_BALLS` is a **daily** flag: it clears when
   the day rolls over, and that is when KURT1 comes back to (3,2). Keyed on the
   stage alone, the swap held all through the wait, so the player was still
   talking to KURT2 at the bench (14,3) — and five `big_step DOWN` from the
   bench walks into the wall, so he never moved at all before vanishing. The
   swap follows the day now, exactly as the cart's callback does, which is also
   what puts him at the door for the exit.
3. **Kurt's "!" cue now finishes before he moves.** `waitsfx`: the movement
   queue holds until `Sound.sfxBusy()` clears.
4. **The shrine's "!" cue now finishes before the player steps back.** Same
   hold, on the same queue.
5. **Kurt no longer goes home.** 1.4.0 added a walk home; the cart does not do
   that — `EVENT_AZALEA_TOWN_KURT` is only ever *cleared* — and
   `AzaleaTownKurtScript` answers a press with `AzaleaTownKurtText3` ("Could
   you go see why ILEX FOREST is so restless?") and nothing else. He stays
   outside. That is what he does now.
6. **A finished save showed no Kurt at home.** The house callback hid both
   Kurts once the forest was restless, so loading a completed save found an
   empty house. KURT1 is shown again — he is home — which is also the cart's
   own state, since its callback returns early once the forest is restless and
   never hides anything further.

### Notes

- The exit path itself is unchanged: five `big_step DOWN` (or `RIGHT` then five
  `DOWN` when the player is below him), which from (3,2) lands on the door tile
  at (3,7) or (4,7). Fix 2 is what makes that path run at all.

## [1.4.0] - 2026-09-18

Eight more defects from play. Checked against `maps/KurtsHouse.asm`,
`maps/AzaleaTown.asm`, `maps/IlexForest.asm` and
`engine/overworld/scripting.asm`.

### Fixed

1. **The PokéCenter attendant did not turn to face the player.** `faceplayer` is
   a script command, and the engine's own `interactBody` does not do it — a mod
   that answers the press itself has to ask. Now applied to the attendant,
   Kurt and the granddaughter.
2. **Kurt's "!" had no sound.** Note for the record: the cart's `showemote` is
   **silent** — `Script_showemote` is `loademote` plus two `applymovement`s and
   nothing else — so this is the one deliberate addition in this release.
   `SFX_EMOTE` at the top of `main.lua` turns it off for cart behaviour.
3. **Kurt walked slower than SFX_FLY.** `big_step` is the cart's faster stride
   and the five of them have to fit inside the whoosh. `BIG_STEP_FRAMES = 8` —
   half the port's `STEP_FRAMES` — now drives both his exit and his approach.
4. **The ball arrived in the wrong direction.** `AzaleaTownPlayerLeavesKurts-
   HouseMovement` ends with `turn_head LEFT`; without it the player was left
   facing UP from the last step. The scene also now plays the cart's line order,
   which is not the obvious one: **all three lines first, then
   `verbosegiveitem GS_BALL`**.
5. **Kurt never went home.** This is beyond the cart, which leaves him outside
   for the rest of the game — `EVENT_AZALEA_TOWN_KURT` is only ever *cleared*.
   He now walks the three tiles back to his door, plays `SFX_EXIT_BUILDING` and
   goes in, and the house callback puts KURT1 back.
6. **Celebi's sprite and animation, reworked from scratch.** The party icon is
   gone. `assets/celebi.png` is a four-frame 16x16 sheet **authored for this
   mod**, drawn as a **true-colour** sheet — so `SpriteRenderer:resolveImage`
   hands it back untouched: real colours, real alpha, every drawn pixel fully
   opaque, no OW-palette bake and no shade-0 keying. The flap is driven from
   the descent's own iteration, as `GetCelebiSpriteTile` is, and reaches the
   draw call through the `SpriteRenderer:draw` wrapper.
7. **The step back at the shrine.** One correction to the report: the ROM's
   `IlexForestPlayerStepsDownMovement` is `fix_facing / slow_step DOWN /
   remove_fixed_facing` — **one** step, not two. It stays one. The turn
   afterwards (`turnobject PLAYER, DOWN`) is what faces the player away.
8. **Kurt spoke before he arrived.** The step queue now refuses to fire
   `onDone` while its last step is still walking, and his approach runs at the
   `big_step` cadence so the four tiles are covered before the closing line.

### Added

- `assets/celebi.png` — original art, drawn for this mod.
- 7 new checks.

## [1.3.0] - 2026-09-18

Eleven defects reported from play, checked one by one against
`pret/pokecrystal`'s own `maps/KurtsHouse.asm`, `maps/AzaleaTown.asm` and
`maps/IlexForest.asm`.

### Fixed

1. **Kurt did not move to his bench.** `KurtsHouseKurtCallback` is a
   `MAPCALLBACK_OBJECTS` that swaps KURT1 (3,2) for KURT2 (14,3) on
   `ENGINE_KURT_MAKING_BALLS`, and the twin for TWIN2 (11,4) with it. The mod
   now hides KURT1 and shows KURT2 while he studies, so leaving and coming back
   finds him at his desk. Gold has both Kurts (event flags 1854 / 1855).
2. **The granddaughter did not move or speak.** Gold has ONE twin object where
   Crystal has two, so she is *relocated* to (11,4) facing right — the same
   thing the player sees — and answers with `KurtsGranddaughterGSBallText`
   ("Grandpa's checking a BALL right now."), or `KurtsGranddaughterLonelyText`
   once he is gone.
3. **No "!" before Kurt ran out.** `showemote EMOTE_SHOCK, KURTSHOUSE_KURT1, 30`
   was missing. Added, on the object the player actually talked to.
4. **Kurt walked through the player and vanished too early.** `readvar
   VAR_FACING / ifequal UP, .GSBallRunAround` — when the player is standing
   below him he takes one `big_step RIGHT` before the five `DOWN`, which is what
   the second movement table is for. And `disappear` happens after the walk
   completes, at the door tile, not before.
5. **The wrong sound.** The cart plays `SFX_FLY` as he starts and
   `SFX_EXIT_BUILDING` as he vanishes; neither was being played. Both are now,
   in that order. (There is no footstep cue in the ROM — `SFX_FLY` *is* the
   cart's sound for both of Kurt's run-out arms.)
6. **The ball was handed over before the player reached Kurt.** The three-line
   hand-back now runs only after `AzaleaTownPlayerLeavesKurtsHouseMovement`
   (LEFT, LEFT, UP) has walked the player to him.
7. **Kurt outside had the wrong dialogue.** `AzaleaTownKurtScript` is ONE line
   — `AzaleaTownKurtText3` — and gives nothing. Talking to him no longer starts
   the hand-back; the coord tile does. (Answering the question: yes, he has
   exactly one line outside, and that is expected.)
8. **Two Kurts outside.** `ensureKurtOutside` was idempotent on the map def,
   which a runtime object is not serialized into. It is idempotent on the live
   `world.npcs` now, and despawns him once the scene has handed the ball back.
9. **The shrine had no emote and no step back.** `pause 20 / showemote
   EMOTE_SHOCK, PLAYER, 20` then `applymovement PLAYER,
   IlexForestPlayerStepsDownMovement` (`fix_facing / slow_step DOWN /
   remove_fixed_facing`) then `turnobject PLAYER, DOWN`. The movement table is
   **one** step, not two — that is the whole of it.
10. **Celebi: mirroring and the descent.** `UpdateCelebiPosition` swaps
    `FRAMESET_CELEBI_LEFT` / `CELEBI_RIGHT` as the sprite crosses the centre
    column; a party icon has two frames and no side poses, so the port mirrors
    the frame instead (`SpriteRenderer:draw`'s `forceFlip`, injected by a
    wrapper). The descent was also anchored to the shrine tile and stopped a
    full tile short of the player; it is anchored to the player's tile now.
    The `.ShiftY` / facing tests use the **raw** offset, as the ASM does —
    using the scaled one put both tests in the wrong place.
11. **Kurt did not appear after the catch.** `appear ILEXFOREST_KURT` at (8,29),
    four `step UP`, the closing line, four `step DOWN`, `disappear`. Gold has no
    Kurt object in Ilex Forest at all, so he is spawned.

### Added

- 44 new checks, including one per item above.

## [1.2.0] - 2026-09-17

### Fixed

- **The dialogue said "PLAYER" instead of the player's name.** Five lines were
  transcribed with the ASM macro `<PLAYER>`; the engine's token is `{PLAYER}`
  (`src/render/TextBox.lua:237`) and the tokenizer's pattern is `{..}` only, so
  the macro rendered literally. All five now use the token.
- **Celebi was the wrong colour.** The party icon is a 4-shade grayscale sheet,
  so its colours come entirely from the OBJ palette it is drawn with — and the
  sprite def carried `paletteId = 0` beside `palette = "PAL_OW_GREEN"`.
  `Palettes.spritePalette` tries `paletteId` first and **0 is truthy in Lua**,
  so the id silently won and painted Celebi with `PAL_OW_RED`. The id is gone
  and the name resolves.
- **Celebi's descent swept off the screen.** The ASM's sway amplitude is `$80`,
  which `SpriteAnims.cosine` turns into **±128 pixels** — wider than the
  160-pixel screen. Read literally it threw the 16x16 sprite off both edges and
  wrapped it round. The sway is now scaled into the cart's own "in window" band
  for this sprite (`8 * TILE_WIDTH + 4` .. `11 * TILE_WIDTH + 4`, i.e. the
  centre column ± 12) — the ASM's decaying-cosine shape, at the extent the ASM
  itself calls normal.

  *Corrected: this was later reverted, and the sway is the cart's own
  arithmetic again. The amplitude is a pixel count that goes straight into
  `SPRITEANIMSTRUCT_XOFFSET`, so the sweep really is ±128 pixels while it
  decays and ±56 once it bottoms out — scaling it into a window was this
  mod's own reading of the band, and it read as a wobble rather than the
  cart's swoop. `DESCENT.AMPLITUDE_START` in `main.lua` is the single knob if
  the sweep ever reads as too wide.*
- **Kurt did not leave the house.** `KurtsHouse.asm`'s `.NotMakingBalls` ends
  with him running out — shocked, five big steps down, `SFX_EXIT_BUILDING`,
  `disappear` — and he takes the ball with him. The mod handed it over inside
  the house instead. It now plays the exit.

### Added

- **The Azalea Town hand-back**, the other half that had been folded away.
  `AzaleaTown.asm` puts KURT_OUTSIDE at (6, 5) and runs
  `AzaleaTownCelebiScene` from `coord_event 9, 6`: the player is walked
  LEFT, LEFT, UP to him, he turns, the three `AzaleaTownKurtText` lines play,
  and `verbosegiveitem GS_BALL` hands the ball back. A Gen 2 mod cannot add a
  coord event, so the tile is watched on `world.stepped` instead — and talking
  to Kurt works too, so the scene cannot be missed by walking round him.
- A step-queue cutscene kind (`beginSteps` / `tickSteps`) driving both
  `applymovement` calls in the event, and `hideObject` for `Script_disappear`.
- 21 new checks: the token, the palette and the `paletteId` that shadowed it,
  the sway staying inside the cart's window, Kurt's exit and his disappearance,
  and the Azalea walk and hand-back.

### Changed

- The `restless` stage is no longer reached in Kurt's House. There is a new
  `left` stage in between: Kurt has run out with the ball, and the Azalea scene
  is what turns the forest restless and returns it.

## [1.1.1] - 2026-09-17

### Added

- **`DEBUG: skip KURT's 24-hour wait`**, a mod option. Crystal makes the player
  wait a day between handing the GS BALL to Kurt and getting it back, and the
  mod reads the day off the device clock — so reaching the shrine meant either
  changing the clock or waiting. The toggle removes the wait and nothing else:
  the hand-over, the re-talk and every line still run. With it off the wait is
  exactly as before.
- 6 checks driving the toggle both ways from a save parked in the same-day
  state, so the only difference between the two runs is the option.

### Notes

- The mod now has two switches for testing the event end to end in one sitting:
  this one, and `Reach the event without the HALL OF FAME` from 1.0.0. Both
  default off, so an untouched install is the cart's behaviour.

## [1.1.0] - 2026-09-17

### Added

- **The shrine cutscene.** Placing the GS BALL no longer cuts straight to the
  battle. The mod now plays the sequence the cart's script does, in its order:
  the player **steps back** one tile with `fix_facing` held (so the step does
  not turn them), then **Celebi descends** from above the shrine to just above
  the player, and only then does the battle start.
- The descent is transcribed from `CelebiShrineEvent` /
  `UpdateCelebiPosition` (`pokecrystal/engine/events/celebi.asm`): **160
  iterations of two frames each**, one pixel of descent per iteration, a cosine
  sway whose amplitude decays from `$80` by `$3` a frame down to `$3a`, the
  cart's own `float_up` / `float_down` Y nudge, and the left/right facing test
  against the centre column. The sway uses the engine's `SpriteAnims.cosine`,
  which is a transcription of the same `calc_sine_wave` the cart calls.
- **`SPRITE_CELEBI`**, built at runtime over the species' extracted party icon
  (the same def shape `World:breedmonSpriteDef` and `World:flyIconFor` build).
  The mod still ships no art at all.
- The world is held **busy** for the whole cutscene, so no press, menu or second
  step can land mid-descent.
- 26 new checks: the step back and its `fix_facing`, the sprite appearing on the
  right tile with `SPRITEMOVEDATA_POKEMON`, the descent, the sway, the
  despawn, and the battle starting only afterwards.

### Notes

- Two deliberate deviations from the cart, both forced by what Gold has:
  - the cart's descent sprite is a bespoke 16-tile, 4-frame graphic
    (`gfx/overworld/celebi.2bpp`); Gold has neither it nor the event, so the
    port uses the species' 16x16 party icon, whose own two-frame bounce is the
    flap. The icon has no side poses, so the cart's left/right facing cannot be
    shown;
  - the cart's OAM coordinates are absolute screen pixels. The port anchors the
    sprite to the shrine tile instead, which is the same position with the
    camera factored out -- the camera is static for the whole animation because
    the player is scripted and cannot move.

## [1.0.1] - 2026-09-16

### Fixed

- **Receiving the GS BALL is no longer silent.** The mod hands the ball over
  with `Bag.add` rather than through a script, so nothing rang the cue that
  every `verbosegiveitem` rings — the BICYCLE, the rods, the ITEMFINDER and
  every gym TM. Both hand-overs (the Goldenrod attendant and Kurt giving the
  ball back) now call `World:specialSound` with the item's own index, which is
  the engine's own give-item cue: `Sfx_Item` for an ordinary pocket and
  `Sfx_GetTm` for TM/HM. The ball is a `KEY_ITEM`, so it rings `Sfx_Item` — the
  same jingle as every other item acquisition.
- Placement matches the cart: `GiveItemScript` prints `.ReceivedItemText` and
  then does `waitsfx / specialsound`, so the cue starts with the received line
  already on screen.

### Added

- Four checks that the cue is rung, and only where it should be: on both
  hand-overs, and never on a refused offer or a press the mod does not own.
  They drive the engine's real `World:specialSound`, so they assert the sound
  the cart would make rather than a re-implementation of it.

## [1.0.0] - 2026-09-16

### Added

- The **GS BALL** as a real key item (index 251, `KEY_ITEM`, untossable),
  registered through `mod.content.items`.
- The **PokéCom attendant** in the Goldenrod Pokémon Center at (6,6), spawned
  as a runtime object and respawned on `map.entered`. He makes the offer once
  the player has entered the Hall of Fame, in Crystal's own words.
- **Kurt's study of the ball** in Kurt's House: he takes it, checks it, and —
  after the day rolls over — reports that it started to shake and hands it back
  with the "ILEX FOREST is restless!" lines.
- **The Ilex Forest shrine event** at (8,22): the shrine asks, the ball goes in,
  and CELEBI appears at level 30 in a `BATTLETYPE_CELEBI` battle. A catch banks
  `save.crystal.celebiCaught` and plays Kurt's closing line.
- A `World.interactBody` wrap that brackets the A press. Every state the vanilla
  cart has behaviour for falls through to the engine's own body, so Gold's
  shrine text and Gold's own Kurt conversation are preserved.
- The **HALL OF FAME** mod option, so the event can be reached without beating
  the Elite Four.
- A Crystal stand-down: the mod does nothing on a Crystal cart, which already
  has the event, detected from `itemSet[115]` rather than a version string.
- `tests/celebi_event_test.lua` — 59 checks over the real loader, the full
  quest, both fall-through directions, the day rollover, the catch and the
  Crystal stand-down.

### Notes

- Quest state lives in this mod's own save bucket rather than the event-flag
  space: `EVENT_FOREST_IS_RESTLESS` and its neighbours are Crystal-only ids, and
  in Gold those numbers belong to unrelated events.

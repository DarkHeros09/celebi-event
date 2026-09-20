-- The GS BALL — Pokémon Crystal's Celebi event, recreated for Gold and Silver.
--
-- Which carts it runs on: **Gold and Silver**.  Both are the same engine
-- (`GameVersion.engine` is "gs" for each) and share their map scripts, so every
-- coordinate, object index and item row this mod reads is the same on the two —
-- `tools/rom_manifest_silver.json` is derived from Gold's and its
-- `constants.itemOrder` and `constants.spriteOrder` are byte-identical, so
-- `items["GS_BALL"]` and `SPRITE_LINK_RECEPTIONIST` resolve the same way.  On
-- **Crystal** the mod stands down: that ROM already has the event, so it
-- registers nothing and returns — see crystalCart below for how the cart is
-- identified, and the manifest's `games: ["gen2"]` for the gate, which resolves
-- to all three version ids.
--
-- Crystal's event does not exist in Gold or Silver: those carts have the SHRINE
-- tile, the Kurt's House Celebi statue and the same map layouts, but every
-- script on the path is flavour text.  Comparing the carts at the map-event
-- level shows exactly that, and it is what makes this mod possible at all:
--
--   ILEX_FOREST      Crystal  bg_event  8,22 BGEVENT_UP   IlexForestShrineScript
--                    Gold     bg_event  8,22 BGEVENT_READ IlexForestShrineScript
--                    ^ the SAME tile and the SAME label, and in Gold the label
--                      is `jumptext Text_IlexForestShrine` -- four lines about
--                      "the forest's protector" and nothing else.
--
--   KURTS_HOUSE      identical objects (KURT 3,2 / TWIN 5,3 / SLOWPOKE 6,3 /
--                    KURT 14,3) and the same seven bg events, including the
--                    Celebi statue at 4,1.
--
--   AZALEA_TOWN      same eight warps, same eleven objects.
--
-- So the geometry, the objects and the shrine are already there; only the
-- scripts differ.  This mod supplies them.
--
-- HOW IT REACHES THE PRESS
-- A Gen 2 mod cannot author a script: `map_scripts` is gated off on Gold
-- (docs/mod-api-gen2-compat.md — `data.gen2Scripts` is the cart's own bytecode
-- pool and a Lua row list is not something src/script/gen2/Vm.lua can run).
-- What a mod *can* do is bracket the A press.  `World.interactBody` is the one
-- funnel every press goes through -- `World:interact`, the Gen 1 facade's
-- default, and a seam-stealing mod all land on it -- so this mod wraps it and
-- answers first.  Every branch falls through to the original when the quest is
-- not in a state the vanilla game has no behaviour for, so Gold's own shrine
-- text and Gold's own Kurt conversation are never lost.
--
-- The rest is public mod API: `mod.content.items` for the ball, `mod.world`
-- for spawnNpc / showText / askYesNo, `World:startBattle` with the engine's
-- own `BATTLETYPE_CELEBI`, and `mod.save` for the quest state.
local World2 = require("src.world.gen2.World")
local Bag = require("src.inventory.Bag")
local Mon = require("src.battle.gen2.Mon")
local Clock = require("src.core.gen2.Clock")
local HallOfFame = require("src.core.gen2.HallOfFame")
-- The engine's port of the cart's sprite-anim runtime (InitSpriteAnimStruct /
-- DoNextFrameForAllSprites).  Its `cosine` is a faithful transcription of
-- calc_sine_wave, which is exactly what CelebiEvent_Cosine calls, so the sway
-- is the engine's arithmetic rather than a re-derivation.
local SpriteAnims = require("src.ui.gen2.SpriteAnims")
local SpriteRenderer = require("src.render.SpriteRenderer")
local Sound = require("src.core.Sound")
-- `special FadeOutMusic` and `special RestartMapMusic`.  The engine hands both
-- to this module -- the VM's own hooks are `Music.fadeOut(2)` and
-- `World:restoreMapMusic` (src/world/gen2/World.lua:3833-3834) -- so those two
-- are what the transcriptions below call rather than a second fade of our own.
local Music = require("src.core.Music")

local GS_BALL = "GS_BALL"
local CELEBI = "CELEBI"
local CELEBI_LEVEL = 30

-- ../pokecrystal/maps/IlexForest.asm: the shrine bg_event, and the only tile
-- in the forest that runs the event.
local SHRINE_MAP, SHRINE_X, SHRINE_Y = "ILEX_FOREST", 8, 22

-- ---- the shrine cutscene ---------------------------------------------------
--
-- `special CelebiShrineEvent` (../pokecrystal/engine/events/celebi.asm) is not
-- a one-line battle-type setter -- it is the whole descent.  The script before
-- it steps the player back and then calls it, and it runs a sprite animation
-- for 160 iterations before it finally writes BATTLETYPE_CELEBI and returns:
--
--   ld a, 160 ; frame count
--   ld [wFrameCounter], a
--   .loop
--       ... GetCelebiSpriteTile / DoNextFrameForAllSprites
--       call CelebiEvent_CountDown     ; exits at 0
--       ld c, 2
--       call DelayFrames
--       jr .loop
--
-- so the descent is 160 iterations of two frames each.  Everything below is
-- transcribed from that file; the label names in the comments are its own.
local CELEBI_SPRITE = "SPRITE_CELEBI"

local DESCENT = {
  -- ld a, 160 ; frame count / ld c, 2 / call DelayFrames (port probe).
  -- `call CelebiEvent_CountDown` runs AFTER DoNextFrameForAllSprites, at the
  -- END of the iteration, so the countdown toggles the exit bit on the
  -- iteration that finds 0 -- which is the 161st drawn frame, because the 160
  -- decrements have already been spent.  The loop is 161 frames of two, not
  -- 160: see tickCutscene's ITERATIONS + 1.
  ITERATIONS = 160,
  FRAMES_PER_ITERATION = 2,
  -- depixel 0, 10, 7, 0.  `depixel` is (x tile, y tile, x pixel, y pixel) --
  -- ldpixel is `lb de, \2 * TILE_WIDTH + \4, \3 * TILE_WIDTH + \5` and
  -- InitSpriteAnimStruct stores e into XCOORD and d into YCOORD -- so the ROM
  -- really assembles `ld de, $0750` here: XCOORD = 10 * 8 = 80, the centre
  -- column of the 160-pixel screen, and YCOORD = 0 * 8 + 7 = 7.  An OAM object
  -- draws at (XCOORD - 8, YCOORD - 16), so the sprite starts at screen
  -- (72, -9): horizontally centred, nine pixels above the top edge.
  --
  -- (Earlier versions read the macro the other way round -- "OAM y = 0 * 8 + 8
  -- and x = 10 * 8 + 8" -- which is what put the whole descent 8 pixels right
  -- of centre and one pixel low.)
  XCOORD = 10 * 8,
  START_Y = 0 * 8 + 7,
  -- UpdateCelebiPosition's `cp 10 * TILE_WIDTH + 2`: YCOORD stops advancing
  -- here, so the sprite descends for 74 of the 160 iterations and then hovers,
  -- still flapping, for the rest.  The sprite's top is then at screen 66, two
  -- pixels into the player's own row.
  FREEZE_Y = 10 * 8 + 2,
  -- The world-pixel lead the cart's screen coordinates imply, relative to the
  -- PLAYER's cell.  Camera:follow puts the player's cell corner at screen
  -- (64, 64) -- `px - (viewW / 2 - 16)` -- and every sprite is drawn at its own
  -- world px, so screen = px - player.px + 64.  With the cart's drawn corner
  -- (XCOORD - 8, YCOORD - 16) that fixes
  --   px = player.px + (10 * 8 - 8) - 64 = player.px + 8
  --   py = player.py + YCOORD - 16 - 64 = player.py + YCOORD - 80
  X_LEAD = (10 * 8 - 8) - 64,
  Y_LEAD = -16 - 64,
  -- ld a, $80 / ld [SPRITEANIMSTRUCT_VAR4], a -- the cosine amplitude, decayed
  -- by `sub $3` a frame while it is above `cp $3a`.
  AMPLITUDE_START = 0x80,
  AMPLITUDE_FLOOR = 0x3a,
  AMPLITUDE_DECAY = 3,
  -- The amplitude is a PIXEL count and it is NOT scaled: `calc_sine_wave`
  -- returns `d * sin(...)` and the cart stores that straight into
  -- SPRITEANIMSTRUCT_XOFFSET, so the sway really is +/-128 pixels while the
  -- amplitude decays and +/-56 once it bottoms out.  Scaling it into a
  -- "window" was this mod's own reading of the band below, and a scaled sway
  -- is what made the descent read as a wobble instead of the cart's swoop.
  -- GetCelebiSpriteTile walks four tile groups; the authored sheet has the
  -- same four, one per row.
  FRAMES = 4,
  -- GetCelebiSpriteTile's counter (`d` in the ROM, `inc d` once per iteration,
  -- pushed and popped around the OAM work).  The tile it picks only CHANGES
  -- when the counter is 0, 3, 6 or 9 -- `.AddE` walks 3, 6, 9, 12 and every
  -- other value takes the `jr c, .done` arm and leaves the tile alone -- and at
  -- 12 it wraps the counter to $ff instead of advancing it, so the next `inc d`
  -- lands on 0 again.  A wing beat is therefore four tiles over THIRTEEN
  -- iterations (twenty-six frames), not the one tile per iteration this used to
  -- step: the flap ran about three times too fast, which is what made the
  -- descent read as a flicker rather than the cart's slow hover-flap.
  TILE_STEPS = 3,
  TILE_COUNTER_WRAP = 12,
  -- UpdateCelebiPosition compares `XCOORD + XOFFSET` against these three, in
  -- the cart's own 8-bit space: `11 * TILE_WIDTH + 4` and `8 * TILE_WIDTH + 4`
  -- are the band it treats as normal (the centre column +/- 12, which is when
  -- it does NOT nudge Y), `10 * TILE_WIDTH` is the facing test's split, and
  -- `-(3 * TILE_WIDTH + 2)` is that test's wrap guard ($e6 as a byte).
  SCREEN_CENTRE = 10 * 8,
  BAND_HI = 11 * 8 + 4,
  BAND_LO = 8 * 8 + 4,
  FACING_MAX = 256 - (3 * 8 + 2),
}

-- ../pokecrystal/maps/KurtsHouse.asm: KURT1 (3,2) is the Kurt who is home and
-- KURT2 (14,3) is the Kurt who is busy at the bench.  Both run the same
-- script in the cart, so both are Kurt here.
local KURT_MAP = "KURTS_HOUSE"
local KURT_INDEXES = { [1] = true, [4] = true }

-- ../pokecrystal/maps/KurtsHouse.asm.  The map has TWO of each: KURT1 (3,2)
-- standing at the door end, KURT2 (14,3) standing UP at the bench, and the
-- granddaughter at (5,3) or (11,4) beside him.  MAPCALLBACK_OBJECTS swaps them
-- on ENGINE_KURT_MAKING_BALLS, which is what puts Kurt at his desk with the
-- ball.  Gold has the two Kurts (event flags 1854 / 1855) but only ONE
-- granddaughter object, at (5,3) with no flag -- so she is MOVED rather than
-- swapped, which is the same thing the player sees.
local KURT1_FLAG, KURT2_FLAG = 1854, 1855
local TWIN_HOME_X, TWIN_HOME_Y = 5, 3
local TWIN_DESK_X, TWIN_DESK_Y = 11, 4

-- ../pokecrystal/maps/IlexForest.asm: Kurt waits at (8, 29) with
-- SPRITEMOVEDATA_STANDING_UP and walks four tiles up to the player.  Gold has
-- no such object -- Ilex Forest carries 14 and neither Kurt nor the Lass is
-- among them -- so he is spawned.
local KURT_WAIT_X, KURT_WAIT_Y = 8, 29
local KURT_APPROACH_STEPS = 4
local KURT_SPRITE = "SPRITE_KURT"

-- Sfx ids out of Gold's sfxOrder.  KurtsHouse.asm plays SFX_FLY as Kurt
-- starts running and SFX_EXIT_BUILDING as he vanishes at the door.
local SFX_FLY, SFX_EXIT_BUILDING = 25, 36
-- There is no emote cue, and there is deliberately no constant for one.
--
-- The cart's `showemote` is SILENT: Script_showemote is `loademote` then
-- ShowEmoteScript, which is `loademote EMOTE_FROM_MEM / applymovementlasttalked
-- .Show / pause 0 / applymovementlasttalked .Hide / end` -- two movements and a
-- wait, with no `playsound` anywhere in either one
-- (engine/overworld/scripting.asm:1065-1095).  An earlier build rang SFX_BUMP
-- with the "!" as an addition; the cart has no such sound, so neither does this.
--
-- The WAIT, on the other hand, is the cart's and is load-bearing.  `pause 0`
-- takes Script_pause's `and a / jr z` arm (scripting.asm:2224-2235), so it
-- leaves wScriptDelay exactly as `showemote` wrote it -- the `time` operand --
-- and then loops `ld c, 2 / call DelayFrames` that many times.  The bubble is
-- therefore held for time * 2 frames, and nothing written after the `showemote`
-- runs until it has finished.  tickSteps reproduces that by inserting the wait
-- itself; see the emote row there.
-- NPC.stepFrames for a `big_step`.  The port has one STEP_FRAMES = 16.
-- `slow_step` / `step` / `big_step` are three different step durations in the
-- cart (movement_slow_step $08 / movement_step $0c / movement_big_step $10,
-- macros/scripts/movement.asm:5-12) and the big one is the fast one: the five
-- of them have to fit inside SFX_FLY, and the port's default 16 left Kurt
-- plodding long after the whoosh had finished.
local BIG_STEP_FRAMES = 8
-- Script_pause's unit: `pause n` holds for n * 2 logic frames (the port's own
-- Vm.pauseLength, src/script/gen2/Vm.lua:2510), and ShowEmoteScript ends on a
-- `pause 0` that reads back the wScriptDelay `showemote` wrote -- so an emote's
-- `time` operand is worth the same two frames a unit.
local PAUSE_UNIT = 2
-- World:showEmote's emote ids; EMOTE_SHOCK is 0 (src/world/gen2/World.lua:99).
local EMOTE_SHOCK = 0

-- ../pokecrystal/maps/GoldenrodPokecenter1F.asm: the GS BALL is handed over by
-- a COORD EVENT on the two doorway tiles, not by talking to anybody.  The
-- receptionist carries no script of her own on either cart -- her object_event
-- points at the shared `ObjectEvent` -- and the scene moves her to the stairs
-- tile (0,7), plays her approach to whichever door the player came through,
-- hands the ball over and walks her back:
--
--   coord_event  3, 7, SCENE_GOLDENRODPOKECENTER1F_GS_BALL, ...GSBallSceneLeft
--   coord_event  4, 7, SCENE_GOLDENRODPOKECENTER1F_GS_BALL, ...GSBallSceneRight
--
-- The trigger is the step ONTO one of those two tiles -- the step that would
-- otherwise take the player back out to GOLDENROD_CITY -- so the hand-over
-- happens on the way OUT of the Center rather than on the way in.
--
-- Gold has the same map, tile for tile: the doorway warps at (3,7) and (4,7)
-- to GOLDENROD_CITY and the stairs warp at (0,7) to POKECENTER_2F are
-- identical, and every cell both of the cart's movements crosses is walkable
-- there -- checked through the engine's own Map/Permissions against the real
-- ROM, not read off the blocks.  Only the map's WIDTH differs: Crystal's is
-- wide enough for her to stand at (16,8), Gold's is ten cells.  So she is
-- spawned at the stairs tile the scene relocates her to, which is where the
-- cart's own `moveobject ... 0, 7` puts her anyway, rather than parked on a
-- tile Gold does not have.
local PC_MAP = "GOLDENROD_POKECENTER_1F"
-- The two doorway tiles the cart's coord events fire on.
local PC_DOOR_LEFT_X, PC_DOOR_Y = 3, 7
local PC_DOOR_RIGHT_X = 4
-- `moveobject ..., 0, 7`: the stairs tile, and where both walk-backs end.
local PC_STAIRS_X, PC_STAIRS_Y = 0, 7
-- SPRITE_LINK_RECEPTIONIST, the cart's own sprite for her -- and Gold's too.
-- The earlier stand-in used SPRITE_COOLTRAINER_F on the belief that this sprite
-- was Crystal-only; it is index 55 of Gold's own 162-entry sprite table, the
-- same index it holds in Crystal's, so she wears the cart's sprite.
local PC_RECEPTIONIST_SPRITE = "SPRITE_LINK_RECEPTIONIST"
-- PAL_NPC_BLUE, the palette her object_event names: the cart's own line is
--   object_event 16, 8, SPRITE_LINK_RECEPTIONIST, SPRITEMOVEDATA_STANDING_DOWN,
--                0, 0, -1, -1, PAL_NPC_BLUE, OBJECTTYPE_SCRIPT, 0, ObjectEvent, -1
-- and the `PAL_NPC_*` block is `const_def 1 << 3` over the eight PAL_OW_*
-- names (constants/sprite_data_constants.asm:15-38), so PAL_NPC_BLUE is 9 --
-- bit 3 is only the "not the sprite's default" marker, and `and OAM_PALETTE`
-- drops it, which is why PAL_NPC_BLUE lands on PAL_OW_BLUE's colours.
--
-- object_event packs the field as `dn \9, \<10>` -- palette in the HIGH nybble,
-- OBJECTTYPE_* in the low one (macros/scripts/maps.asm:113-138) -- and the
-- extractor stores it unswapped as the plain constant, so 9 is what the runtime
-- wants.  Palettes.objectPaletteId takes `p % 8` = 1 and hands back that OBJ
-- palette, which is what gives her the blue hair; a 0 here would mean "use the
-- sprite's own default" and she would come out in the wrong colours.
local PC_RECEPTIONIST_PALETTE = 9
-- `playmusic MUSIC_SHOW_ME_AROUND` -- 0x11 in the cart's music constants, and
-- Music_ShowMeAround at index 17 of Gold's own musicOrder (the same index it
-- holds in Crystal's).  World:playMusicId takes the id, exactly as the VM's
-- `playmusic` handler hands it over.
local MUSIC_SHOW_ME_AROUND = 17

-- Quest state, in this mod's own save bucket rather than the event-flag space:
-- EVENT_FOREST_IS_RESTLESS and friends are Crystal-only ids, and in Gold those
-- numbers belong to unrelated events.  Writing them would corrupt a real save.
local STAGE = "stage"
local GIVEN_DAY = "given_day"
-- KurtsHouse.asm gates the outcome on ENGINE_KURT_MAKING_BALLS, a DAILY flag.
-- The same test drives the object swap, so it lives here once.
local function sameDayAsGiven(mod, save)
  if mod.options:get("skip_kurt_wait") then return false end
  return mod.save:get(GIVEN_DAY) == Clock.weekday(save)
end
-- nil -> "have" -> "given" -> "left" -> "restless" -> "shrine" -> "caught".
-- "shrine" is the ball in the hole (EVENT_FOREST_IS_RESTLESS cleared, which is
-- what the cart's `clearevent` does there); "caught" is that plus the catch.

-- ../pokecrystal/maps/*.asm, transcribed.  \n is a line, \v is a `cont` that
-- scrolls without clearing, \f is a page break (src/render/TextBox.lua:5).
--
-- ------- why four of Kurt's lines open with "KURT: " and the rest do not
--
-- The dialogue-portraits mod answers "who is talking" from the A press that
-- started the conversation: World:interactBody resolves the object in front,
-- sets World.talkNpc to it and brackets the box, and the mod reads the object
-- back out.  Every conversation a press reaches therefore gets a face for free,
-- and Kurt has three of those here -- the ball he is handed in his house, and
-- the two follow-up talks.
--
-- Two of his do NOT have a press behind them: the AZALEA hand-back runs off the
-- coord tile (world.stepped) and the ILEX FOREST closing line off the battle
-- callback.  Nothing resolved an object for either, so the press-shaped lookup
-- finds nobody and those boxes come out with no face while the other three have
-- one.  (A mod cannot forge the engine's `world.interacted` to close the gap --
-- mod.events:emit is sandboxed to the mod's own prefix, Loader.lua:1281.)
--
-- The portraits mod's other route is the text: a box that OPENS with "NAME: "
-- names its own speaker, and `CustomArt/KURT.png` -- the file that mod ships
-- beside `CustomArt/SPRITE_KURT.png` for exactly this -- is what a "KURT: " box
-- resolves to.  It needs no press and no world state, so it is the route those
-- four boxes can use.
--
-- And it is the game's own convention for him rather than a token invented
-- here: the Gold ROM's own text opens TEN of Kurt's boxes with "KURT: " --
-- "KURT: Hi, {PLAYER}! You handled yourself like a real hero at the WELL.",
-- "KURT: Ah, {PLAYER}! I just finished your BALL. Here!" -- read out of the
-- cart, not assumed.  The three press-driven conversations are left exactly as
-- they were, because they already resolve.
local T = {
  -- GoldenrodPokecenter1F.asm: GoldenrodPokeCenter1FLinkReceptionistPlease*
  accept = "{PLAYER}, isn't it?\fCongratulations!\f"
    .. "As a special deal,\na GS BALL has been\nsent just for you!\f"
    .. "Please accept it!",
  comeAgain = "Please do come\nagain!",

  -- KurtsHouse.asm: KurtsHouseKurtWhatIsThatText
  kurtWhatIsThat = "Wh-what is that?\fI've never seen\none before.\f"
    .. "It looks a lot\nlike a # BALL,\vbut it appears to\nbe something else.\f"
    .. "Let me check it\nfor you.",
  -- KurtsHouseKurtImCheckingItNowText / KurtsHouseKurtAhHaISeeText
  kurtChecking = "I'm checking it\nnow.",
  kurtAhHa = "Ah-ha! I see!\nSo…",
  -- KurtsHouseKurtThisBallStartedToShakeText
  kurtShaking = "{PLAYER}!\fThis BALL started\nto shake while I\nwas checking it.\f"
    .. "There must be\nsomething to this!",
  -- AzaleaTown.asm: AzaleaTownKurtText1/2/3, the scene the cart plays outside
  -- Kurt's house.  Folded into the same conversation here, because Gold has no
  -- KURT_OUTSIDE object and a Gen 2 mod cannot add the coord event that runs it.
  --
  -- "KURT: " because no press starts this conversation -- see the note above.
  kurtRestless1 = "KURT: ILEX FOREST is\nrestless!\fWhat is going on?",
  kurtRestless2 = "KURT: {PLAYER}, here's\nyour GS BALL back!",
  kurtRestless3 = "KURT: Could you go see\nwhy ILEX FOREST is\nso restless?",

  -- IlexForest.asm: Text_ShrineCelebiEvent
  shrineEvent = "ILEX FOREST\nSHRINE…\f"
    .. "It's in honor of\nthe forest's\nprotector…\f"
    .. "Oh? What is this?\fIt's a hole.\nIt looks like the\f"
    .. "GS BALL would fit\ninside it.\f"
    .. "Want to put the GS\nBALL here?",
  -- Text_InsertGSBall
  insertBall = "{PLAYER} put in the\nGS BALL.",
  -- Text_KurtCaughtCelebi.  This is Kurt's LAST box in the event and the one
  -- the report names: the battle callback plays it, so no press ever resolved an
  -- object for it and the portraits mod had nobody to draw.  "KURT: " for the
  -- same reason as the three above -- see the note on the table.
  kurtCaught = "KURT: Whew, wasn't that\nsomething!\f"
    .. "{PLAYER}, that was\nfantastic. Thanks!\f"
    .. "The legends about\nthat SHRINE were\nreal after all.\f"
    .. "I feel inspired by\nwhat I just saw.\f"
    .. "It motivates me to\nmake better BALLS!\f"
    .. "I'm going!",

  received = "{PLAYER} received\nthe GS BALL.",

  -- KurtsHouse.asm: KurtsGranddaughterGSBallText -- TWIN2 while Kurt is at the
  -- bench.  She has relocated next to him and says what he is doing.
  twinChecking = "Grandpa's checking\na BALL right now.\fSo I'm waiting\ntill he's done.",
  -- KurtsGranddaughterLonelyText, once he has run out.
  twinLonely = "Grandpa's gone…\nI'm so lonely…",
  -- AzaleaTown.asm: AzaleaTownKurtText3.  This is the ONLY line Kurt has
  -- outside -- AzaleaTownKurtScript is three lines and a `closetext`, and the
  -- ball is handed over by the coord event, never by talking to him.
  kurtOutside = "Could you go see\nwhy ILEX FOREST is\nso restless?",
  pocketFull = "You have no room\nfor this!",
}

-- ---- helpers ---------------------------------------------------------------

local function saveOf(world)
  return world and world.game and world.game.save
end

local function dataOf(world)
  return world and world.game and world.game.data
end

-- `playsound SFX_*`.  World:playSfxNamed is the engine's sfx seam, and it takes
-- the ROM's own sfx id alongside the name so the cue is the cart's row rather
-- than a name this mod picked out.
local function playSfx(world, name, id)
  if world and world.playSfxNamed and name then
    world:playSfxNamed(name, id)
  end
end

local function hasBall(save)
  return save ~= nil and save.inventory ~= nil
    and (save.inventory[GS_BALL] or 0) > 0
end

-- The stage KURT answers to.
--
-- A GS BALL in the bag IS the "have" state, whatever this mod's own stage says.
-- The cart reads it that way too -- KurtsHouseKurtScript is gated on
-- `checkitem GS_BALL` -- and it matters here because **Crystal defines the item
-- natively**: a Crystal player can be carrying one this mod never handed over,
-- from the cart's own event, and this mod's stage would still be nil.
--
-- Both balls are the same key, which is why one test covers them:
-- `data.items` and `save.inventory` are keyed by the item's ID, and the engine's
-- own scripts resolve their item operand through World:itemIdByIndex
-- (src/world/gen2/World.lua:2764) before touching the bag -- so Crystal's native
-- GS_BALL and this mod's registered one both live at `save.inventory["GS_BALL"]`.
-- (`Bag.add`/`Bag.remove` write `inv[id]` for the same reason; Bag.lua:131-167.)
--
-- On Gold and Silver the ball only ever arrives from this mod's receptionist,
-- which sets "have" as it hands it over, so this is the same answer there.
local function kurtStage(mod, save)
  local stage = mod.save:get(STAGE)
  if stage == nil and hasBall(save) then return "have" end
  return stage
end

-- The cart's own gate on the GS Ball deal is `BattleTowerAction GSBALL`
-- returning GS_BALL_AVAILABLE, which the engine reads out of
-- `save.crystal.gsBall` (src/script/gen2/specials/battle_tower.lua:132).  In
-- the Virtual Console release that flag goes up once the player has entered the
-- Hall of Fame, which is the gate this mod uses by default --
-- `HallOfFame.hasEntered` is the engine's own answer to that question
-- (src/core/gen2/BattleTower.lua:235).  The HALL OF FAME option below relaxes
-- it, because a player who installs this mod to *see* the event should not have
-- to beat the Elite Four first.
local function qualified(mod, save)
  if not save then return false end
  if mod.options:get("open_from_start") == true then return true end
  local ok, entered = pcall(HallOfFame.hasEntered, save)
  return ok and entered == true
end

local function celebrate(save)
  save.crystal = save.crystal or {}
  return save.crystal
end

-- `faceplayer`: the object turns to look at the player.  The engine's own
-- interactBody does NOT do this -- it is a script command, and a mod that
-- answers the press itself has to ask for it.
local function facePlayer(npc, world)
  local p = world and world.player
  if not (npc and p) then return end
  local dx = (p.cellX or 0) - (npc.cellX or 0)
  local dy = (p.cellY or 0) - (npc.cellY or 0)
  if math.abs(dx) > math.abs(dy) then
    npc.facing = (dx > 0) and "right" or "left"
  else
    npc.facing = (dy > 0) and "down" or "up"
  end
end

-- ---- the item jingle -------------------------------------------------------

-- `specialsound` inside GiveItemScript (engine/overworld/scripting.asm:441-449)
-- is the cue EVERY `verbosegiveitem` rings -- the BICYCLE from the Goldenrod
-- Bike Shop, the rods and the ITEMFINDER from their givers, every gym TM, and
-- the POKéCOM receptionist's own `verbosegiveitem GS_BALL` on Crystal.  It is
-- what "receiving an item" sounds like.
--
-- The engine wires it into the script VM as `hooks.specialSound`
-- (src/world/gen2/World.lua:1165) and World:specialSound (ibid :2481) picks
-- SFX_GET_TM for the TM/HM pocket and SFX_ITEM for every other one.  This mod
-- hands the ball over with Bag.add rather than through a script, so nothing
-- rang it for us and the ball landed in the pack in silence.
--
-- The item's OWN index is passed, read off the merged record rather than
-- restated here, so the pocket test stays where the engine put it and the cue
-- is the engine's answer to "what does receiving this sound like" instead of
-- this mod's.  A nil index still lands on the ordinary item jingle, which is
-- the right answer for a KEY_ITEM.
--
-- Placement is the cart's: GiveItemScript does `writetext .ReceivedItemText`
-- and then `waitsfx / specialsound`, so the jingle starts with the received
-- line already on screen -- showText pushes the box before it returns, so the
-- two calls in that order are the same sequence.
local function playItemJingle(world)
  local items = dataOf(world) and dataOf(world).items
  local def = items and items[GS_BALL]
  local play = world and world.specialSound
  if not (def and type(play) == "function") then return end
  play(world, def.index)
end

-- ---- the Goldenrod hand-over ----------------------------------------------
--
-- `verbosegiveitem GS_BALL` inside GiveItemScript, which prints the received
-- line and rings the item jingle.  The scene that calls this is
-- beginGsBallScene, further down, where the movement queue it needs is in
-- scope.

local function giveBall(mod, world)
  local save, data = saveOf(world), dataOf(world)
  if not (save and data) then return end
  if not Bag.add(save, GS_BALL, 1, data) then
    world:showText(T.pocketFull)
    return
  end
  -- `setevent EVENT_GOT_GS_BALL_FROM_GOLDENROD_POKEMON_CENTER`, and with it
  -- EVENT_CAN_GIVE_GS_BALL_TO_KURT: the two flags the cart sets together are
  -- this one stage value, which is what both later scenes test.
  mod.save:set(STAGE, "have")
  world:showText(T.received)
  playItemJingle(world)
end

-- ---- the one cutscene at a time -------------------------------------------
--
-- Module-level because World:step is a class-level wrap and cannot close over
-- the mod table.  Two shapes run through it: the shrine's descent (a phase
-- machine, below) and a queue of one-tile steps, which is what both
-- `applymovement` calls in this event are.

local cutscene = nil

-- The last world the mod saw.  `mod.world` resolves lazily off the live game
-- and can be absent (a mid-session load, or a harness with no game injected),
-- so an event handler that needs a world has a second place to look rather
-- than silently doing nothing.
local liveWorld = nil

local function cutsceneRunning()
  return cutscene ~= nil
end

-- A queue of movement-command rows, walked one entry per tick.  The rows are
-- the script commands both exits are written in, so the transcription reads
-- next to the ASM it came from:
--
--   { who = npc, dir = "down" }                    `applymovement`, one tile
--   { wait = 40 }                                  `pause 20`
--   { emote = EMOTE_SHOCK, who = npc, time = 30 }  `showemote EMOTE_SHOCK, ..., 30`
--   { turn = "down" }                              `turnobject PLAYER, DOWN`
--   { fadeMusic = 2 }                              `special FadeOutMusic`
--   { sfx = "Sfx_Fly", sfxId = 25 }                `playsound SFX_FLY`
--   { sfxWait = true }                             `waitsfx`
--
-- `who:scriptStep` is the engine's own one-tile step, so the facing and the
-- walk animation are the engine's -- but NOT its collision: a scripted step in
-- this port is a forced step (src/world/gen2/Npc.lua:344) where the cart's
-- movement engine refuses a tile it cannot enter, so any route that has to
-- respect the map is computed before it is handed over (see routeToDoor).
local function beginSteps(mod, world, steps, onDone)
  if cutscene then return false end
  cutscene = {
    kind = "steps", mod = mod, world = world,
    steps = steps, i = 1, onDone = onDone,
  }
  return true
end

local function tickSteps(cs)
  local cur = cs.steps[cs.i]
  if not cur then
    -- The queue is exhausted, but the LAST step is still walking: `cs.i` is
    -- advanced when a step is STARTED.  Firing onDone here is what made Kurt
    -- talk before he arrived and the ball arrive mid-walk.
    local last = cs.steps[cs.i - 1]
    if last and last.who and last.who.moving then return end
    cutscene = nil
    local onDone = cs.onDone
    if onDone then onDone() end
    return
  end
  -- A step owns the object until it has walked the whole tile: `applymovement`
  -- is a blocking command, so nothing written after it runs while the object is
  -- still moving -- which is what keeps a `pause 30` behind a movement 30
  -- frames after the movement, not 30 frames after it was ORDERED.
  if cs.walking then
    if cs.walking.moving then return end
    cs.walking = nil
  end
  -- `pause n`: n * 2 frames, and the row is spent before the next one runs.
  -- Script_pause's own loop (`ld c, 2 / call DelayFrames` once per unit).
  if cur.wait then
    cur.left = (cur.left or cur.wait) - 1
    if cur.left <= 0 then cs.i = cs.i + 1 end
    return
  end
  -- `waitsfx`: the cue that has just been played is drained before the next
  -- command runs.  Script_specialsound ends with the same WaitSFX.
  if cur.sfxWait then
    if Sound.sfxBusy() then return end
    cs.i = cs.i + 1
    return
  end
  -- `playsound`: armed and over with on the same tick, so the row after it
  -- starts the very frame the cue does -- which is the whole reason the cart
  -- writes them as two commands.
  if cur.sfx then
    playSfx(cs.world, cur.sfx, cur.sfxId)
    cs.i = cs.i + 1
    return
  end
  -- `showemote emote, object, time`: the bubble goes up over `object`, SILENTLY,
  -- and the script then holds until it comes down -- two frames per unit, which
  -- is the `pause 0` ShowEmoteScript ends on.  Both halves are the cart's: no
  -- `playsound` is anywhere in Script_showemote, and the `pause 0` reads the
  -- `time` operand straight back out of wScriptDelay.  The bubble itself is
  -- given `time` frames and not the doubled hold, exactly as the engine's own
  -- showemote hands it over (src/script/gen2/Vm.lua:1243-1252), so a mod bubble
  -- lives as long as any other.  `object` is named when the bubble is not over
  -- the row's own object; the player is object 0.
  if cur.emote then
    local object = cur.object
    if not object and cur.who and cur.who.def then
      object = cur.who.def.index + 1
    end
    if cs.world.showEmote and object then
      cs.world:showEmote(cur.emote, object, cur.time)
    end
    cs.i = cs.i + 1
    local hold = (cur.time or 0) * PAUSE_UNIT
    if hold > 0 then table.insert(cs.steps, cs.i, { wait = hold }) end
    return
  end
  -- `special FadeOutMusic`: the map theme goes out now, and stays out until the
  -- next map load or an explicit RestartMapMusic.
  if cur.fadeMusic then
    Music.fadeOut(cur.fadeMusic)
    cs.i = cs.i + 1
    return
  end
  -- `turnobject`: the facing moves without a step, which is what the shrine's
  -- `turnobject PLAYER, DOWN` is between its two pauses.  Fixing the facing is
  -- the movement's own `fix_facing` / `remove_fixed_facing`, so the turn also
  -- releases it.
  if cur.turn then
    local target = cur.player or cs.world.player
    if target then
      target.fixedFacing = nil
      target.facing = cur.turn
    end
    cs.i = cs.i + 1
    return
  end
  -- `if self.moving then return false end` in scriptStep is what paces the
  -- queue: one tile finishes before the next is asked for.
  if cur.who.moving then return end
  cur.who:scriptStep(cur.dir)
  cs.walking = cur.who
  cs.i = cs.i + 1
end

-- Script_disappear / Script_appear.  The facade's toggleObject is the
-- sanctioned call and does the same work, but it needs a loaded map and the
-- live game; World:disappearObject is the method it wraps, so falling back to
-- it is the same call rather than a second implementation.
local function hideObject(mod, world, npc)
  local index = npc and npc.def and npc.def.index
  if not (index and world and world.map) then return end
  local api = mod.world
  if api and api.toggleObject then
    local ok, err = api:toggleObject(world.map.id, index, false)
    if ok then return end
    if err then
      mod.log:warn("could not hide object %d: %s", index, tostring(err))
    end
  end
  if world.disappearObject then world:disappearObject(index + 1) end
end

-- ---- Kurt ------------------------------------------------------------------

-- ../pokecrystal/maps/KurtsHouse.asm: `.NotMakingBalls` ends with Kurt running
-- out of the house -- `showemote EMOTE_SHOCK, KURTSHOUSE_KURT1, 30` /
-- `playsound SFX_FLY` / `applymovement ... KurtsHouseKurtExitHouseMovement`
-- (five big_steps DOWN) / `playsound SFX_EXIT_BUILDING` / `disappear`.  The
-- ball is NOT handed back here; he takes it with him and gives it to the
-- player outside, which is the next scene.
--
-- When the player is standing BELOW him (`readvar VAR_FACING` == UP) he would
-- walk straight through them, so the cart runs
-- `KurtsHouseKurtGoAroundPlayerThenExitHouseMovement` instead: one big_step
-- RIGHT, then the same five down.
local KURT_EXIT_STEPS = 5

-- ../pokecrystal/maps/AzaleaTown.asm: KURT_OUTSIDE stands at (6, 5) and the
-- scene is a `coord_event 9, 6`.  Talking to him there is AzaleaTownKurtScript
-- -- ONE line and a closetext, no item.  The ball comes from the coord event
-- alone, which is why the tile is the trigger and the talk is not.
local AZALEA_MAP = "AZALEA_TOWN"
local KURT_OUTSIDE_X, KURT_OUTSIDE_Y = 6, 5
local AZALEA_TRIGGER_X, AZALEA_TRIGGER_Y = 9, 6
-- Kurt stands at (6,5) and the house warp is (9,5).
local KURT_HOME_STEPS = 3

-- The map's object list is keyed by the object's own index, and both
-- World:objectEntity and WorldAPI:toggleObject read it back as `index + 1`.
local function objectIndexForFlag(world, mapId, flag)
  local def = world and world.maps and world.maps[mapId]
  for i, obj in ipairs(def and def.objects or {}) do
    if obj.eventFlag == flag then return i end
  end
end

local function setObjectVisible(mod, world, mapId, flag, visible)
  if not (world and world.map and world.map.id == mapId) then return end
  local index = objectIndexForFlag(world, mapId, flag)
  if not index then return end
  local api = mod.world
  if api and api.toggleObject then
    local ok, err = api:toggleObject(mapId, index, visible)
    if ok or err then return end
  end
  if visible and world.appearObject then
    world:appearObject(index + 1)
  elseif world.disappearObject then
    world:disappearObject(index + 1)
  end
end

-- A runtime object the mod spawned: WorldAPI:removeNpc is the call, and
-- World:removeRuntimeObject is the method it wraps.
local function despawnNpc(mod, world, npc)
  if not (npc and npc.id) then return end
  local api = mod.world
  if api and api.removeNpc then
    local ok, err = api:removeNpc(npc.id)
    if ok or err then return end
  end
  if world.removeRuntimeObject then
    world:removeRuntimeObject(npc.id, mod.id)
  end
end

-- The granddaughter.  Gold has ONE twin object (5, 3, no visibility flag)
-- where Crystal has two, so the cart's TWIN1/TWIN2 swap is done by moving her:
-- the same thing the player sees, without a second copy that could outlive the
-- scene.
--
-- She follows the same flag the swap does: TWIN2 while ENGINE_KURT_MAKING_BALLS
-- is set, TWIN1 -- home -- the rest of the time.  That is what puts her back at
-- (5,3) the moment the day rolls over and KURT1 returns to the door, and it is
-- where she stays for the rest of the quest, because the callback never touches
-- her again once the forest is restless.
local function moveTwin(world, atBench)
  for _, npc in ipairs(world and world.npcs or {}) do
    local def = npc.def or {}
    if def.sprite == "SPRITE_TWIN" then
      local x = atBench and TWIN_DESK_X or TWIN_HOME_X
      local y = atBench and TWIN_DESK_Y or TWIN_HOME_Y
      -- The movement type she was extracted with -- TWIN1 is
      -- SPRITEMOVEDATA_SPINRANDOM_SLOW -- remembered on the object rather than
      -- restated here, so the map's own data is what she goes back to.
      local homeKind = npc.celebiEventHomeKind
      if homeKind == nil then
        homeKind = npc.kind
        npc.celebiEventHomeKind = homeKind
      end
      if npc.cellX ~= x or npc.cellY ~= y then
        npc.cellX, npc.cellY = x, y
        npc.px, npc.py = x * 16, y * 16
      end
      if atBench then
        -- SPRITEMOVEDATA_SPINRANDOM_SLOW would keep turning her; Crystal's
        -- TWIN2 is SPRITEMOVEDATA_STANDING_RIGHT.
        npc.kind = "stand"
        npc.facing = "right"
      else
        npc.kind = homeKind
      end
      return npc
    end
  end
end

local function kurtTwin(world)
  for _, npc in ipairs(world and world.npcs or {}) do
    local def = npc.def or {}
    if def.sprite == "SPRITE_TWIN" then return npc end
  end
end

-- MAPCALLBACK_OBJECTS, KurtsHouseKurtCallback, transcribed against the mod's
-- own stage in place of the two cart flags it reads.
--
-- The cart's first test is `checkevent EVENT_FOREST_IS_RESTLESS / iftrue .Done`:
-- once the forest is restless the callback returns without touching ANYTHING,
-- so whoever is on the map stays on it.  Who that is at that point is set by the
-- exit itself -- KURT1 runs out of the house and `disappear` takes him off the
-- map -- so the house is EMPTY of Kurts until the shrine clears the flag again,
-- which is the point the normal ladder below starts running once more.  Showing
-- him through the restless stretch is what had a player watch "Grandpa's gone…"
-- from the doorway with Grandpa standing in it.
local function applyKurtHouse(mod, world)
  local stage = mod.save:get(STAGE)
  local restless = stage == "left" or stage == "restless"
  -- ENGINE_KURT_MAKING_BALLS is a DAILY flag, so the swap back to KURT1
  -- happens when the day rolls over -- NOT when the ball is handed over.  The
  -- same test puts Kurt at KURT1 (3,2), five tiles above the door, which is
  -- where the cart's exit stream is written from.
  local making = not restless and stage == "given"
    and sameDayAsGiven(mod, saveOf(world))
  setObjectVisible(mod, world, KURT_MAP, KURT1_FLAG, not making and not restless)
  setObjectVisible(mod, world, KURT_MAP, KURT2_FLAG, making)
  moveTwin(world, making)
end

-- `CanObjectMoveInDirection` is the cart's answer to "may this object step
-- here" (engine/overworld/npc_movement.asm:1) and `applymovement` runs through
-- it: a `big_step` into a wall simply ends the stream there, which is why the
-- cart's own route can be five `big_step DOWN` and nothing else.  The port's
-- scripted step is FORCED (src/world/gen2/Npc.lua:344), so the route has to be
-- right before it is handed over.  Map:objectStepPermitted is the port of the
-- same routine.
local ROUTE_DELTA = {
  down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 }, up = { 0, -1 },
}
-- Breadth-first, so the tie-breaks are what make the shape: down first puts the
-- vertical leg in before the horizontal one, which is the "down and then left"
-- walk out of the bench the cart's own stream implies.
local ROUTE_ORDER = { "down", "left", "right", "up" }

local function routeCellTaken(world, ignore, x, y)
  local player = world and world.player
  if player and player.cellX == x and player.cellY == y then return true end
  for _, npc in ipairs(world and world.npcs or {}) do
    if npc ~= ignore and not npc.hiddenByMovement
      and npc.cellX == x and npc.cellY == y then
      return true
    end
  end
  return false
end

-- The way out: a shortest walk from where Kurt is standing to the nearest warp
-- tile, over the engine's own collision and around whoever is standing there.
--
-- KURT1 at (3,2) gets exactly the cart's stream out of it -- five `big_step
-- DOWN` to the door at (3,7), or, with the player below him, one RIGHT and then
-- the five to the second door tile at (4,7), which IS the cart's go-around arm.
-- KURT2 at the bench (14,3) gets the walk the cart never has to write: down and
-- then left, across the room, to the same door -- where the cart's literal five
-- steps down walk him into the wall, because that stream is only ever run from
-- KURT1.
--
-- nil when the map cannot answer (no collision to ask, no door reachable), and
-- the caller falls back to the cart's own stream.
local function routeToDoor(world, npc)
  local map = world and world.map
  if not (map and map.objectStepPermitted and map.inBounds and map.warps) then
    return nil
  end
  if not (npc.cellX and npc.cellY) then return nil end
  local doors = {}
  for _, w in ipairs(map.warps or {}) do
    doors[w.y * 1024 + w.x] = true
  end
  if not next(doors) then return nil end

  local startKey = npc.cellY * 1024 + npc.cellX
  local seen, from = { [startKey] = true }, {}
  local queue, head = { { x = npc.cellX, y = npc.cellY } }, 1
  local goal
  while head <= #queue do
    local cur = queue[head]
    head = head + 1
    if doors[cur.y * 1024 + cur.x] then goal = cur break end
    for _, dir in ipairs(ROUTE_ORDER) do
      local d = ROUTE_DELTA[dir]
      local nx, ny = cur.x + d[1], cur.y + d[2]
      local key = ny * 1024 + nx
      if not seen[key] and map:inBounds(nx, ny)
        and map:objectStepPermitted(cur.x, cur.y, dir)
        and not routeCellTaken(world, npc, nx, ny) then
        seen[key] = true
        from[key] = { x = cur.x, y = cur.y, dir = dir }
        queue[#queue + 1] = { x = nx, y = ny }
      end
    end
  end
  if not goal then return nil end

  -- Walked backwards from the door, so the list is reversed on the way out.
  local back, key = {}, goal.y * 1024 + goal.x
  while from[key] do
    back[#back + 1] = from[key].dir
    key = from[key].y * 1024 + from[key].x
  end
  local route = {}
  for i = #back, 1, -1 do route[#route + 1] = { who = npc, dir = back[i] } end
  return route
end

local function kurtExitSteps(world, npc, playerFacingUp)
  local route = routeToDoor(world, npc)
  if route and #route > 0 then return route end
  -- The cart's own stream, for a map with no collision to ask: KURT1 (3,2) is
  -- five tiles above the door, and `readvar VAR_FACING / ifequal UP` adds the
  -- one step right that takes him past a player standing below him.
  local steps = {}
  if playerFacingUp then steps[#steps + 1] = { who = npc, dir = "right" } end
  for _ = 1, KURT_EXIT_STEPS do
    steps[#steps + 1] = { who = npc, dir = "down" }
  end
  return steps
end

local function beginKurtExit(mod, world, npc, playerFacingUp)
  -- The cart's `.NotMakingBalls`, command for command:
  --
  --   special FadeOutMusic
  --   pause 20
  --   showemote EMOTE_SHOCK, KURTSHOUSE_KURT1, 30
  --   turnobject PLAYER, DOWN / playsound SFX_FLY / applymovement ...
  --   playsound SFX_EXIT_BUILDING / disappear / waitsfx / special RestartMapMusic
  --
  -- Three things about that list are easy to get wrong, and all three are the
  -- cart's:
  --
  --   * the `showemote` is SILENT.  Script_showemote is `loademote` plus two
  --     applymovements and a wait, with no `playsound` in it
  --     (engine/overworld/scripting.asm:1065-1095), so the "!" goes up without a
  --     cue.  An earlier build rang SFX_BUMP with it; the cart does not.
  --   * the `showemote` HOLDS.  Its `pause 0` takes Script_pause's
  --     `and a / jr z` arm, leaving wScriptDelay as the `time` operand, and then
  --     loops that many times at two frames each -- 60 frames for the 30 here.
  --     Nothing after it runs until the bubble is down, which is what keeps the
  --     "!" off the walk; tickSteps inserts that wait itself.
  --   * the exit sound is a SEPARATE command from the whoosh.  `playsound
  --     SFX_FLY` fires as he starts running and `playsound SFX_EXIT_BUILDING` as
  --     he reaches the door, with the whole movement between them -- playing
  --     SFX_FLY first and THEN holding the queue until it finished put the
  --     whoosh a full sound ahead of the animation.
  local steps = {}
  steps[#steps + 1] = { fadeMusic = 2 }
  steps[#steps + 1] = { wait = 20 * PAUSE_UNIT }
  steps[#steps + 1] = {
    who = npc, emote = EMOTE_SHOCK, time = 30,
  }
  steps[#steps + 1] = { sfx = "Sfx_Fly", sfxId = SFX_FLY }
  for _, row in ipairs(kurtExitSteps(world, npc, playerFacingUp)) do
    steps[#steps + 1] = row
  end
  steps[#steps + 1] = { sfx = "Sfx_ExitBuilding", sfxId = SFX_EXIT_BUILDING }
  steps[#steps + 1] = { sfxWait = true }
  -- `big_step` is the cart's faster stride, and the five of them have to fit
  -- inside SFX_FLY: the port's default is STEP_FRAMES = 16.
  if npc then npc.stepFrames = BIG_STEP_FRAMES end
  return beginSteps(mod, world, steps, function()
    -- `disappear KURTSHOUSE_KURT1`: the two sounds and the walk have all been
    -- waited out by the queue, and the map tune comes back behind them.
    hideObject(mod, world, npc)
    if world.restoreMapMusic then world:restoreMapMusic() end
  end)
end

local function kurtOutside(world)
  for _, npc in ipairs(world and world.npcs or {}) do
    local def = npc.def or {}
    if def.owner == "celebi_event" and def.sprite == KURT_SPRITE then
      return npc
    end
  end
end

-- The cart's order, which is not the obvious one: all THREE lines play first,
-- and `verbosegiveitem GS_BALL` comes after them --
--
--   writetext AzaleaTownKurtText1 / promptbutton
--   turnobject AZALEATOWN_KURT_OUTSIDE, RIGHT
--   writetext AzaleaTownKurtText2 / promptbutton
--   writetext AzaleaTownKurtText3 / waitbutton
--   verbosegiveitem GS_BALL
--   turnobject AZALEATOWN_KURT_OUTSIDE, LEFT
--
-- He then STAYS outside, which is the cart's behaviour: EVENT_AZALEA_TOWN_KURT
-- is only ever cleared, and AzaleaTownKurtScript answers a press with
-- AzaleaTownKurtText3 and nothing else.
local function azaleaHandBack(mod, world, kurt)
  local save = saveOf(world)
  world:showText(T.kurtRestless1, function()
    if kurt then kurt.facing = "right" end
    world:showText(T.kurtRestless2, function()
      world:showText(T.kurtRestless3, function()
        Bag.add(save, GS_BALL, 1, dataOf(world))
        world:showText(T.received, function()
          if kurt then kurt.facing = "left" end
        end)
        playItemJingle(world)
      end)
    end)
  end)
  mod.save:set(STAGE, "restless")
end

-- `AzaleaTownPlayerLeavesKurtsHouseMovement` (LEFT, LEFT, UP, turn_head LEFT)
-- then the three lines.  Only the coord tile runs this -- talking to Kurt
-- outside is AzaleaTownKurtScript, which says one line and gives nothing.
local function beginAzaleaScene(mod, world)
  if cutscene then return false end
  local kurt = kurtOutside(world)
  local steps = {
    { who = world.player, dir = "left" },
    { who = world.player, dir = "left" },
    { who = world.player, dir = "up" },
  }
  return beginSteps(mod, world, steps, function()
    -- `turn_head LEFT`, the last entry of AzaleaTownPlayerLeavesKurtsHouse-
    -- Movement.  Without it the player is left facing UP from the step, which
    -- is the wrong direction to be handed the ball in.
    if world.player then world.player.facing = "left" end
    azaleaHandBack(mod, world, kurt)
  end)
end

-- GoldenrodPokecenter1F_GSBallSceneLeft / ...GSBallSceneRight, transcribed.
-- The two scenes are the same nine commands with a different approach and a
-- different walk-back, so one function takes the side.  See the constants at
-- PC_MAP for the trigger and for what Gold shares with the cart's map.
--
-- Returns true only when the scene is actually running, which is what lets the
-- caller decide whether to hold the exit warp back -- see the world.stepped
-- handler at the bottom of this file.
local function beginGsBallScene(mod, world, right)
  if cutscene then return false end
  local save = saveOf(world)
  -- `checkevent EVENT_GOT_GS_BALL_FROM_GOLDENROD_POKEMON_CENTER / iftrue .cancel`
  -- -- once the ball has been handed over, walking out again does nothing.
  if mod.save:get(STAGE) ~= nil then return false end
  -- ...and a ball ALREADY IN THE BAG is that same state, however it got there.
  -- This is what keeps the receptionist from handing over a second one on
  -- Crystal, where the cart's own event can have given one and this mod's stage
  -- cannot know about it.  The bag is the authority, exactly as it is for KURT
  -- (see kurtStage): one GS BALL, from either source, suppresses the scene.
  if hasBall(save) then return false end
  -- `setval BATTLETOWERACTION_GSBALL / special BattleTowerAction / ifequal
  -- GS_BALL_AVAILABLE, .gsball` -- and the cart's own bare `end` when it is
  -- not, with no line and no box.  That is the HALL OF FAME gate.
  if not qualified(mod, save) then return false end

  -- `moveobject RECEPTIONIST, 0, 7` / `disappear` / `appear`.  A runtime object
  -- is spawned where it stands, so the move and the appearance are the same
  -- act here -- and the position is the cart's stairs tile.
  local objDef = {
    sprite = PC_RECEPTIONIST_SPRITE,
    x = PC_STAIRS_X, y = PC_STAIRS_Y,
    movement = 6, -- SPRITEMOVEDATA_STANDING_DOWN
    radius = { x = 0, y = 0 },
    hours = { -1, -1 },
    palette = PC_RECEPTIONIST_PALETTE, type = 0, sight = 0,
  }
  local api = mod.world
  local npcId
  if api then
    npcId = api:spawnNpc(PC_MAP, objDef)
  elseif world.addRuntimeObject then
    npcId = world:addRuntimeObject(PC_MAP, objDef, mod.id)
  end
  local npc
  for _, n in ipairs(world.npcs or {}) do
    if n.id == npcId then npc = n break end
  end

  -- The doorway the player stepped out by, and the two movements that depend on
  -- it: UP then one RIGHT per tile from the stairs (three for the left door,
  -- four for the right), ending with `turn_head DOWN` so she faces the player;
  -- and the mirror of it going back, LEFT the same number of times then DOWN.
  local doorX = right and PC_DOOR_RIGHT_X or PC_DOOR_LEFT_X
  local span = doorX - PC_STAIRS_X
  local function approach()
    local steps = {}
    if not npc then return steps end
    steps[1] = { who = npc, dir = "up" }
    for i = 1, span do steps[#steps + 1] = { who = npc, dir = "right" } end
    return steps
  end
  local function walkBack()
    local steps = {}
    if not npc then return steps end
    for i = 1, span do steps[#steps + 1] = { who = npc, dir = "left" } end
    steps[#steps + 1] = { who = npc, dir = "down" }
    return steps
  end

  -- `playmusic MUSIC_SHOW_ME_AROUND`, which the queue has no row for because no
  -- other script in this event plays a song.
  --
  -- NO `playsound` here, and that is the one place this deliberately leaves the
  -- cart's command list.  `.gsball` opens with `playsound SFX_EXIT_BUILDING`,
  -- which in the cart is the cue that goes with the hero actually walking out
  -- of the building: the coord event fires on the step onto the doorway tile and
  -- the step's own warp to GOLDENROD_CITY follows straight after it.  Here the
  -- hero stops on that tile instead -- the scene stands the exit warp down so
  -- the receptionist can reach him -- so nobody has left and the leaving cue
  -- would be a sound with nothing behind it.  Everything else in the list is
  -- kept, including the SFX_EXIT_BUILDING at the other end, which is hers: it
  -- rings as she vanishes back down the stairs.
  if world.playMusicId then world:playMusicId(MUSIC_SHOW_ME_AROUND) end

  local function handOver()
    -- `turnobject PLAYER, UP`: the cart faces the player into the room before
    -- the box goes up.  They stepped DOWN onto the doorway to leave, so this is
    -- also what turns them round to face the receptionist.
    if world.player then world.player.facing = "up" end
    -- `writetext ...PleaseAcceptGSBallText / waitbutton / verbosegiveitem
    -- GS_BALL / setevent / setevent / writetext ...PleaseDoComeAgainText`.
    world:showText(T.accept, function()
      giveBall(mod, world)
      world:showText(T.comeAgain, function()
        beginSteps(mod, world, walkBack(), function()
          -- `special RestartMapMusic` / `disappear RECEPTIONIST` /
          -- `playsound SFX_EXIT_BUILDING`, in that order and only then.
          if world.restoreMapMusic then world:restoreMapMusic() end
          despawnNpc(mod, world, npc)
          playSfx(world, "Sfx_ExitBuilding", SFX_EXIT_BUILDING)
        end)
      end)
    end)
  end

  -- Without a receptionist the hand-over still happens rather than the ball
  -- being lost to a failed spawn; only the walk is skipped, as at the shrine.
  if not npc then
    handOver()
    return true
  end
  return beginSteps(mod, world, approach(), function()
    -- `turn_head DOWN`, the last entry of the approach movement.
    npc.facing = "down"
    handOver()
  end)
end

-- The cart's KURT_OUTSIDE object, spawned because Gold has no such object and
-- a Gen 2 mod cannot add the coord event that runs it.  Idempotent on
-- world.npcs rather than on the map def: a runtime object is not serialized,
-- so a re-entry has to be able to tell "already standing there" from "the
-- first one was rebuilt away", and only the live list can.
local function ensureKurtOutside(mod, world)
  if not (world and world.map and world.map.id == AZALEA_MAP) then return end
  local existing = kurtOutside(world)
  if mod.save:get(STAGE) ~= "left" then
    -- He has handed the ball over; the copy outside must not survive it.
    if existing then despawnNpc(mod, world, existing) end
    return
  end
  if existing then return end
  local objDef = {
    sprite = KURT_SPRITE,
    x = KURT_OUTSIDE_X, y = KURT_OUTSIDE_Y,
    movement = 8, -- SPRITEMOVEDATA_STANDING_LEFT
    radius = { x = 0, y = 0 },
    hours = { -1, -1 },
    palette = 0, type = 0, sight = 0,
  }
  local api = mod.world
  if api then
    api:spawnNpc(AZALEA_MAP, objDef)
  elseif world.addRuntimeObject then
    world:addRuntimeObject(AZALEA_MAP, objDef, mod.id)
  end
end

-- Returns true when this mod owned the press, false to fall through to Gold's
-- own Kurt conversation.
local function kurtTalk(mod, world, npc)
  facePlayer(npc, world)
  local save = saveOf(world)
  -- The ball is the trigger as well as the stage: see kurtStage.
  local stage = kurtStage(mod, save)

  if stage == "have" then
    if not hasBall(save) then
      -- the ball went missing (a save edited under us) -- let the cart talk
      mod.save:set(STAGE, nil)
      return false
    end
    world:showText(T.kurtWhatIsThat, function()
      Bag.remove(save, GS_BALL, 1)
      mod.save:set(STAGE, "given")
      mod.save:set(GIVEN_DAY, Clock.weekday(save))
      world:showText(T.kurtChecking)
    end)
    return true
  end

  if stage == "given" then
    -- KurtsHouse.asm gates the outcome on ENGINE_KURT_MAKING_BALLS, a DAILY
    -- flag: "I'm checking it now" the same day, the shaking line after the
    -- rollover.  This is that gate, keyed on the weekday the ball was handed
    -- over -- the cart's own definition of a day having passed.
    --
    -- The SKIP KURT'S WAIT option collapses it, so the whole quest can be
    -- walked in one sitting without changing the device clock.  It only
    -- removes the wait: the hand-over, the re-talk and every line still run.
    if sameDayAsGiven(mod, save) then
      world:showText(T.kurtChecking, function()
        world:showText(T.kurtAhHa)
      end)
      return true
    end
    -- The shaking line, then `.NotMakingBalls`: the music goes, the "!" goes up,
    -- and he runs out of the house with the ball.  beginKurtExit is that sequence
    -- command for command, because the ORDER of the fade, the bubbles and the
    -- two sounds is the timing.
    world:showText(T.kurtShaking, function()
      mod.save:set(STAGE, "left")
      -- `readvar VAR_FACING / ifequal UP, .GSBallRunAround` -- read before the
      -- cart's own `turnobject PLAYER, DOWN`, which is why it is read here.
      local facingUp = world.player and world.player.facing == "up"
      beginKurtExit(mod, world, npc, facingUp)
    end)
    return true
  end

  return false
end

-- The granddaughter's half of the same scene.  Crystal gives her two objects
-- with two scripts; Gold's single twin answers both, and WHICH of the two she is
-- standing as is the same test the object swap uses.
local function twinTalk(mod, world, npc)
  facePlayer(npc, world)
  local stage = mod.save:get(STAGE)
  if stage == "given" and sameDayAsGiven(mod, saveOf(world)) then
    -- KurtsGranddaughterGSBallText: TWIN2, at the bench beside him, with
    -- EVENT_GAVE_GS_BALL_TO_KURT set.
    world:showText(T.twinChecking)
    return true
  end
  if stage == "left" or stage == "restless" then
    -- KurtsGranddaughterLonelyText: TWIN1, home, and
    -- EVENT_FOREST_IS_RESTLESS is what she is answering -- KURT is really gone
    -- for exactly this stretch (the shrine clears it again).
    world:showText(T.twinLonely)
    return true
  end
  -- Every other state is one the cart's TWIN1 answers out of flags this mod
  -- does not own -- the apricorn wait, the FAST SHIP, the WELL -- and Gold's own
  -- twin conversation is those words, so the press falls through to it.  That
  -- is deliberate on both ends: it keeps the mod off vanilla's lines, and it is
  -- what stops "Grandpa's gone… I'm so lonely…" being said from the doorway of a
  -- house KURT is standing in.
  return false
end

-- ---- the shrine ------------------------------------------------------------

-- The cart's OAM coordinates are 8-bit and several of the routines rely on the
-- wrap.  Every offset the descent computes is a signed byte, so read it back
-- the way the OAM writer does.
local function signedByte(value)
  local n = math.floor(value or 0) % 256
  if n >= 128 then return n - 256 end
  return n
end

-- The descent sprite -- the player's own file in assets/, not shipped with the
-- mod -- four 16x16 frames, one per step
-- of the cart's GetCelebiSpriteTile, re-cut from the cart's own 16x64
-- overworld sheet (`gfx/overworld/celebi.2bpp`, engine/events/celebi.asm,
-- SpecialCelebiGFX).
--
-- Gold has NO Celebi overworld sprite of its own to cut at runtime -- the
-- constant is Crystal's -- so this is the one picture the mod carries.  It is
-- NOT a party icon standing in for Celebi (every version through 1.3.x), and
-- NOT a true-colour drawing either (1.4.0 and 1.4.1): see the sprite
-- definition in ensureCelebiSprite for why the colours have to come from the
-- game's own palette rather than from the PNG.
local CELEBI_SHEET = "assets/celebi.png"

-- `Assets.resolve` (src/render/Assets.lua:36) only rewrites a path that points
-- into the engine's own extracted cache; anything else is handed to
-- love.graphics.newImage unchanged, which resolves it against the GAME's root
-- rather than the mod's.  So a bare "assets/..." throws and takes the whole
-- cutscene with it -- mod.assets:path is the helper that joins the mod's own
-- directory, and the literal the gate looks for is avoided here on purpose.
local function celebiSheetPath(mod)
  if mod and mod.assets and mod.assets.path then
    local ok, path = pcall(function() return mod.assets:path(CELEBI_SHEET) end)
    if ok and path then return path end
  end
  return CELEBI_SHEET
end

-- Is the player's sheet actually installed?
--
-- The sheet is deliberately NOT shipped (see assets/README.md): it is a re-cut
-- of the cart's own overworld graphic, so it is Nintendo's, and this mod leaves
-- it to the player rather than redistributing it.  mod.assets:info is the
-- sandboxed existence test -- it resolves inside the mod's own directory and
-- answers nil for anything that is not there.
--
-- When the API is unavailable there is nothing to ask, so the old behaviour
-- stands and the definition is built anyway.
local function sheetInstalled(mod)
  if not (mod and mod.assets and mod.assets.info) then return true end
  local ok, info = pcall(function() return mod.assets:info(CELEBI_SHEET) end)
  if not ok then return true end
  return info ~= nil
end

local function ensureCelebiSprite(mod, world)
  local data = dataOf(world)
  local sprites = data and data.gen2Sprites
  if not sprites then return nil, "this dataset has no sprite table" end
  if sprites[CELEBI_SPRITE] then return sprites[CELEBI_SPRITE] end
  -- No sheet, no sprite.  Registering the definition anyway would throw inside
  -- Assets.imageData on the first draw and take the whole cutscene down with
  -- it, so decline here and let the caller descend without a sprite.
  if not sheetInstalled(mod) then
    return nil, "assets/celebi.png is not installed"
  end
  local def = {
    id = CELEBI_SPRITE,
    image = celebiSheetPath(mod),
    frames = DESCENT.FRAMES,
    frameWidth = 16, frameHeight = 16,
    walker = false,
    spriteType = "STILL_SPRITE",
    -- FOUR SHADES, baked through the game's own OW palette.
    --
    -- The sheet is white/grey/grey/black and carries no colour of its own.
    -- SpriteRenderer:resolveImage runs it through getObpImage, which keys
    -- OBJ colour 0 (shade 0, white) to alpha and maps shades 1-3 onto the
    -- palette Palettes.spritePalette resolves for this sprite -- the
    -- PAL_OW_GREEN the cart draws the shrine sprite with.  The colours are
    -- therefore the game's own, and they follow the time of day and the COLOR
    -- option like every other sprite on the map.
    --
    -- That palette's colours 1-3 are #FF9C52 (orange), #3ABD19 (green) and
    -- black at every time of day, so the Celebi that descends is an
    -- orange-bodied, green-accented hover -- which is what the real event
    -- shows, and what the reference screenshot of it shows.
    --
    -- `trueColor` used to be set here, which hands the sheet back untouched
    -- and skips the palette bake entirely: that is why 1.4.0/1.4.1 drew a
    -- green and blue Celebi that looked nothing like the game's.
    palette = "PAL_OW_GREEN",
    species = CELEBI,
  }
  sprites[CELEBI_SPRITE] = def
  return def
end

local function spawnCelebi(world)
  local def, err = ensureCelebiSprite(cutscene and cutscene.mod, world)
  if not def then
    return nil, err or "no CELEBI icon in this dataset"
  end
  local objDef = {
    sprite = CELEBI_SPRITE,
    x = SHRINE_X, y = SHRINE_Y,
    -- SPRITEMOVEDATA_POKEMON ($16).  This is not decoration: NPC.new sets
    -- `bouncing` from it, and NPC:bounceFrame is what swaps the icon's two
    -- frames -- SPRITEMOVEDATA_POKEMON's OBJECT_ACTION_BOUNCE
    -- (engine/overworld/map_object_action.asm:184).  That is the only flap the
    -- party icon can give, where the cart's bespoke 16-tile graphic has four.
    movement = 0x16,
    radius = { x = 0, y = 0 },
    hours = { -1, -1 },
    palette = 0, type = 0, sight = 0,
  }
  -- `mod.world` is resolved lazily off the live game, so it can be absent when
  -- the entry chunk ran before Game2 injected itself.  World:addRuntimeObject
  -- is the method WorldAPI:spawnNpc is a one-line wrapper around, so falling
  -- back to it is the same call rather than a second implementation.
  local api = cutscene.mod.world
  local owner = cutscene.mod.id
  local npcId
  if api then
    npcId = api:spawnNpc(SHRINE_MAP, objDef)
  else
    npcId = world:addRuntimeObject(SHRINE_MAP, objDef, owner)
  end
  if not npcId then return nil, "could not place CELEBI" end
  for _, npc in ipairs(world.npcs or {}) do
    if npc.id == npcId then return npc end
  end
  return nil, "CELEBI did not spawn"
end

-- The sprite's place on screen, in the port's world pixels.  The cart works
-- in absolute OAM screen coordinates because the camera is static for the whole
-- animation -- the player is scripted and cannot move -- so anchoring to the
-- player's cell is that same position with the camera factored out.  It is the
-- player's cell and not the shrine's on purpose: the freeze point is two pixels
-- into the player's own row, so the shrine would stop the sprite a full tile
-- short.
local function positionDescent(cs)
  local npc = cs.npc
  if not npc then return end
  local anchor = (cs.world and cs.world.player)
    or { cellX = SHRINE_X, cellY = SHRINE_Y + 1 }
  npc.px = anchor.cellX * 16 + DESCENT.X_LEAD + cs.xOffset
  npc.py = anchor.cellY * 16 + DESCENT.Y_LEAD + cs.y
  npc.facing = cs.facing
  -- The cart swaps FRAMESET_CELEBI_LEFT / CELEBI_RIGHT as the sprite crosses
  -- the centre column.  The sheet has no side poses, so the equivalent
  -- is the mirror -- see the SpriteRenderer:draw wrap in the entry chunk, which
  -- reads this flag.
  if npc.sprite then
    npc.sprite.celebiEventMirror = (cs.facing == "left")
    -- Read by the SpriteRenderer:draw wrap, which passes it as frameOverride.
    -- NPC:draw hard-codes that to bounceFrame(), which is nil for a
    -- STILL_SPRITE, so the sheet would otherwise sit on frame 0 forever.
    npc.sprite.celebiEventFrame = cs.frame
  end
end

-- UpdateCelebiPosition, one iteration.
local function advanceDescent(cs)
  local npc = cs.npc
  if not npc then return end

  -- GetCelebiSpriteTile, tile group for the counter this iteration was called
  -- with, `inc d` afterwards -- including while the sprite is frozen, which is
  -- what keeps the descent a hover rather than a fall.  See DESCENT.TILE_STEPS
  -- for why the tile only changes every third iteration.
  local counter = cs.tileCounter or 0
  if counter < DESCENT.TILE_COUNTER_WRAP
    and counter % DESCENT.TILE_STEPS == 0 then
    cs.frame = counter / DESCENT.TILE_STEPS
  end
  -- `cp d / jr c, .done / jr .restart`: at 12 the routine resets the counter to
  -- $ff, so the loop's own `inc d` lands it on 0 and the next beat starts.
  cs.tileCounter = counter < DESCENT.TILE_COUNTER_WRAP and counter + 1 or 0
  if cs.y < DESCENT.FREEZE_Y then
    -- `ld hl, SPRITEANIMSTRUCT_YCOORD / inc [hl]` -- one pixel per iteration.
    cs.y = cs.y + 1
    -- `cp $3a / jr c, .skip / jr z, .skip / sub $3`: the amplitude decays by
    -- three a frame until it reaches the floor, so the swoop starts widest.
    if cs.amplitude > DESCENT.AMPLITUDE_FLOOR then
      cs.amplitude = cs.amplitude - DESCENT.AMPLITUDE_DECAY
    end
    -- `call CelebiEvent_Cosine` -- a = d * cos(a * pi/32), the signed byte the
    -- OAM writer adds straight onto XCOORD.  The engine's `SpriteAnims.cosine`
    -- is a transcription of the same `calc_sine_wave`, so this is the ROM's
    -- arithmetic -- amplitude included.  See DESCENT on why it is not scaled.
    local prev = cs.xOffset
    cs.xOffset = signedByte(SpriteAnims.cosine(cs.phaseAngle, cs.amplitude))
    cs.phaseAngle = (cs.phaseAngle + 1) % 64
    -- Both tests below read `XCOORD + XOFFSET` as the 8-bit byte the OAM writer
    -- writes, and both read the OLD offset: `.ShiftY` does `pop af / push af`
    -- for the direction test, and `.ReinitSpriteAnimFrame` pops it again for
    -- the facing test.
    local screenX = (DESCENT.XCOORD + cs.xOffset) % 256
    if screenX >= DESCENT.BAND_HI or screenX < DESCENT.BAND_LO then
      -- `.ShiftY`: outside the cart's own in-window band -- the centre column
      -- +/- 12 -- the sprite gets a vertical nudge instead of a clean descent.
      -- `cp d` is OLD against NEW, so the nudge follows which way the sway is
      -- travelling as well as which side of centre it is on.
      local oldX = (DESCENT.XCOORD + prev) % 256
      if prev < cs.xOffset then
        -- .moving right
        if oldX < DESCENT.XCOORD then cs.y = cs.y + 1     -- .float_up
        else cs.y = cs.y - 2 end                          -- .float_down
      else
        -- .moving left
        if oldX >= DESCENT.XCOORD then cs.y = cs.y + 1    -- .float_up
        else cs.y = cs.y - 2 end                          -- .float_down
      end
    end
    local faceX = (DESCENT.XCOORD + prev) % 256
    cs.facing = (faceX >= DESCENT.SCREEN_CENTRE and faceX < DESCENT.FACING_MAX)
      and "right" or "left"
  end

  positionDescent(cs)
end

local function beginShrineDescent(mod, world, onDone)
  if cutscene then return false end
  if not (world and world.player) then return false end
  cutscene = {
    kind = "shrine",
    mod = mod,
    world = world,
    onDone = onDone,
    phase = "descend",
    frames = 0,
    iteration = 0,
    -- UpdateCelebiPosition's own state
    y = DESCENT.START_Y,
    xOffset = 0,
    phaseAngle = 0,          -- SPRITEANIMSTRUCT_VAR3
    frame = 0,               -- GetCelebiSpriteTile's tile group
    tileCounter = 0,         -- GetCelebiSpriteTile's counter (`d`)
    amplitude = DESCENT.AMPLITUDE_START,  -- SPRITEANIMSTRUCT_VAR4
    -- The cart decides the frameset inside UpdateCelebiPosition, before the
    -- first frame is drawn, so this is only what the struct starts as.
    facing = "right",
    npc = nil,
  }
  local npc, err = spawnCelebi(world)
  if not npc then
    -- The descent plays anyway.  The freeze, the 160 iterations, the sway, the
    -- tear-down and the battle are all the cutscene's own; only the sprite is
    -- missing.  advanceDescent and positionDescent both return early on a nil
    -- npc, and tickCutscene's tear-down is guarded by `if cs.npc`, so a
    -- cutscene with no npc runs to completion exactly like one with it.  That
    -- is what makes the player's sheet optional rather than required -- the
    -- alternative was skipping the whole shrine event over a missing picture.
    mod.log:warn("Celebi descends without a sprite: %s", tostring(err))
  end
  cutscene.npc = npc
  -- The first DRAWN frame is the struct AFTER one UpdateCelebiPosition.  The
  -- cart's anim function is DoSpriteAnimFrame -- the jumptable UpdateCelebiPosition
  -- is reached from -- and it runs inside DoNextFrameForAllSprites, BEFORE
  -- UpdateAnimFrame writes the OAM, so the loop's very first drawn frame already
  -- carries the first sway and the first Y nudge.  Advancing here and NOT at the
  -- first tick later is therefore the cart's order; the sprite is never drawn in
  -- the `depixel`-fresh state.
  advanceDescent(cutscene)
  return true
end

-- World:step calls this once per logic frame.  The cart's `ld c, 2 /
-- call DelayFrames` means one UpdateCelebiPosition call every two frames.
local function tickCutscene()
  local cs = cutscene
  if not cs then return end
  local world = cs.world
  if not (world and world.player) then cutscene = nil return end

  -- A step queue is its own shape; everything below is the shrine's descent.
  if cs.kind == "steps" then return tickSteps(cs) end

  if cs.phase == "finish" then
    -- One frame of separation between the last drawn descent frame and the
    -- battle screen, so the sprite is never torn down in the same tick that
    -- pushes the battle over it.
    cutscene = nil
    local onDone = cs.onDone
    if onDone then onDone() end
    return
  end

  if cs.phase ~= "descend" then return end
  cs.frames = cs.frames + 1
  if cs.frames < DESCENT.FRAMES_PER_ITERATION then return end
  cs.frames = 0
  cs.iteration = cs.iteration + 1
  -- `call CelebiEvent_CountDown` is the LAST command of the iteration, so the
  -- 160 decrements buy 160 frames and the iteration that finds the counter at 0
  -- still draws -- its own frame 161.  The tear-down happens on the iteration
  -- after that, which is the loop's `bit JUMPTABLE_EXIT_F, a / jr nz, .done`.
  if cs.iteration > DESCENT.ITERATIONS + 1 then
    -- `call .RestorePlayerSprite_DespawnLeaves` -- the cart clears the OAM
    -- slots it borrowed, which here is the spawned object going away.
    if cs.npc then
      local api = cs.mod.world
      local npcId = SHRINE_MAP .. "_obj_" .. (cs.npc.def.index or 0)
      if api then
        api:removeNpc(npcId)
      elseif world.removeRuntimeObject then
        world:removeRuntimeObject(npcId, cs.mod.id)
      end
      cs.npc = nil
    end
    cs.phase = "finish"
    return
  end
  advanceDescent(cs)
end

-- `appear ILEXFOREST_KURT` at (8, 29), `applymovement ... IlexForestKurtSteps-
-- UpMovement` (four step UP), the text, four step DOWN, `disappear`.  Gold has
-- no Kurt object in Ilex Forest at all, so he is spawned; if he cannot be, the
-- closing line still plays rather than the moment being lost.
local function beginKurtApproach(mod, world)
  local objDef = {
    sprite = KURT_SPRITE,
    x = KURT_WAIT_X, y = KURT_WAIT_Y,
    movement = 7, -- SPRITEMOVEDATA_STANDING_UP
    radius = { x = 0, y = 0 },
    hours = { -1, -1 },
    palette = 0, type = 0, sight = 0,
  }
  local api = mod.world
  local npcId
  if api then
    npcId = api:spawnNpc(SHRINE_MAP, objDef)
  elseif world.addRuntimeObject then
    npcId = world:addRuntimeObject(SHRINE_MAP, objDef, mod.id)
  end
  local kurt
  for _, npc in ipairs(world.npcs or {}) do
    if npc.id == npcId then kurt = npc break end
  end
  if not kurt then
    world:showText(T.kurtCaught)
    return
  end
  local up, down = {}, {}
  for i = 1, KURT_APPROACH_STEPS do
    up[i] = { who = kurt, dir = "up" }
    down[i] = { who = kurt, dir = "down" }
  end
  beginSteps(mod, world, up, function()
    world:showText(T.kurtCaught, function()
      beginSteps(mod, world, down, function()
        despawnNpc(mod, world, kurt)
      end)
    end)
  end)
end

local function celebiBattle(mod, world)
  local save, data = saveOf(world), dataOf(world)
  if not (save and data) then return end
  local mon = Mon.new(data, CELEBI, CELEBI_LEVEL)
  if not mon then
    mod.log:error("no CELEBI in this dataset; the shrine event cannot run")
    return
  end
  save.pokedex = save.pokedex or { seen = {}, caught = {} }
  save.pokedex.seen[mon.species] = true
  -- `special CelebiShrineEvent` writes BATTLETYPE_CELEBI into wBattleType and
  -- nothing else (src/script/gen2/specials/crystal_story.lua:278).  Gold's own
  -- battle engine reads the same id -- no running away, no Roar -- so passing
  -- it straight to startBattle is the whole of that special.
  world:startBattle({ wild = mon, battleType = "celebi" }, function(outcome)
    if outcome == "caught" then
      -- `special CheckCaughtCelebi`, which reads the bit and banks it
      -- (crystal_story.lua:285).
      celebrate(save).celebiCaught = true
      mod.save:set(STAGE, "caught")
      beginKurtApproach(mod, world)
    end
  end)
end

local function shrineTalk(mod, world)
  local stage = mod.save:get(STAGE)
  local save = saveOf(world)
  if stage ~= "restless" or not hasBall(save) then
    return false -- Gold's own "forest's protector" text, untouched
  end
  world:showText(T.shrineEvent, function()
    world:askYesNo(function(yes)
      if not yes then return end
      Bag.remove(save, GS_BALL, 1)
      world:showText(T.insertBall, function()
        -- `clearevent EVENT_FOREST_IS_RESTLESS` is the same command as
        -- `takeitem GS_BALL` here, and it is what the rest of the quest reads:
        -- the shrine has the ball now, so the forest is no longer restless even
        -- if CELEBI is not caught.  "shrine" is that state; "caught" is banked
        -- on top of it when the battle ends in a catch.
        mod.save:set(STAGE, "shrine")
        -- `pause 20` / `showemote EMOTE_SHOCK, PLAYER, 20` / `special
        -- FadeOutMusic` / `applymovement PLAYER, IlexForestPlayerStepsDown-
        -- Movement` / `pause 30` / `turnobject PLAYER, DOWN` / `pause 20` /
        -- `special CelebiShrineEvent`, in that order.  The fade is BEFORE the
        -- step back and a good second before the descent, so the forest theme
        -- is already gone when CELEBI starts falling -- and the emote's "!" is
        -- over the player, object 0 (World:objectEntity).
        --
        -- The "!" is SILENT and it HOLDS, both as the cart has it: nothing in
        -- Script_showemote plays a sound, and its `pause 0` holds the script for
        -- the `time` operand at two frames a unit -- 40 frames here -- so the
        -- `FadeOutMusic` and the step back wait for the bubble to come down.
        -- The queue inserts that hold; see the emote row in tickSteps.
        local player = world.player
        -- `fix_facing`, the movement's own first command.
        if player then player.fixedFacing = true end
        beginSteps(mod, world, {
          { wait = 20 * PAUSE_UNIT },
          { emote = EMOTE_SHOCK, object = 0, time = 20 },
          { fadeMusic = 2 },
          -- `fix_facing / slow_step DOWN / remove_fixed_facing` -- ONE slow
          -- step, not two; that is the whole table.
          { who = player, dir = "down" },
          -- `pause 30`
          { wait = 30 * PAUSE_UNIT },
          -- `turnobject PLAYER, DOWN`: the step kept the facing (fix_facing),
          -- so this is what turns the player away from the shrine, and it
          -- releases the lock the movement took.
          { player = player, turn = "down" },
          -- `pause 20`
          { wait = 20 * PAUSE_UNIT },
        }, function()
          if not beginShrineDescent(mod, world, function()
            celebiBattle(mod, world)
          end) then
            celebiBattle(mod, world)
          end
        end)
      end)
    end)
  end)
  return true
end

-- ---- the press -------------------------------------------------------------

local function tryInteract(mod, world)
  if not (world and world.map and world.player and world.vm) then return false end
  liveWorld = world
  -- Mirrors the guard World:interactBody opens with, so a press during a box or
  -- a battle can never open a second one.
  if world:busy() or world.player.moving then return false end
  local mapId = world.map.id

  if mapId == KURT_MAP then
    local npc = world:facingObject()
    if npc and npc.def then
      if KURT_INDEXES[npc.def.index] then
        -- The object is handed on because Kurt has to walk out of the house,
        -- and only the one the player actually talked to can do that.
        return kurtTalk(mod, world, npc)
      end
      if npc.def.sprite == "SPRITE_TWIN" then
        return twinTalk(mod, world, npc)
      end
    end
  elseif mapId == AZALEA_MAP then
    local npc = world:facingObject()
    if npc and npc.def and npc.def.owner == mod.id then
      -- AzaleaTownKurtScript: ONE line, no item.  The ball comes from the
      -- coord event on (9,6) alone, which is why the tile is the trigger.
      world:showText(T.kurtOutside)
      if npc.facing == "right" then npc.facing = "left" end
      return true
    end
  elseif mapId == SHRINE_MAP then
    local fx, fy = world:facingObjectCell()
    if fx == SHRINE_X and fy == SHRINE_Y then
      return shrineTalk(mod, world)
    end
  end
  return false
end

-- ---- entry -----------------------------------------------------------------

-- ---- which cart this is -----------------------------------------------------
--
-- The mod runs on **all three** Gen 2 carts.  What differs is one thing: whether
-- the cart already carries the GS BALL, because `mod.content.items:register`
-- refuses a duplicate id (`items already registered: GS_BALL`,
-- src/mods/Registry.lua:103) and a Crystal boot would otherwise fail the mod
-- outright rather than run it.
--
-- The question asked is the CAPABILITY, not the cart: "does this ROM already
-- carry the GS BALL?"  Crystal's item list names GS_BALL where Gold's and
-- Silver's carry a placeholder (tools/rom_manifest_{gold,silver,crystal}.json,
-- constants.itemOrder[114]: "ITEM_73" / "ITEM_74" / "GS_BALL"), and extractItems
-- keys its table by that name (`out[itemId]`, see
-- RomExtractorGen2:extractItems) -- so `items["GS_BALL"]` is present on Crystal
-- and nil on both GS carts.  The table is loaded into game.data BEFORE mods:load
-- (src/core/Game2.lua:1028 then :1125), and `mod.game` is injected just before
-- it (:1124 `mods.game = self`), so both are live when the entry chunk runs.
--
-- Deliberately NOT `GameVersion.get() == "crystal"`.  Two reasons.  It is the
-- shape `modkit gen2check` reports as MK409 -- "allow-lists a Gen 1 version
-- string ... test for the capability the code needs instead of the version" --
-- and a version test would be the weaker question anyway: a ROM whose item table
-- has been edited still answers the capability honestly, where a version string
-- would not.  The engine's own version id is the right question for the
-- manifest's gate, which is where it is asked (see below).
--
-- The manifest keeps claiming `"gen2"` rather than `["gold", "silver"]` on
-- purpose, and it is what makes that gate cover all three: ModTargets.normalize
-- expands the token to the version-id list (`["gold","silver","crystal"]`,
-- src/mods/ModTargets.lua:36-46), which is exactly what Loader:_gateGeneration
-- matches on.  Spelling the three ids out instead makes `modkit gen2check`
-- report MK400 "no Gen 2 game in games" against a manifest that is correct --
-- tried, not assumed -- so the token stays.
local function cartHasGsBall(game)
  local items = game and game.data and game.data.items
  return type(items) == "table" and items[GS_BALL] ~= nil
end

return function(mod)
  -- Read once, at entry: this is the cart's OWN item table, before the registry
  -- merges anything of ours into it.
  local cartBall = cartHasGsBall(mod.game)
  if cartBall then
    -- Crystal.  The event is already in that ROM, so the mod does not stand
    -- down -- it runs there too -- but it must not register a second GS BALL:
    -- the registry refuses a duplicate id and the whole mod would fail to load.
    -- The cart's own record is used instead, which is the one the Pack, the
    -- item jingle and `Bag.add` all read anyway.
    mod.log:info("this cart already carries the GS BALL; "
      .. "running without registering a second one")
  end

  mod.options:define({
    { key = "open_from_start", type = "toggle", default = false,
      label = "Reach the event without the HALL OF FAME",
      help = "Off: the receptionist hands the GS BALL over only once you "
        .. "have entered the HALL OF FAME, as in Crystal -- walk out of the "
        .. "GOLDENROD POKéMON CENTER and nothing happens until then. On: she "
        .. "makes the offer the first time you walk out." },
    -- The debug switch.  Crystal makes the player wait a day between handing
    -- the ball to KURT and getting it back, and the engine reads the day off
    -- the device clock -- so testing the shrine means either changing the
    -- clock or waiting.  This removes the wait and nothing else.
    { key = "skip_kurt_wait", type = "toggle", default = false,
      label = "Skip KURT's 24-hour wait",
      help = "Off: KURT studies the GS BALL until the day rolls over, as in "
        .. "Crystal. On: talk to him again straight away and he hands it back "
        .. "with the same lines. Handy for reaching the shrine without "
        .. "changing the device clock." },
  })

  -- Skipped on a cart that already carries the ball.  Everything downstream --
  -- Bag.add, Bag.remove, playItemJingle -- reads the record out of data.items by
  -- id, so the cart's own GS_BALL serves all of them unchanged.
  if not cartBall then
    mod.content.items:register(GS_BALL, {
      id = GS_BALL,
      name = "GS BALL",
      -- Gold's and Silver's own itemOrder is 250 rows; Gold's row 115 is the
      -- placeholder "TERU-SAMA".  A new id is registered instead of patching
      -- that row so the carts' item lists stay independent, and it takes an
      -- index past the ROM's own so no positional read can collide.
      index = 251,
      price = 0,
      pocket = "KEY_ITEM",
      tossable = false,
      canToss = false,
      canSelect = false,
      description = "A mysterious BALL\nreceived from the\nPOKéCOM CENTER.",
    })
  end

  -- The receptionist is not a standing object any more: on the cart she has no
  -- interaction script and exists only for the entrance scene, so nothing is
  -- spawned until beginGsBallScene runs -- see the world.stepped handler below.
  mod.events:on("map.entered", function(ev)
    if not ev then return end
    local world = (mod.world and mod.world:overworld()) or liveWorld
    if world then liveWorld = world end
    if ev.mapId == KURT_MAP then
      -- KurtsHouseKurtCallback: the desk swap and the granddaughter's move.
      applyKurtHouse(mod, world)
    elseif ev.mapId == AZALEA_MAP then
      -- Kurt is standing outside his house from the moment he runs out of it
      -- until the scene runs, and a runtime object is not serialized, so this
      -- is where he comes back after a save or a warp.
      ensureKurtOutside(mod, world)
    end
  end)

  -- GoldenrodPokecenter1F.asm's `coord_event 3, 7` / `coord_event 4, 7`.  A Gen
  -- 2 mod cannot add a coord event, but world.stepped carries the tile the
  -- player just landed on, which is the same trigger -- and it is the STEP onto
  -- the tile, not the arrival through the door, so the hand-over happens on the
  -- way OUT of the Center.  That is the cart's own reading of these tiles too:
  -- they are COLL_WARP_CARPET_DOWN, and the cart's CheckWarpTile declines a
  -- DIRECTIONAL warp (CheckDirectionalWarp clears carry), so the coord event is
  -- what runs when the player steps onto one.  A plain warp would have taken
  -- the press instead.
  --
  -- Which is also why the warp has to be stood down here.  World:step emits
  -- world.stepped and only THEN asks World:checkWarpOnArrive
  -- (src/world/gen2/World.lua:11106-11113), and for a directional warp that
  -- test is `heldDir == carpetDirection(coll)` -- so a player walking out with
  -- DOWN held warps to GOLDENROD_CITY in the same frame the scene starts.
  -- `warpsSuppressed()` is NOT the lever: checkWarpOnArrive only consults it on
  -- the IMMEDIATE-warp arm, and these tiles never take that arm.  The lever is
  -- the held direction itself, so the mod drops it for the frame.  Game2 polls
  -- input before World:step (src/core/Game2.lua:1268-1271), so clearing it here
  -- is in time; and once the scene owns the world, World:busy -- which this mod
  -- holds true for the whole cutscene -- keeps movePlayer, and with it
  -- checkCarpetWhileStanding, from reading the direction again until it ends.
  -- After that the player is still standing on the tile, so holding DOWN again
  -- walks them out exactly as it did before.
  --
  -- Nothing is stood down when the scene declines -- not qualified yet, or the
  -- ball already given -- because then the player is simply walking out.
  mod.events:on("world.stepped", function(ev)
    if not ev then return end
    local world = (mod.world and mod.world:overworld()) or liveWorld
    if ev.mapId == PC_MAP then
      if ev.y ~= PC_DOOR_Y then return end
      local right
      if ev.x == PC_DOOR_LEFT_X then right = false
      elseif ev.x == PC_DOOR_RIGHT_X then right = true
      else return end
      if not world then return end
      liveWorld = world
      if not beginGsBallScene(mod, world, right) then return end
      world.heldDir = nil
      return
    end
    if ev.mapId ~= AZALEA_MAP then return end
    -- AzaleaTown.asm's `coord_event 9, 6, SCENE_AZALEATOWN_KURT_RETURNS_GS_BALL`.
    if ev.x ~= AZALEA_TRIGGER_X or ev.y ~= AZALEA_TRIGGER_Y then return end
    if mod.save:get(STAGE) ~= "left" then return end
    if world then beginAzaleaScene(mod, world) end
  end)

  -- Nothing to place at load time any more: the receptionist is spawned by the
  -- scene itself, so a Center the player is already standing in when the mod
  -- loads has nothing to catch up on -- the next step onto a doorway tile runs
  -- the scene, exactly as it does on any other visit.

  -- The original is stashed on the class rather than captured from a
  -- module-local, so a second load of this mod replaces the wrapper with a
  -- fresh one bound to the new `mod` instead of keeping the first load's
  -- closure (the trap that makes a re-loaded mod measure the wrong run).
  local vanillaInteractBody = World2.celebi_event_vanilla or World2.interactBody
  World2.celebi_event_vanilla = vanillaInteractBody
  World2.interactBody = function(self, ...)
    local okCall, handled = pcall(tryInteract, mod, self)
    -- A diagnostic must never eat a press: anything this mod throws falls
    -- through to the engine's own body rather than swallowing the input.
    if okCall and handled then return true end
    if not okCall then
      mod.log:error("interact interception failed: %s", tostring(handled))
    end
    return vanillaInteractBody(self, ...)
  end

  -- The descent's mirror.  SpriteRenderer:draw takes `forceFlip` as its ninth
  -- argument and NPC:draw hard-codes it to false, so the flag the descent sets
  -- on the sprite is read here instead.  forceFlip is what :draw ORs into the
  -- frame's own flip, which for a two-frame party icon is the only way to show
  -- Celebi facing the way it is travelling.
  local vanillaSpriteDraw = SpriteRenderer.celebi_event_vanilla_draw
    or SpriteRenderer.draw
  SpriteRenderer.celebi_event_vanilla_draw = vanillaSpriteDraw
  SpriteRenderer.draw = function(self, px, py, camX, camY, facing, walkPhase,
                                 stepFlip, topHalf, forceFlip, frameOverride,
                                 oamRow)
    if self.celebiEventMirror and not forceFlip then forceFlip = true end
    if self.celebiEventFrame and not frameOverride then
      frameOverride = self.celebiEventFrame
    end
    return vanillaSpriteDraw(self, px, py, camX, camY, facing, walkPhase,
      stepFlip, topHalf, forceFlip, frameOverride, oamRow)
  end

  -- The descent's tick.  World:step is what Game2 calls once per logic frame
  -- (src/core/Game2.lua:1272) and it is the only per-frame seam the overworld
  -- offers a mod, so the animation is driven from its tail.
  local vanillaStep = World2.celebi_event_vanilla_step or World2.step
  World2.celebi_event_vanilla_step = vanillaStep
  World2.step = function(self, ...)
    local result = vanillaStep(self, ...)
    if cutscene then
      local okTick, err = pcall(tickCutscene)
      if not okTick then
        mod.log:error("cutscene aborted: %s", tostring(err))
        cutscene = nil
      end
    end
    return result
  end

  -- A cutscene with no box up would otherwise leave the world walkable: the
  -- engine's own busy() covers the VM, the text box, a choice box, movement
  -- and the field-move animations, and none of those is this.  Holding it here
  -- is the honest answer -- the world IS busy -- and it also stops the next
  -- press, the menu and a second step from landing mid-descent.
  local vanillaBusy = World2.celebi_event_vanilla_busy or World2.busy
  World2.celebi_event_vanilla_busy = vanillaBusy
  World2.busy = function(self, ...)
    if cutsceneRunning() then return true end
    return vanillaBusy(self, ...)
  end
end

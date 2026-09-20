-- The GS BALL — behaviour test.
--
-- Standalone (from the engine repo root):
--   luajit ../celebi-event/tests/celebi_event_test.lua
-- or with the repo elsewhere:
--   GEN1RECOMP_ROOT=/path/to/gen1recomp luajit .../celebi_event_test.lua
--
-- What it proves, in order:
--   * the mod loads through the REAL loader on generation 2 and its item merges
--   * the press interception is a fall-through by default: every state the
--     vanilla cart has behaviour for still reaches the engine's own body
--   * the whole quest runs: stepping out of the GOLDENROD POKéMON CENTER ->
--     Kurt -> the day rollover -> the shrine -> the CELEBI battle, with the
--     state and the save landing where they should
--   * a Crystal cart (which already has the event) is stood down
--
-- The vanilla body is replaced with a sentinel BEFORE the mod loads, so "did
-- this press fall through?" is an identity check rather than a guess.
package.path = "./?.lua;./?/init.lua;" .. package.path

-- love has to exist before any engine module is required
local love = require("tests.love_stub")
_G.love = love
if not love.timer then love.timer = {} end
if not love.timer.getTime then love.timer.getTime = function() return 0 end end

local T = require("tests.modkit")
local Sdk = require("tests.modkit.sdk")
local Runtime = require("src.mods.Runtime")
local SpriteRenderer = require("src.render.SpriteRenderer")
local Sound = require("src.core.Sound")
local Music = require("src.core.Music")
local World2 = require("src.world.gen2.World")
local Palettes = require("src.world.gen2.Palettes")
local Clock = require("src.core.gen2.Clock")
local GameVersion = require("src.core.GameVersion")
local HallOfFame = require("src.core.gen2.HallOfFame")

-- ---- where is the mod? -----------------------------------------------------
--
-- arg[0] is not reliable under a launcher shim (a .bat makes it the
-- interpreter), so scan the whole arg list for something ending in .lua and
-- VERIFY the directory by looking for main.lua before accepting it.
local function modDir()
  local root = os.getenv("GEN1RECOMP_ROOT")
  local candidates = {}
  if root and root ~= "" then candidates[#candidates + 1] = root end
  for i = 0, 4 do
    local a = arg and arg[i]
    if type(a) == "string" and a:sub(-4) == ".lua" then
      local dir = a:match("^(.*)[/\\][^/\\]*$") or "."
      dir = dir:gsub("[/\\]tests$", "")
      candidates[#candidates + 1] = dir
    end
  end
  candidates[#candidates + 1] = "."
  candidates[#candidates + 1] = ".."
  candidates[#candidates + 1] = "../celebi-event"
  for _, dir in ipairs(candidates) do
    local handle = io.open(dir .. "/main.lua", "rb")
    if handle then
      handle:close()
      return (dir:gsub("\\", "/"))
    end
  end
  error("cannot locate the mod directory (set GEN1RECOMP_ROOT)", 0)
end

local MOD_DIR = modDir()

local function readFile(path)
  local handle = assert(io.open(path, "rb"), "missing " .. path)
  local body = handle:read("*a")
  handle:close()
  return body
end

-- readFile asserts, so it cannot answer "is this here at all?" -- which is
-- the question for the one file the mod deliberately does NOT ship.
local function fileExists(path)
  local handle = io.open(path, "rb")
  if handle then handle:close() return true end
  return false
end

-- ---- the sentinel engine seams --------------------------------------------

local vanillaCalls = 0
World2.interactBody = function(self, ...)
  vanillaCalls = vanillaCalls + 1
  return "VANILLA"
end
-- The mod also wraps World:step (the per-frame tick) and World:busy (to hold
-- the world still during the descent).  Both are replaced with sentinels
-- BEFORE the load for the same reason interactBody is: the real ones need a
-- live map, and a sentinel makes "did the mod call through?" an identity check.
local stepCalls = 0
World2.step = function(self, ...)
  stepCalls = stepCalls + 1
  return "VANILLA_STEP"
end
local busyCalls = 0
World2.busy = function(self, ...)
  busyCalls = busyCalls + 1
  return false
end
-- SpriteRenderer:draw, sentinelled for the same reason: the mod wraps it to
-- inject `forceFlip` for a mirrored Celebi, and the only way to see that is to
-- stand behind the wrapper.  Records the ninth argument.
-- Sound.sfxBusy, sentinelled so the `waitsfx` hold is observable: with it true
-- the movement queue must not start.
local sfxBusy = false
Sound.sfxBusy = function() return sfxBusy end
-- `special FadeOutMusic`, recorded rather than performed: the engine's own
-- special hands the cart's control byte (2) to Music.fadeOut
-- (src/world/gen2/World.lua:3834), so counting the calls is counting the fade
-- the cart asks for.  `showemote`'s cue and `playsound` go through the world
-- double's own playSfxNamed, which the scenarios read back from `world.sfx`.
local musicFades = {}
Music.fadeOut = function(control)
  musicFades[#musicFades + 1] = control
  return true
end
local spriteDraws = {}
SpriteRenderer.draw = function(self, px, py, camX, camY, facing, walkPhase,
                               stepFlip, topHalf, forceFlip, frameOverride,
                               oamRow)
  spriteDraws[#spriteDraws + 1] = {
    flip = forceFlip and "flipped" or "plain", frame = frameOverride,
  }
  return "VANILLA_DRAW"
end

-- ---- load the mod through the real loader ---------------------------------

-- An explicit file map rather than the aliasFs path: on Windows
-- tests/fs_io.lua's getInfo decides "directory" with os.rename, which returns
-- ACCESS_DENIED whenever anything holds a handle on the directory, and the
-- loader then silently discovers zero mods.
local files = {
  ["mods/celebi_event/manifest.json"] =
    readFile(MOD_DIR .. "/manifest.json"),
  ["mods/celebi_event/main.lua"] = readFile(MOD_DIR .. "/main.lua"),
}
-- The descent sheet is the PLAYER's file -- this repo deliberately does not
-- ship it (see assets/README.md) -- so the mod's own directory has to be
-- given one for the sprite half of the suite to exercise anything at all.
-- It is taken away again in "the descent without the sheet" below, which is
-- the other half and the state a fresh install is actually in.
--
-- The bytes do not matter: nothing here renders, and the mod only asks
-- whether the path exists.  What the file has to look like is the player's
-- business and assets/README.md is where it is written down.
local SHEET_KEY = "mods/celebi_event/assets/celebi.png"
files[SHEET_KEY] = "PLAYER-SUPPLIED-SHEET-FIXTURE"
-- The ROM-free fixture is a three-species stand-in, so the shrine event has no
-- CELEBI to build.  Cloning one fixture species under the id the mod names is
-- enough: what is under test is the mod's event logic, not the cart's record
-- for Celebi, and Mon.new only needs baseStats / growthRate / types / moves.
local Data = require("tests.modkit.fixtures").fresh()
do
  local base = assert(Data.pokemon.FIXMON_A, "the fixture species is missing")
  local clone = {}
  for k, v in pairs(base) do clone[k] = v end
  clone.id, clone.name, clone.dex = "CELEBI", "CELEBI", 251
  Data.pokemon.CELEBI = clone
  -- The descent draws Celebi from the party-icon table the engine extracts for
  -- every species (data.gen2Icons), which the ROM-free fixture has none of.
  -- The path is never opened -- the harness never renders -- but the mod reads
  -- it to build the sprite def, so the shape has to be the real one:
  -- icons.species[SPECIES] -> icon id, icons.icons[id].image -> the sheet.
  Data.gen2Icons = {
    species = { CELEBI = "ICON_CELEBI" },
    icons = { ICON_CELEBI = { image = "icons/celebi.png", frames = 2 } },
  }
  -- The sprite table the mod writes SPRITE_CELEBI into.  Gold always has it
  -- (Game2 loads data/generated/sprites.lua before mods:load); the fixture
  -- does not, and a mod with nowhere to put the def correctly declines.
  Data.gen2Sprites = {}
end

local run = Sdk.loadMod("mods/celebi_event", {
  generation = 2,
  data = Data,
  fs = Sdk.memfs(files),
})

T.eq(#run.errors, 0, "loads with no errors ("
  .. tostring(run.errors[1]) .. ")")
T.check(run.mod ~= nil, "the loader discovered the mod")
T.eq(run.mod and run.mod.state, "loaded",
  "runs on gen 2: " .. tostring(run.mod and run.mod.skipReason))

-- ---- nothing may go wrong quietly -------------------------------------------
--
-- The mod brackets its cutscenes in pcall and reports through mod.log:error
-- ("cutscene aborted: ..."), which is exactly the failure that would otherwise
-- show up as "the animation simply stopped".  Every one of them is collected
-- here and asserted against at the end of the run.
--
-- The seam is the ENGINE's Logger, not the mod's own log table.  `mod.log` is
-- handed to main.lua as an argument -- it is not a field on the loader's mod
-- record, which carries path/state/manifest/enabled -- so a collector hung off
-- run.mod.log is never installed, and the assertions that read it pass without
-- being able to fail.  Logger.history is the engine's own bounded record of
-- everything emitted, so it sees the mod's lines whatever the mod does with the
-- handle it was given.
local Logger = require("src.core.Logger")

-- Logger prefixes each line "[<level>] [<mod id>] <message>".
local MOD_TAG = "[" .. tostring(run.mod and run.mod.manifest
  and run.mod.manifest.id or "celebi_event") .. "] "

-- What the mod logged since a mark, split by level.  Scanning from a mark
-- rather than over the whole history matters: the suite runs the mod several
-- times, and a warning from an earlier case must not satisfy a later assertion.
local function modLogSince(mark)
  local out = { info = {}, warn = {}, error = {} }
  for i = (mark or 0) + 1, #Logger.history do
    local level, rest = Logger.history[i]:match("^%[(%a+)%] (.+)$")
    if level and rest and rest:sub(1, #MOD_TAG) == MOD_TAG then
      local bucket = out[level]
      if bucket then bucket[#bucket + 1] = rest:sub(#MOD_TAG + 1) end
    end
  end
  return out
end

local function logMark() return #Logger.history end

-- ---- the item --------------------------------------------------------------

local gs = Data.items and Data.items.GS_BALL
T.check(gs ~= nil, "the GS BALL item merged into the dataset")
T.eq(gs and gs.pocket, "KEY_ITEM", "and it lands in the key-item pocket")
T.eq(gs and gs.tossable, false, "and it cannot be tossed")
T.eq(gs and gs.index, 251, "and its index sits past the ROM's own 250 rows")

-- ---- harness ---------------------------------------------------------------

local function newSave(opts)
  opts = opts or {}
  return {
    inventory = opts.inventory or {},
    modData = {},
    flags = {},
    pokedex = { seen = {}, caught = {} },
    hallOfFame = opts.hallOfFame or { count = 1 },
    rtc = opts.rtc or {},
  }
end

-- A world with just the surface the interception touches.  Callbacks are
-- QUEUED rather than run inline, so one drain step is one button press and the
-- nesting of the conversation is exercised instead of flattened.
local function newWorld(mapId, save, opts)
  opts = opts or {}
  local world = {
    game = { data = Data, save = save },
    map = { id = mapId, def = { objects = {}, bgEvents = {} } },
    player = {
      cellX = 8, cellY = 23, facing = "up", moving = false,
      -- NPC:scriptStep, as far as this harness needs it: one tile, the facing
      -- held while `fixedFacing` is set (that IS fix_facing), and `moving`
      -- standing until the tick has walked the frames out.
      scriptStep = function(self, dir)
        if self.moving then return false end
        self.stepDir = dir
        if not self.fixedFacing then self.facing = dir end
        self.moving = true
        -- NPC.stepFrames is the per-object cadence the mod overrides for a
        -- `big_step`; the harness has to honour it or the timing under test
        -- is not the timing the game gets.
        self.stepCountdown = self.stepFrames or 16
        return true
      end,
    },
    vm = {},
    npcs = {},
    nextIndex = 100,
    texts = {}, battles = {}, asks = 0, queue = {}, sfx = {},
    hidden = {}, appeared = {}, faced = opts.npc, emotes = {},
  }
  -- World:addRuntimeObject / removeRuntimeObject, which is what
  -- WorldAPI:spawnNpc wraps -- so the harness drives the same path the game
  -- does rather than a stub the mod could not tell apart.
  function world:addRuntimeObject(objMapId, objDef, owner)
    self.nextIndex = self.nextIndex + 1
    objDef.index = self.nextIndex
    objDef.owner = owner
    objDef.runtime = true
    local npc = {
      id = objMapId .. "_obj_" .. objDef.index, def = objDef, sprite = {},
      cellX = objDef.x, cellY = objDef.y,
      px = objDef.x * 16, py = objDef.y * 16,
      facing = "down", moving = false,
      -- NPC:scriptStep, as the harness needs it: one tile, paced by `moving`
      -- and by stepFrames.
      scriptStep = function(self, dir)
        if self.moving then return false end
        self.stepDir = dir
        self.moving = true
        self.stepCountdown = self.stepFrames or 16
        return true
      end,
    }
    self.npcs[#self.npcs + 1] = npc
    return npc.id
  end
  function world:removeRuntimeObject(npcId)
    for i, npc in ipairs(self.npcs) do
      if npc.id == npcId then
        table.remove(self.npcs, i)
        return true
      end
    end
    return nil, "no such runtime object: " .. tostring(npcId)
  end
  function world:busy() return false end
  function world:facingObjectCell() return opts.fx, opts.fy end
  -- `faced` rather than opts.npc so a scenario can re-aim the press at an
  -- object it spawned after construction.
  function world:facingObject() return self.faced end
  -- Script_disappear.  The real one masks the object in the map def; what the
  -- assertions care about is WHICH object and that it happened.
  function world:disappearObject(objectId)
    self.hidden[#self.hidden + 1] = objectId
    return true
  end
  function world:appearObject(objectId)
    self.appeared[#self.appeared + 1] = objectId
    return true
  end
  function world:showText(body, onDone)
    self.texts[#self.texts + 1] = body
    if onDone then self.queue[#self.queue + 1] = onDone end
  end
  function world:askYesNo(cb)
    self.asks = self.asks + 1
    self.queue[#self.queue + 1] = function() cb(opts.yes ~= false) end
  end
  function world:startBattle(o, onDone)
    self.battles[#self.battles + 1] = o
    if onDone then
      self.queue[#self.queue + 1] = function()
        onDone(opts.outcome or "caught")
      end
    end
  end
  -- The REAL give-item cue, not a stand-in for it: World:specialSound is what
  -- the script VM calls for every `verbosegiveitem`, so routing it at this
  -- world and recording the name it rings asserts the sound the cart would
  -- make.  It resolves the item's pocket through World:itemIdByIndex, which is
  -- why the double carries the real World metatable -- the methods this world
  -- defines itself (busy, showText, startBattle, ...) still shadow it.
  world.sfx = {}
  function world:showEmote(emote, object, frames)
    self.emotes[#self.emotes + 1] = { emote = emote, object = object,
                                      frames = frames }
  end
  function world:playSfxNamed(want, fallbackId)
    self.sfx[#self.sfx + 1] = want
  end
  -- `playmusic MUSIC_*`.  The VM hands `playmusic` to World:playMusicId, which
  -- resolves the id through the loaded dataset's own musicOrder; the harness has
  -- no dataset, so the ids are recorded instead.
  world.music = {}
  function world:playMusicId(id)
    self.music[#self.music + 1] = id
    return true
  end
  -- `special RestartMapMusic` is World:restoreMapMusic in this engine
  -- (src/world/gen2/World.lua:3833), which needs a live map and an audio
  -- player; the scenarios care that it was asked for and when.
  function world:restoreMapMusic()
    self.musicRestored = (self.musicRestored or 0) + 1
    return true
  end
  return setmetatable(world, { __index = World2 })
end

-- One logic frame: walk the player's step along, then let the mod's own
-- World:step wrapper run.  The wrapper is what drives the cutscene, so this is
-- "the game ticks" rather than a hand-cranked animation.
local function walkOne(who)
  if who and who.moving then
    who.stepCountdown = (who.stepCountdown or 0) - 1
    if who.stepCountdown <= 0 then who.moving = false end
  end
end

local function tick(world, frames)
  for _ = 1, frames or 1 do
    walkOne(world.player)
    walkOne(world.faced)
    for _, npc in ipairs(world.npcs) do walkOne(npc) end
    World2.step(world)
  end
end

-- Answer every box the mod queued.  Shared by the press and by the cutscene,
-- because the shrine's descent ends by queuing the battle and then the battle
-- queues its own outcome -- all of it driven from ticks, not from a press.
local function drain(world)
  local guard = 0
  while #world.queue > 0 do
    guard = guard + 1
    if guard > 400 then error("the conversation never settled", 0) end
    table.remove(world.queue, 1)()
  end
end

-- Press A: run the wrapped body, then answer every box it queued.
local function press(world)
  -- `mod.save` is `save.modData`; the engine binds them at boot
  -- (src/core/Game2.lua:207) and the headless loader leaves them apart, so a
  -- scenario has to do what the boot does before its state is readable.
  run.loader.modSave = world.game.save.modData
  vanillaCalls = 0
  local result = World2.interactBody(world)
  drain(world)
  return result, vanillaCalls
end

local function stageOf(save)
  return (save.modData.celebi_event or {}).stage
end

local function withBall()
  return { GS_BALL = 1 }
end

-- ---- the shrine ------------------------------------------------------------

local SHRINE = "ILEX_FOREST"
local function shrineWorld(save, opts)
  opts = opts or {}
  opts.fx, opts.fy = 8, 22
  return newWorld(SHRINE, save, opts)
end

do
  -- nothing started: Gold's own "forest's protector" text must survive
  local world = shrineWorld(newSave())
  local result, vanilla = press(world)
  T.eq(vanilla, 1, "an untouched shrine still reaches the engine's own body")
  T.eq(#world.texts, 0, "and the mod shows nothing over it")

  -- restless but no ball: the cart's own fall-through, not an empty press
  local save = newSave()
  save.modData.celebi_event = { stage = "restless" }
  world = shrineWorld(save)
  result, vanilla = press(world)
  T.eq(vanilla, 1, "a restless forest with no GS BALL falls through")

  -- The CRYSTAL START again, at the shrine this time: a ball in the bag and no
  -- mod stage.  The shrine's gate is `stage == "restless" AND hasBall`, so the
  -- ball alone must NOT open it -- the player has to have gone through KURT and
  -- AZALEA first.  Falling through leaves the cart's own "forest's protector"
  -- text in place, which is the right answer here.
  save = newSave({ inventory = withBall() })
  T.eq(stageOf(save), nil, "no mod stage, as a Crystal cart would be")
  world = shrineWorld(save)
  result, vanilla = press(world)
  T.eq(vanilla, 1, "a ball with no stage does not open the shrine")
  T.eq(#world.texts, 0, "and the mod shows nothing over the cart's own text")
  T.eq(save.inventory.GS_BALL, 1, "and the ball is left in the bag")

  -- restless with the ball: the event owns the press
  save = newSave({ inventory = withBall() })
  save.modData.celebi_event = { stage = "restless" }
  world = shrineWorld(save)
  result, vanilla = press(world)
  T.eq(vanilla, 0, "the shrine event takes the press")
  T.eq(result, true, "and answers the dispatcher with true")
  T.eq(world.asks, 1, "the shrine asks exactly one YES/NO")
  -- The press only puts the ball in.  The step back and the descent run on the
  -- world's own per-frame tick, and the battle is the LAST thing the sequence
  -- does -- which is the cart's order (applymovement, then the special, then
  -- loadwildmon/startbattle).
  T.eq(#world.battles, 0, "the press alone does not start the battle yet")
  -- Everything between the press and the battle is on the world's own tick now:
  -- `pause 20`, the "!", `special FadeOutMusic`, the one step back, `pause 30 /
  -- turnobject / pause 20`, then the descent's 161 iterations of two frames.
  -- Walked out rather than guessed at, because a miscount here leaves the
  -- cutscene running and every later scenario blocked by it.
  local guard = 0
  while #world.battles == 0 and guard < 900 do
    guard = guard + 1
    tick(world, 1)
  end
  drain(world)
  T.eq(#world.battles, 1, "and starts exactly one battle")
  local battle = world.battles[1]
  T.eq(battle and battle.battleType, "celebi",
    "with the engine's own BATTLETYPE_CELEBI")
  T.check(battle and battle.wild ~= nil, "as a wild battle")
  T.eq(battle and battle.wild and battle.wild.species, "CELEBI",
    "against CELEBI")
  T.eq(battle and battle.wild and battle.wild.level, 30,
    "at level 30, as the cart loads it")
  T.eq(save.inventory.GS_BALL, nil, "the GS BALL is consumed")
  T.eq(stageOf(save), "caught", "and a catch advances the quest")
  T.check(save.crystal and save.crystal.celebiCaught == true,
    "CheckCaughtCelebi's own save bit is set")
  T.check(save.pokedex.seen.CELEBI == true, "CELEBI is marked seen")
  -- The shrine's own two boxes: the question, then the ball going in.  Kurt's
  -- closing line is the THIRD, and it only comes after he has walked up to the
  -- player -- see the cutscene block below, which is where it is asserted.
  T.eq(#world.texts, 2, "the shrine asks and the ball goes in")
  T.check(world.texts[1]:find("ILEX FOREST", 1, true) == 1,
    "box 1 is Text_ShrineCelebiEvent")
  T.check(world.texts[1]:find("Want to put the GS", 1, true) ~= nil,
    "and it ends on the cart's YES/NO question")
  T.check(world.texts[2]:find("put in the", 1, true) ~= nil,
    "box 2 is Text_InsertGSBall")
  -- Walk Kurt's approach out.  A cutscene is module-level, so one left running
  -- here would block every scenario after it -- a harness bug, not a mod one.
  tick(world, 1)
  tick(world, 16 * 4 + 24)
  drain(world)
  tick(world, 16 * 4 + 24)

  -- answering NO keeps the ball and starts nothing
  save = newSave({ inventory = withBall() })
  save.modData.celebi_event = { stage = "restless" }
  world = shrineWorld(save, { yes = false })
  press(world)
  T.eq(world.asks, 1, "declining still asks")
  T.eq(#world.battles, 0, "but starts no battle")
  T.eq(save.inventory.GS_BALL, 1, "and keeps the GS BALL")
  T.eq(stageOf(save), "restless", "and leaves the quest where it was")

  -- not caught: the ball is still spent, the quest does not complete
  save = newSave({ inventory = withBall() })
  save.modData.celebi_event = { stage = "restless" }
  world = shrineWorld(save, { outcome = "win" })
  press(world)
  local missGuard = 0
  while #world.battles == 0 and missGuard < 900 do
    missGuard = missGuard + 1
    tick(world, 1)
  end
  drain(world)
  T.eq(#world.battles, 1, "a failed catch still fights CELEBI")
  -- The SHRINE still took the ball -- `takeitem GS_BALL` and `clearevent
  -- EVENT_FOREST_IS_RESTLESS` are the same two commands in the cart -- so the
  -- quest sits at "shrine" rather than back at "restless" until a catch banks it.
  T.eq(stageOf(save), "shrine", "and does not complete the quest")
  T.check(not (save.crystal and save.crystal.celebiCaught),
    "and does not bank the caught bit")
end

-- ---- the shrine cutscene ---------------------------------------------------
--
-- `special CelebiShrineEvent` is not a one-line battle-type setter: it runs a
-- 160-iteration sprite animation, and the script steps the player back before
-- calling it.  This block drives the whole thing off the world's own tick and
-- watches the sprite move.

do
  local save = newSave({ inventory = withBall() })
  save.modData.celebi_event = { stage = "restless" }
  local world = shrineWorld(save)
  musicFades = {}
  press(world)

  -- 1. The cart's order, which is the timing:
  --
  --      pause 20
  --      showemote EMOTE_SHOCK, PLAYER, 20
  --      special FadeOutMusic
  --      applymovement PLAYER, IlexForestPlayerStepsDownMovement
  --          fix_facing / slow_step DOWN / remove_fixed_facing -- ONE step
  --      pause 30 / turnobject PLAYER, DOWN / pause 20
  --
  --    The music cue sits BETWEEN the emote and the step back, so the forest
  --    theme is already gone when the descent starts.
  tick(world, 20 * 2)
  T.eq(#world.emotes, 0, "the '!' waits out the cart's `pause 20` first")
  tick(world, 1)
  T.eq(#world.emotes, 1, "the player gets the '!' emote")
  T.eq(world.emotes[1].emote, 0, "EMOTE_SHOCK")
  T.eq(world.emotes[1].object, 0, "on the player, which is object 0")
  T.eq(world.emotes[1].frames, 20, "for the cart's 20 frames")
  -- The "!" is SILENT.  Script_showemote is `loademote` + two applymovements +
  -- `pause 0`, with no `playsound` anywhere in it
  -- (engine/overworld/scripting.asm:1065-1095), so nothing rings with the
  -- bubble.  (An earlier build rang SFX_BUMP here as an addition.)
  T.eq(#world.sfx, 0, "and it rings NO cue -- the cart's showemote is silent")
  T.check(world.player.fixedFacing, "with fix_facing held, as the cart does")
  T.eq(#musicFades, 0, "and the forest theme is still playing")
  -- The emote's own hold is `pause 0`, i.e. the 20 units again -- and it is a
  -- HOLD, so nothing written after the `showemote` runs until the bubble is
  -- down.  One tick is not enough; all 40 frames are.
  tick(world, 1)
  T.eq(#musicFades, 0, "FadeOutMusic does NOT run on the tick after the emote")
  tick(world, 20 * 2 - 1)
  T.eq(#musicFades, 0, "nor before the bubble's own 40 frames are up")
  tick(world, 1)
  T.eq(#musicFades, 1, "`special FadeOutMusic` -- the theme goes out")
  T.eq(musicFades[1], 2, "with the cart's own fast ramp")
  tick(world, 1)
  T.check(world.player.moving, "and then the player steps back from the shrine")
  T.eq(world.player.stepDir, "down", "one step, DOWN")
  T.eq(world.player.facing, "up",
    "and the facing is held, so the step does not turn them")
  T.eq(#world.battles, 0, "nothing has fought yet")

  -- the cutscene holds the world: no press, no menu, no second step
  busyCalls = 0
  T.eq(World2.busy(world), true, "the world reports busy during the cutscene")
  T.eq(busyCalls, 0, "without asking the engine's own busy()")

  -- 2. the step completes, the cart's `pause 30 / turnobject PLAYER, DOWN /
  --    pause 20` run, and Celebi appears
  tick(world, 16)
  T.check(not world.player.moving, "the step finishes")
  T.eq(world.player.facing, "up", "and nothing is turned yet")
  tick(world, 30 * 2 - 1)
  T.eq(world.player.facing, "up", "`pause 30` before the turn")
  tick(world, 1)
  T.eq(world.player.facing, "down", "turnobject PLAYER, DOWN")
  T.eq(world.player.fixedFacing, nil, "which also releases fix_facing")
  T.eq(#world.npcs, 0, "and `pause 20` is all that is left before Celebi")
  tick(world, 20 * 2 + 1)
  T.eq(#world.npcs, 1, "Celebi appears")
  local celebi = world.npcs[1]
  T.eq(celebi.def.sprite, "SPRITE_CELEBI", "as the mod's own sprite")
  T.eq(celebi.def.movement, 0x16,
    "on SPRITEMOVEDATA_POKEMON, so the icon's two frames flap")
  -- The party icon is a 4-shade grayscale sheet (RomExtractorGen2:write2bpp
  -- with transparent shade 0), so its colours come ENTIRELY from the OBJ
  -- palette.  `celebi.def` is the OBJECT, so the sprite definition the mod
  -- built is the one to read -- Data.gen2Sprites is where it put it.
  local spriteDef = Data.gen2Sprites and Data.gen2Sprites.SPRITE_CELEBI
  T.check(spriteDef ~= nil, "the mod registered a sprite definition")
  -- The sprite is AUTHORED for this mod now, not a party icon standing in for
  -- Celebi -- that is what the icon's grayscale sheet could never do.
  -- mod.assets:path joins the MOD's directory: Assets.resolve passes anything
  -- that is not assets/generated/ straight through to love.graphics.newImage,
  -- so a bare "assets/celebi.png" would be looked up against the game root.
  T.check(spriteDef and spriteDef.image:find("assets/celebi.png", 1, true) ~= nil,
    "from the mod's own authored sheet (" .. tostring(spriteDef and spriteDef.image) .. ")")
  T.check(spriteDef and spriteDef.image:find("mods/", 1, true) == 1,
    "addressed through the mod's own directory")
  T.eq(spriteDef and spriteDef.frames, 4, "with four flap frames")
  T.eq(spriteDef and spriteDef.frameWidth, 16, "16 pixels wide")
  T.eq(spriteDef and spriteDef.frameHeight, 16, "and 16 tall")
  -- 1.4.2: the sheet is FOUR SHADES, not true colour.
  --
  -- `trueColor` made SpriteRenderer:resolveImage return self.image untouched,
  -- so the bake below never ran and the sprite wore whatever colours the PNG
  -- happened to hold -- which is exactly why it looked nothing like the real
  -- event.  Unset, resolveImage reaches getObpImage: OBJ colour 0 (shade 0,
  -- white) keyed to alpha, shades 1-3 mapped onto the sprite's own OBJ
  -- palette, which is the cart's PAL_OW_GREEN.
  T.eq(spriteDef and spriteDef.trueColor, nil,
    "not true-colour, so the OBJ palette bake runs")
  T.eq(spriteDef and spriteDef.palette, "PAL_OW_GREEN",
    "drawn with the cart's own OW palette for this sprite")
  -- and the name is one the engine's own table resolves -- Palettes.spritePalette
  -- looks it up here, so a typo would bake a nil palette rather than colours.
  T.eq(Palettes.OW_PALETTE_ID[spriteDef and spriteDef.palette or ""] or nil, 3,
    "PAL_OW_GREEN is OW palette 3 in the engine's own table")
  -- The real bake's colour thresholds are the reason the SHADES matter: it
  -- reads white as transparent, then r > 0.5 / r > 0.17 as palette colours
  -- 1 / 2 and everything darker as colour 3.  A true-colour sheet has none of
  -- those levels, so nothing in it means "palette colour 1".

  -- The sheet is the player's file now, so there is no shipped one to measure.
  -- What the repo has to prove instead is that it does NOT carry one -- the
  -- shape the player must supply is written down in assets/README.md, and
  -- tools/author_celebi_sheet.py is the recipe that produces it -- and that a
  -- copy kept here for local testing cannot ride along in a release.
  T.eq(fileExists(MOD_DIR .. "/assets/celebi.png"), false,
    "the repo ships no sheet -- it is the player's to supply")
  T.check(fileExists(MOD_DIR .. "/assets/README.md"),
    "assets/README.md says what to drop in and where")
  T.check(fileExists(MOD_DIR .. "/tools/author_celebi_sheet.py"),
    "and tools/author_celebi_sheet.py is the recipe that makes it")
  local ignore = readFile(MOD_DIR .. "/.modkitignore")
  T.check(ignore and ignore:find("\nassets/celebi.png\n", 1, true) ~= nil,
    "and .modkitignore names it, so a local copy cannot ship")
  T.eq(spriteDef and spriteDef.spriteType, "STILL_SPRITE",
    "as a still sprite whose frame the descent drives")
  T.eq(celebi.def.owner, "celebi_event", "owned by this mod")

  -- 3. it starts high above the shrine and descends toward the player
  local startPy = celebi.py
  T.check(startPy < 22 * 16, "it starts above the shrine tile")

  -- Sampled from the FIRST tick: the sway is widest at the start and decays,
  -- so the left-facing half only happens early.
  local swayMax, lowest = 0, celebi.py
  local mirrorLeft, mirrorRight = false, false
  local function sample(n)
    for _ = 1, n do
      tick(world, 1)
      swayMax = math.max(swayMax, math.abs(celebi.px - world.player.cellX * 16))
      lowest = math.max(lowest, celebi.py)
      -- the cart swaps FRAMESET_CELEBI_LEFT / RIGHT; the port mirrors instead
      if celebi.sprite.celebiEventMirror then mirrorLeft = true
      else mirrorRight = true end
    end
  end
  sample(40)
  -- The bar is set above what the `float_up`/`float_down` nudge alone can
  -- produce, so this measures the descent rather than the bob.
  T.check(celebi.py > startPy + 4,
    "it descends (" .. (celebi.py - startPy) .. " px in 40 frames)")
  sample(120)
  T.check(mirrorLeft and mirrorRight,
    "the descent sets the mirror flag both ways")
  -- The flag alone proves nothing -- assert the wrapper actually flips the
  -- frame.  This drives the mod's own SpriteRenderer:draw.
  spriteDraws = {}
  SpriteRenderer.draw({ celebiEventMirror = true }, 0, 0, 0, 0, "down", 0, false)
  T.eq(spriteDraws[1].flip, "flipped", "a left-facing Celebi is drawn mirrored")
  spriteDraws = {}
  SpriteRenderer.draw({ celebiEventMirror = false }, 0, 0, 0, 0, "down", 0, false)
  T.eq(spriteDraws[1].flip, "plain", "and a right-facing one is not")
  spriteDraws = {}
  SpriteRenderer.draw({}, 0, 0, 0, 0, "down", 0, false)
  T.eq(spriteDraws[1].flip, "plain", "and an ordinary sprite is untouched")
  -- and the flap frame reaches the draw call: NPC:draw hard-codes
  -- frameOverride to bounceFrame(), which is nil for a STILL_SPRITE
  spriteDraws = {}
  SpriteRenderer.draw({ celebiEventFrame = 2 }, 0, 0, 0, 0, "down", 0, false)
  T.eq(spriteDraws[1].frame, 2, "and the flap frame is passed through")
  -- and the frame is driven too: NPC:draw hard-codes frameOverride to
  -- bounceFrame(), which is nil for a STILL_SPRITE
  local frames = {}
  for _ = 1, 120 do
    tick(world, 1)
    frames[#frames + 1] = celebi.sprite.celebiEventFrame
  end
  local seen = {}
  for _, v in ipairs(frames) do seen[v] = true end
  local n = 0
  for _ in pairs(seen) do n = n + 1 end
  T.check(n == 4, "the flap cycles all four frames (" .. n .. ")")
  -- GetCelebiSpriteTile only picks a new tile when its counter is 0, 3, 6 or 9
  -- (`.AddE` walks 3, 6, 9, 12 and every other value leaves the tile alone),
  -- so one wing beat is four tiles over THIRTEEN iterations -- twenty-six
  -- frames -- and not the one tile per iteration this used to step.  Forty
  -- iterations of descent buy four beats and no more.
  local changes = 0
  for i = 2, #frames do
    if frames[i] ~= frames[i - 1] then changes = changes + 1 end
  end
  T.check(changes >= 10 and changes <= 21,
    "a beat per thirteen iterations -- four tile changes each -- not one per "
    .. "iteration (" .. changes .. " changes in 120 frames)")
  T.check(swayMax > 12,
    "it sways by the cart's own amplitude, not the +/-12 band ("
    .. swayMax .. " px)")
  T.check(lowest > startPy, "and keeps descending while it does")

  -- 4. it settles just above the player, then the battle starts.  The 161
  --    iterations are 322 frames, and the tick count is not asserted: what
  --    matters is that the sprite goes BEFORE the battle screen.
  local guard = 0
  while #world.battles == 0 and guard < 400 do
    guard = guard + 1
    tick(world, 1)
  end
  T.eq(#world.npcs, 0, "Celebi is despawned when the descent ends")
  T.eq(#world.battles, 1, "and only then does the battle start")
  T.eq(world.battles[1].battleType, "celebi", "with BATTLETYPE_CELEBI")
  T.eq(world.battles[1].wild.level, 30, "against CELEBI at level 30")
  -- the freeze point plus the `float_up`/`float_down` nudge, so "on the shrine
  -- tile" is within a few pixels rather than exact
  T.check(math.abs(celebi.py - world.player.cellY * 16) <= 4,
    "having descended all the way onto the player's tile (py=" .. celebi.py .. ")")
  drain(world)
  T.eq(stageOf(save), "caught", "and the catch still banks the quest")

  -- 5. `appear ILEXFOREST_KURT` at (8,29) then four step UP, the closing
  --    line, four step DOWN, disappear.  Gold has no Kurt object in Ilex
  --    Forest at all, so he is spawned.
  T.eq(#world.npcs, 1, "Kurt appears once CELEBI is caught")
  local kurt = world.npcs[1]
  T.eq(kurt.cellX, 8, "at the cart's (8,29)")
  T.eq(kurt.cellY, 29, "at the cart's (8,29)")
  tick(world, 1)
  T.eq(kurt.stepDir, "up", "and walks up towards the player")
  tick(world, 16 * 4 + 24)
  drain(world)
  -- Kurt's LAST box in the event, and the one the report names: the battle
  -- callback plays it, so no press ever resolved an object for it and the
  -- portraits mod had nobody to draw.  It names its speaker instead, with the
  -- "KURT: " token the Gold ROM's own Kurt text uses in ten of its boxes and
  -- CustomArt/KURT.png answers for.
  local caught = world.texts[#world.texts]
  T.eq(caught:match("^(KURT):%s"), "KURT",
    "saying Text_KurtCaughtCelebi, named by a KURT: token")
  T.check(caught:find("Whew", 1, true) ~= nil, "and it is the closing line")
  tick(world, 16 * 4 + 24)
  T.eq(#world.npcs, 0, "and walks back out again")

  -- and the world is walkable again
  busyCalls = 0
  World2.busy(world)
  T.eq(busyCalls, 1, "World.busy defers to the engine once the cutscene ends")
end

-- ---- the descent without the sheet -----------------------------------------
--
-- The sheet is the player's file, so "no sheet" is the state a fresh install
-- is in, and it has to be a WORKING state.  It used to be fatal:
-- beginShrineDescent treated a sprite it could not build as a reason to
-- abandon the whole cutscene, so a missing picture cost the player the entire
-- shrine event -- the "!", the step back, the 160-iteration descent and the
-- Lv30 battle -- over art.  It now says so once and descends anyway, and this
-- is that path.
--
-- The same press as above, on a fresh world, with the sheet taken back out.
do
  files[SHEET_KEY] = nil
  Data.gen2Sprites = {}
  local mark = logMark()

  local save = newSave({ inventory = withBall() })
  save.modData.celebi_event = { stage = "restless" }
  local world = shrineWorld(save)
  press(world)

  -- Past the cart's `pause 20 / showemote / FadeOutMusic / step back /
  -- pause 30 / turnobject / pause 20`, which is where the sprite would appear.
  -- 200 is the tick the sheet-present run reaches the sprite on, so the
  -- spawn attempt has certainly happened by 210 and the descent is still
  -- running (the cart's 161 iterations are 322 frames on their own).
  tick(world, 210)
  T.eq(#world.npcs, 0, "no Celebi sprite without the sheet")
  T.eq(Data.gen2Sprites.SPRITE_CELEBI, nil,
    "and no sprite definition was registered for it")
  T.eq(#world.battles, 0, "and the descent is still running, not skipped")

  -- ...and the event plays out.  The frame count is the evidence that it
  -- really descended: the cart's 161 iterations are two frames each, so a
  -- cutscene that had been skipped would reach the battle almost immediately.
  local guard = 0
  while #world.battles == 0 and guard < 400 do
    guard = guard + 1
    tick(world, 1)
  end
  T.check(guard > 250,
    "the descent really ran before the battle (" .. guard .. " frames)")
  T.eq(#world.battles, 1, "the battle still starts")
  T.eq(world.battles[1].battleType, "celebi", "with BATTLETYPE_CELEBI")
  T.eq(world.battles[1].wild.level, 30, "against CELEBI at level 30")
  drain(world)
  T.eq(stageOf(save), "caught", "and the catch still banks the quest")
  T.eq(#world.npcs, 1, "and Kurt still appears afterwards")

  -- The sprite was declined rather than built, and the mod says so once.
  -- Read after the descent rather than at a chosen tick, so the assertion is
  -- about the run and not about a frame count.
  local descentLog = modLogSince(mark)
  T.check(#descentLog.warn >= 1, "the mod says so in the log")
  T.check(descentLog.warn[1] and descentLog.warn[1]:find("without a sprite", 1, true),
    "naming what it is missing (" .. tostring(descentLog.warn[1]) .. ")")

  -- ...and the cutscene has to tear down here, which it does once Kurt has
  -- walked back out -- the same tick sequence the sheet-present block uses.
  -- A cutscene still set holds World.busy true, which stalls the script queue
  -- for every block that follows this one, so this is not cosmetic: stopping
  -- one step short of the walk-out here is what broke the Kurt's-house block.
  tick(world, 1)
  tick(world, 16 * 4 + 24)
  drain(world)
  tick(world, 16 * 4 + 24)
  T.eq(#world.npcs, 0, "and Kurt walks back out again")

  busyCalls = 0
  World2.busy(world)
  T.eq(busyCalls, 1, "and the world is walkable again afterwards")

  -- the sprite's absence must not have been reported as an ERROR
  T.eq(#descentLog.error, 0, "and nothing went wrong quietly ("
    .. tostring(descentLog.error[1]) .. ")")

  -- Put the sheet back.  This is the only block that runs without one, and
  -- leaving it out would make every later descent sheet-less too -- the
  -- hand-over block's shrine run near the end of this file does one -- which
  -- still passes, because it only asserts the battle and the teardown.  That is
  -- the problem: the sprite path would stop being exercised anywhere after this
  -- point and nothing would say so.
  files[SHEET_KEY] = "PLAYER-SUPPLIED-SHEET-FIXTURE"
end

-- ---- Kurt ------------------------------------------------------------------

local KURT = "KURTS_HOUSE"

-- The Kurt the player talks to.  He has to be WALKABLE: the cart's
-- `.NotMakingBalls` sends him out of the house, and only the object the press
-- was aimed at can do that.
local function makeKurt(index)
  return {
    def = { index = index or 1 },
    facing = "down", moving = false,
    scriptStep = function(self, dir)
      if self.moving then return false end
      self.stepDir = dir
      self.moving = true
      self.stepCountdown = self.stepFrames or 16
      return true
    end,
  }
end

local function kurtWorld(save, opts)
  opts = opts or {}
  opts.npc = opts.npc or makeKurt()
  return newWorld(KURT, save, opts)
end

do
  -- the quest has not started: Gold's own Kurt conversation must survive
  local world = kurtWorld(newSave())
  local result, vanilla = press(world)
  T.eq(vanilla, 1, "an untouched Kurt still reaches the engine's own body")

  -- Crystal: the CART's own event gave the ball, so this mod's stage is nil.
  -- The ball is the trigger, exactly as `checkitem GS_BALL` is in the cart's
  -- own KurtsHouseKurtScript -- and both balls are the same key, because
  -- data.items and save.inventory are keyed by the item's ID.
  local crystalSave = newSave({ inventory = withBall() })
  T.eq(stageOf(crystalSave), nil,
    "no mod stage at all, as a Crystal cart carrying its own ball would be")
  world = kurtWorld(crystalSave)
  result, vanilla = press(world)
  T.eq(vanilla, 0, "a ball in the bag ALONE makes KURT take the press")
  T.eq(crystalSave.inventory.GS_BALL, nil, "and he takes the native GS BALL")
  T.eq(stageOf(crystalSave), "given",
    "and the quest picks up from there, on this mod's own stage")

  -- visit 1: hand the ball over
  local save = newSave({ inventory = withBall() })
  save.modData.celebi_event = { stage = "have" }
  world = kurtWorld(save)
  result, vanilla = press(world)
  T.eq(vanilla, 0, "Kurt takes the press once the quest is running")
  T.eq(save.inventory.GS_BALL, nil, "and takes the GS BALL")
  T.eq(stageOf(save), "given", "and the quest moves on")

  -- the same day: "I'm checking it now."
  world = kurtWorld(save)
  press(world)
  T.eq(stageOf(save), "given", "the same day leaves the quest alone")
  T.eq(save.inventory.GS_BALL, nil, "and does not hand the ball back")
  T.eq(#world.texts, 2, "and plays the checking pair")

  -- the DEBUG toggle: same state, same talk, no wait.  Both directions are
  -- driven from a save parked in the same-day state, so the only difference
  -- between the two runs is the option.
  local function givenToday()
    local s = newSave()
    s.modData.celebi_event = { stage = "given", given_day = Clock.weekday(s) }
    return s
  end

  local quickSave = givenToday()
  run.loader.modOptions.celebi_event = { skip_kurt_wait = true }
  local quick = kurtWorld(quickSave)
  press(quick)
  T.eq(stageOf(quickSave), "left",
    "DEBUG on: the same talk sends KURT out, with no wait")
  T.eq(quickSave.inventory.GS_BALL, nil, "and the ball goes with him")
  T.eq(#quick.texts, 1, "after the shaking line alone")
  -- Walk his exit out: a cutscene is module-level and one left running would
  -- block every later scenario, which is a harness bug, not a mod one.  A
  -- guard loop rather than a frame count, because a miscount here is invisible
  -- until every block after it fails.
  local quickGuard = 0
  while #quick.hidden == 0 and quickGuard < 400 do
    quickGuard = quickGuard + 1
    tick(quick, 1)
  end
  T.eq(#quick.hidden, 1, "and he leaves the house")
  -- and let the queue hand the map music back, so nothing is left running
  tick(quick, 40)

  local slowSave = givenToday()
  run.loader.modOptions.celebi_event = { skip_kurt_wait = false }
  local slow = kurtWorld(slowSave)
  press(slow)
  T.eq(stageOf(slowSave), "given",
    "DEBUG off: the wait is back and the same talk changes nothing")
  T.eq(slowSave.inventory.GS_BALL, nil, "and the ball stays with KURT")
  T.eq(#slow.texts, 2, "playing only the checking pair")
  run.loader.modOptions.celebi_event = nil

  -- The rollover: KURT is shocked, runs out of the house and disappears,
  -- taking the ball with him.  Clock.weekday is (hostWeekday + rtc.startDay)
  -- % 7, so shifting startDay by one is a day having passed.
  local before = Clock.weekday(save)
  save.rtc.startDay = (save.rtc.startDay or 0) + 1
  T.check(Clock.weekday(save) ~= before, "the harness really rolled the day")
  world = kurtWorld(save)
  local kurt = world.faced
  press(world)
  T.eq(stageOf(save), "left", "the rollover sends KURT out of the house")
  T.eq(save.inventory.GS_BALL, nil, "and he takes the ball with him")
  T.eq(#world.texts, 1, "after the shaking line and nothing else")
  T.eq(#world.hidden, 0, "he has not vanished yet")
  -- A queue starts on the tick after it is armed, not inside the press, and the
  -- cart's first two commands are `special FadeOutMusic` and `pause 20`.
  musicFades = {}
  T.eq(#musicFades, 0, "the tune has not been faded yet")
  tick(world, 1)
  T.eq(#musicFades, 1, "`special FadeOutMusic` comes first")
  tick(world, 20 * 2)
  T.check(not kurt.moving, "and he stands still through `pause 20`")
  T.eq(#world.emotes, 0, "with no '!' up yet")
  tick(world, 1)
  T.eq(world.emotes[1].frames, 30, "then the '!' is up for 30 frames")
  -- The "!" is SILENT, and it HOLDS.  Script_showemote has no `playsound` in it
  -- at all, and its `pause 0` holds the script for the `time` operand at two
  -- frames a unit -- so no cue rings and SFX_FLY cannot start until the bubble
  -- is down.  (An earlier build rang SFX_BUMP with the bubble.)
  T.eq(#world.sfx, 0, "and it rings NO cue -- the cart's showemote is silent")
  tick(world, 30 * 2 - 1)
  T.eq(#world.sfx, 0, "and SFX_FLY still waits one frame short of the 60")
  tick(world, 1)
  T.eq(#world.sfx, 0, "and on the last frame of the bubble's hold")
  tick(world, 1)
  T.eq(world.sfx[1], "Sfx_Fly", "`playsound SFX_FLY`, right at the movement")
  tick(world, 1)
  T.check(kurt.moving, "which is the walk itself, not a sound before it")
  -- `readvar VAR_FACING / ifequal UP, .GSBallRunAround`: the player is standing
  -- below him, so he goes RIGHT first rather than walking through them.
  T.eq(kurt.stepDir, "right", "right first, so he does not cross the player")
  tick(world, 8)
  T.eq(kurt.stepDir, "down", "and then down towards the door")
  tick(world, 8 * 5 + 8)
  T.eq(#world.hidden, 1, "and then he is gone")
  T.eq(world.hidden[1], 2,
    "the object the press was aimed at (def index 1, so objectId 2)")
  T.eq(world.musicRestored, 1, "and the map music comes back behind him")
end

-- ---- KURT outside, in Azalea Town ------------------------------------------
--
-- The half the mod used to fold into the house: KURT is standing outside, and
-- the scene walks the player to him and hands the ball back.  The cart runs it
-- from `coord_event 9, 6`; the mod cannot add one, so it is reached by walking
-- onto that tile or by talking to him.

local AZALEA = "AZALEA_TOWN"

do
  local save = newSave()
  save.modData.celebi_event = { stage = "left" }
  local kurt = makeKurt(200)
  kurt.def.owner = "celebi_event"
  kurt.def.sprite = "SPRITE_KURT"
  -- a spawned object's id is what WorldAPI:removeNpc / removeRuntimeObject
  -- take, so the harness has to give it one
  kurt.id = AZALEA .. "_obj_200"
  kurt.cellX, kurt.cellY = 6, 5
  local world = newWorld(AZALEA, save, { npc = kurt, fx = 9, fy = 6 })
  world.npcs[1] = kurt

  -- AzaleaTownKurtScript: faceplayer / writetext / waitbutton / turnobject /
  -- closetext -- ONE line and no item.  Talking to him is NOT how the ball
  -- comes back.
  local result, vanilla = press(world)
  T.eq(vanilla, 0, "talking to KURT outside owns the press")
  T.eq(#world.texts, 1, "and says exactly one line")
  T.check(world.texts[1]:find("why ILEX FOREST", 1, true) ~= nil,
    "which is AzaleaTownKurtText3")
  T.eq(save.inventory.GS_BALL, nil, "and hands over nothing")

  -- The ball comes from `coord_event 9, 6`.  A Gen 2 mod cannot add one, so
  -- the mod watches that tile on world.stepped -- driven here with the payload
  -- the engine itself emits (src/world/gen2/World.lua:11107).
  Runtime.emit("world.stepped", { mapId = AZALEA, x = 9, y = 6 })
  tick(world, 1)
  T.check(world.player.moving, "the coord tile walks the player over to him")
  T.eq(world.player.stepDir, "left", "left first, as the cart's movement does")

  tick(world, 16 * 3 + 24)
  T.eq(world.player.stepDir, "up", "then LEFT, LEFT, UP")
  drain(world)
  T.eq(stageOf(save), "restless", "the scene turns the forest restless")
  T.eq(world.player.facing, "left", "the player is left facing KURT")
  T.eq(#world.sfx, 1, "ringing the acquisition cue once ("
    .. table.concat(world.sfx, ",") .. ")")
  T.eq(world.sfx[1], "Sfx_Item", "the ordinary item jingle")
  -- and he STAYS outside, as the cart leaves him: AzaleaTownKurtScript answers
  -- a press with text3 and nothing else, and nothing ever sets
  -- EVENT_AZALEA_TOWN_KURT again
  T.eq(#world.npcs, 1, "KURT stays outside after handing the ball back")
  T.eq(kurt.cellX, 6, "at his own (6,5)")
  T.eq(save.inventory.GS_BALL, 1, "and KURT hands the GS BALL back")
  T.eq(kurt.facing, "left", "and turns back to face left afterwards")
  T.check(#world.texts >= 4,
    "the three ILEX FOREST lines plus the receipt (" .. #world.texts .. ")")
  -- The hand-back is the other conversation no press starts -- the coord tile
  -- runs it -- so its three Kurt boxes name their speaker with the ROM's own
  -- "KURT: " token, while the receipt line (which is not Kurt talking) does
  -- not.  Asserted here because this is the only place the three lines play.
  -- The earlier press left AzaleaTownKurtText3 at [1], so the scene's own four
  -- boxes are the last four.
  local n = #world.texts
  for i = n - 3, n - 1 do
    T.eq(world.texts[i]:match("^(KURT):%s"), "KURT",
      "hand-back line " .. (i - (n - 4)) .. " names KURT in the text")
  end
  T.eq(world.texts[n]:match("^(KURT):%s"), nil,
    "and the receipt line does not put words in his mouth")

  -- and the shrine is live now, which is the join between the two halves
  local shrine = shrineWorld(save)
  local _, shrineVanilla = press(shrine)
  T.eq(shrineVanilla, 0, "the returned ball makes the shrine live")
  local shrineGuard = 0
  while #shrine.battles == 0 and shrineGuard < 900 do
    shrineGuard = shrineGuard + 1
    tick(shrine, 1)
  end
  drain(shrine)
  T.eq(#shrine.battles, 1, "and the event runs end to end")
  -- and walk Kurt's closing approach out, so the cutscene slot is free
  tick(shrine, 1)
  tick(shrine, 16 * 4 + 24)
  drain(shrine)
  tick(shrine, 16 * 4 + 24)
end

-- ---- the Goldenrod hand-over ----------------------------------------------
--
-- GoldenrodPokecenter1F_GSBallSceneLeft / ...Right are COORD EVENTS on the two
-- doorway tiles -- the receptionist has no script of her own on either cart, and
-- the offer is an entrance cutscene rather than a conversation.  A Gen 2 mod
-- cannot add a coord event, so the mod watches world.stepped for those tiles.
--
-- It is the STEP ONTO the tile, which is the step out of the Center: the same
-- step World:step is about to hand to checkWarpOnArrive, so the scene has to
-- hold that warp back itself (see the next scenario).  Walking IN does not run
-- it -- a warp arrival is not a step.

local PC = "GOLDENROD_POKECENTER_1F"
local DOOR_LEFT_X, DOOR_RIGHT_X, DOOR_Y = 3, 4, 7
local STAIRS_X, STAIRS_Y = 0, 7
local MUSIC_SHOW_ME_AROUND = 17

-- The player steps out through the door.  A press first arms the mod's own
-- `liveWorld` (the harness has no `mod.world` to resolve), and the press on this
-- map is not the mod's any more, so it falls straight through to the engine.
--
-- `heldDir` is set because that is what the engine's carpet-warp test reads:
-- Game2 polls input before World:step (src/core/Game2.lua:1268-1271), so a
-- player walking out with DOWN held arrives here with it set -- which is exactly
-- the frame the mod has to stand the warp down on.
local function stepOut(save, x, y)
  local world = newWorld(PC, save, {})
  world.player.cellX, world.player.cellY = x or DOOR_LEFT_X, y or DOOR_Y
  world.heldDir = "down"
  run.loader.modSave = save.modData
  press(world)
  world.heldDir = "down"
  Runtime.emit("world.stepped",
    { mapId = PC, x = world.player.cellX, y = world.player.cellY })
  return world
end

local function receptionist(world)
  for _, npc in ipairs(world.npcs) do
    if npc.def and npc.def.owner == "celebi_event" then return npc end
  end
end

do
  -- `setval BATTLETOWERACTION_GSBALL / special BattleTowerAction / ifequal
  -- GS_BALL_AVAILABLE, .gsball` -- and the cart's own bare `end` when it is
  -- not.  No line, no box, no cue: stepping out before the HALL OF FAME simply
  -- does nothing, which is Crystal's behaviour rather than a hint the cart
  -- never gives.
  local save = newSave({ hallOfFame = {} })
  local world = stepOut(save)
  tick(world, 4)
  drain(world)
  T.eq(#world.texts, 0, "nothing is said before the HALL OF FAME")
  T.eq(#world.npcs, 0, "and no receptionist appears")
  T.eq(save.inventory.GS_BALL, nil, "and nothing is handed over")
  T.eq(stageOf(save), nil, "and the quest does not start")
  T.eq(#world.sfx, 0, "and no cue is rung")
  T.eq(#world.music, 0, "and no music is played")
  -- ...and the decline must NOT stand the exit warp down, or the player would be
  -- left standing on the doorway instead of walking out.
  T.eq(world.heldDir, "down",
    "a declined scene leaves the exit warp alone")

  -- qualified: the whole scene, in the cart's order
  save = newSave()
  T.check(HallOfFame.hasEntered(save), "the harness save has entered the HOF")
  world = stepOut(save)
  local npc = receptionist(world)
  T.check(npc ~= nil, "the receptionist is placed")
  T.eq(npc and npc.def.sprite, "SPRITE_LINK_RECEPTIONIST",
    "wearing the cart's own sprite for her")
  -- `PAL_NPC_BLUE` (9) on the cart's own object_event: the high nybble of the
  -- palette byte, which Palettes.objectPaletteId takes `% 8` of and hands back
  -- as OBJ palette 1 -- the blue one, and the reason she has blue hair.  A 0
  -- here would mean "the sprite's own default" and she would come out wrong.
  T.eq(npc and npc.def.palette, 9,
    "in PAL_NPC_BLUE, the palette the cart's object_event names")
  T.eq(Palettes.objectPaletteId(npc and npc.def), 1,
    "which resolves to OBJ palette 1 -- blue")
  T.eq(npc and npc.cellX, STAIRS_X, "at the cart's stairs tile (0,7)")
  T.eq(npc and npc.cellY, STAIRS_Y, "and its y")

  -- The step that ran the scene is also the step that would have warped the
  -- player out: these tiles are COLL_WARP_CARPET_DOWN, and checkWarpOnArrive
  -- takes the carpet arm when the held direction matches -- so the mod drops the
  -- held direction for the frame and the warp stands down.
  T.eq(world.heldDir, nil, "the exit warp is stood down for the scene")

  -- `playmusic MUSIC_SHOW_ME_AROUND`, before she moves a tile -- and NO cue.
  -- `.gsball` opens with `playsound SFX_EXIT_BUILDING`, but that is the sound of
  -- the hero actually leaving the building, which is what the cart's step out
  -- does.  Here the scene stands that warp down so the receptionist can reach
  -- him, so the hero stops on the tile and nobody has left: the cue is dropped.
  T.eq(#world.sfx, 0, "the scene opens with NO cue -- nobody has left")
  T.eq(#world.music, 1, "but it switches the music once")
  T.eq(world.music[1], MUSIC_SHOW_ME_AROUND,
    "to MUSIC_SHOW_ME_AROUND, the cart's own song")

  -- `applymovement ...ApproachPlayerAtLeftDoorwayTileMovement`: UP then three
  -- RIGHT, from the stairs to the tile above the LEFT doorway.
  tick(world, 1)
  T.check(npc and npc.moving, "she walks over to the player")
  T.eq(npc and npc.stepDir, "up", "UP first, as the cart's movement does")
  tick(world, 16 * 3 + 24)
  T.eq(npc and npc.stepDir, "right", "then RIGHT, one per tile of the way")
  tick(world, 16 * 3 + 24)
  drain(world)
  T.eq(npc and npc.facing, "down", "and `turn_head DOWN` leaves her facing you")
  T.eq(world.player.facing, "up", "`turnobject PLAYER, UP`")
  T.eq(save.inventory.GS_BALL, 1, "the receptionist hands over the GS BALL")
  T.eq(stageOf(save), "have", "and starts the quest")
  -- The engine's token is {PLAYER} (src/render/TextBox.lua:237); <PLAYER> is
  -- the ASM macro and the tokenizer's pattern is {..} only, so a macro left in
  -- the transcription renders as the literal word.  The harness records the
  -- RAW body, which is what makes this checkable.
  T.eq(#world.texts, 3, "the offer, the receipt and `please come again`")
  T.check(world.texts[1]:find("{PLAYER}", 1, true) == 1,
    "the offer names the player with the engine's {PLAYER} token")
  for _, body in ipairs(world.texts) do
    T.check(not body:find("<PLAYER>", 1, true),
      "and no ASM macro survives in the dialogue")
  end
  -- the acquisition cue: the same jingle every `verbosegiveitem` rings, which
  -- is the BICYCLE / ROD / ITEMFINDER sound
  T.eq(#world.sfx, 1, "receiving the ball rings the scene's first cue")
  T.eq(world.sfx[1], "Sfx_Item",
    "and it is Sfx_Item -- the ordinary item jingle, not the TM one")

  -- `applymovement ...WalkToStairsFromLeftDoorwayTileMovement`: three LEFT then
  -- DOWN, back to the stairs -- then `special RestartMapMusic`, `disappear` and
  -- one more SFX_EXIT_BUILDING.
  tick(world, 1)
  T.eq(npc and npc.stepDir, "left", "she walks back the way she came")
  tick(world, 16 * 4 + 24)
  drain(world)
  T.eq(npc and npc.stepDir, "down", "ending on the stairs' own DOWN step")
  T.eq(world.musicRestored, 1, "`special RestartMapMusic` hands the map back")
  T.eq(#world.npcs, 0, "and she disappears")
  T.eq(#world.sfx, 2, "with the closing cue")
  T.eq(world.sfx[2], "Sfx_ExitBuilding",
    "which is SFX_EXIT_BUILDING -- HERS, as she vanishes")

  -- `checkevent EVENT_GOT_GS_BALL_FROM_GOLDENROD_POKEMON_CENTER / iftrue
  -- .cancel`: a second walk out does nothing at all, and must not hold the warp.
  world = stepOut(save)
  tick(world, 4)
  drain(world)
  T.eq(save.inventory.GS_BALL, 1, "a second walk out does not hand out another")
  T.eq(#world.texts, 0, "and says nothing")
  T.eq(#world.npcs, 0, "and shows no receptionist")
  T.eq(#world.sfx, 0, "and rings nothing")
  T.eq(world.heldDir, "down", "and the exit warp is not stood down either")

  -- The OTHER suppression, and the one that matters on Crystal: a ball already
  -- in the bag, with no mod stage at all -- the cart's own event gave it.  Both
  -- balls are the same key, so one test covers the native one and this mod's.
  save = newSave({ inventory = withBall() })
  T.eq(stageOf(save), nil, "no mod stage, as a Crystal cart would be")
  T.check(HallOfFame.hasEntered(save), "and the Hall of Fame gate is open")
  world = stepOut(save)
  tick(world, 4)
  drain(world)
  T.eq(#world.npcs, 0, "a ball in the bag starts no receptionist scene")
  T.eq(#world.texts, 0, "and says nothing")
  T.eq(#world.sfx, 0, "and rings nothing")
  T.eq(save.inventory.GS_BALL, 1,
    "and the ball the player already had is left alone, not doubled")
  T.eq(stageOf(save), nil, "and no mod stage is started")
  T.eq(world.heldDir, "down",
    "and the exit warp is not stood down for a scene that never ran")

  -- The RIGHT doorway is the other scene: one more RIGHT going out and one
  -- more LEFT coming back, and nothing else differs.
  save = newSave()
  world = stepOut(save, DOOR_RIGHT_X, DOOR_Y)
  npc = receptionist(world)
  T.check(npc ~= nil, "the right doorway places her too")
  T.eq(world.heldDir, nil,
    "and the warp is stood down on the right doorway tile too")
  tick(world, 1)
  tick(world, 16 * 4 + 24)
  T.eq(npc and npc.stepDir, "right", "four RIGHT for the right doorway")
  tick(world, 16 * 3 + 24)
  drain(world)
  T.eq(npc and npc.facing, "down", "and she still ends facing the player")
  T.eq(save.inventory.GS_BALL, 1, "and the ball still changes hands")
  tick(world, 1)
  tick(world, 16 * 5 + 24)
  drain(world)
  T.eq(npc and npc.stepDir, "down", "with four LEFT and a DOWN to walk back")
  T.eq(#world.npcs, 0, "and she is gone")

  -- Walking IN is not the trigger: a warp arrival is not a step, so stepping
  -- anywhere else in the Center -- including the stairs tile from POKECENTER_2F
  -- and the middle of the room -- runs nothing.
  save = newSave()
  world = stepOut(save, STAIRS_X, STAIRS_Y)
  tick(world, 4)
  drain(world)
  T.eq(#world.npcs, 0, "the stairs tile is not the trigger")
  T.eq(#world.texts, 0, "and nothing is said")
  T.eq(save.inventory.GS_BALL, nil, "and nothing is handed over")
  T.eq(world.heldDir, "down", "and no warp is stood down")

  world = stepOut(save, 5, 4)
  tick(world, 4)
  drain(world)
  T.eq(#world.npcs, 0, "nor is the middle of the room")
  T.eq(save.inventory.GS_BALL, nil, "and still nothing is handed over")
end

-- ---- the interception never eats an unrelated press ------------------------

do
  -- an NPC that is not ours, on a map we do handle
  local save = newSave()
  local world = newWorld(PC, save, { npc = { def = { index = 1 } } })
  local _, vanilla = press(world)
  T.eq(vanilla, 1, "somebody else's NPC still reaches the engine")
  T.eq(#world.sfx, 0, "and a press we do not own rings nothing")

  -- and a press somewhere else entirely
  world = newWorld("NEW_BARK_TOWN", save, {})
  local _, vanilla2 = press(world)
  T.eq(vanilla2, 1, "and a press on any other map still reaches the engine")
  T.eq(#world.sfx, 0, "and rings nothing there either")
end

-- ---- Kurt's house: the bench swap and the granddaughter ---------------------

do
  -- Gold's KURTS_HOUSE objects, from the real ROM: KURT1 (3,2) on flag 1854,
  -- TWIN (5,3) with no flag, SLOWPOKE, KURT2 (14,3) on flag 1855.
  local OBJECTS = {
    { index = 1, eventFlag = 1854 }, { index = 2 }, { index = 3 },
    { index = 4, eventFlag = 1855 },
  }
  local function houseWorld(stage, givenDay)
    local save = newSave()
    save.modData.celebi_event = { stage = stage, given_day = givenDay }
    local world = newWorld(KURT, save)
    world.maps = { [KURT] = { objects = OBJECTS } }
    world.npcs[1] = { def = { sprite = "SPRITE_TWIN" },
                      cellX = 5, cellY = 3, px = 80, py = 48,
                      facing = "down", kind = "spin" }
    press(world)                          -- arms liveWorld, nothing else
    Runtime.emit("map.entered", { mapId = KURT })
    return world
  end

  -- KurtsHouseKurtCallback's .MakingBalls arm: ENGINE_KURT_MAKING_BALLS is a
  -- DAILY flag, so the bench swap holds only while the day has not rolled over
  local today = Clock.weekday(newSave())
  local world = houseWorld("given", today)
  T.eq(#world.hidden, 1, "KURT1 is taken off the map while he studies")
  T.eq(world.hidden[1], 2, "object 2, which is def index 1")
  T.eq(#world.appeared, 1, "and KURT2 is put on it")
  T.eq(world.appeared[1], 5, "object 5, which is def index 4 -- the bench")
  local twin = world.npcs[1]
  T.eq(twin.cellX, 11, "the granddaughter relocates to (11,4)")
  T.eq(twin.cellY, 4, "beside her grandfather")
  T.eq(twin.facing, "right", "facing right, as Crystal's TWIN2 does")
  T.eq(twin.kind, "stand", "and stands rather than spinning")

  world = houseWorld("given", today)
  world.faced = world.npcs[1]
  press(world)
  T.eq(#world.texts, 1, "the granddaughter says one thing")
  T.check(world.texts[1]:find("Grandpa's checking", 1, true) == 1,
    "KurtsGranddaughterGSBallText")

  -- Once the day has rolled over he is back at the door -- which is what makes
  -- his five-step exit reach the door at all.
  world = houseWorld("given", (today + 1) % 7)
  T.eq(world.appeared[1], 2, "the day rolling over puts KURT1 back at the door")
  T.eq(world.hidden[1], 5, "and takes KURT2 off the bench")

  -- The restless stretch: KURT ran out of the house, and the cart's callback
  -- returns without touching anything once the forest is restless -- so neither
  -- Kurt is on the map, and the granddaughter is HOME.  She is the one who says
  -- "Grandpa's gone…", and this is the only stretch where that is true.
  world = houseWorld("restless", (today + 1) % 7)
  T.eq(#world.appeared, 0, "the restless forest leaves no KURT in the house")
  T.eq(#world.hidden, 2, "neither of them")
  T.eq(world.npcs[1].cellX, 5, "and the granddaughter is back home")
  world.faced = world.npcs[1]
  press(world)
  T.check(world.texts[1]:find("Grandpa's gone", 1, true) == 1,
    "KurtsGranddaughterLonelyText")

  -- The CRYSTAL START: the cart's own ball in the bag and NO mod stage at all.
  -- The callback must leave the house exactly as the quest-not-started
  -- arrangement -- KURT1 at the door (3,2), KURT2 off the map, the granddaughter
  -- home -- because the ball being KURT's trigger does not move anybody until he
  -- has actually taken it.  This is the reader the bag rule could most easily
  -- have disturbed, since it branches on the stage and nothing else.
  world = houseWorld(nil, nil)
  T.eq(#world.appeared, 1, "with no stage the callback shows exactly one object")
  T.eq(world.appeared[1], 2, "KURT1, at the door, ready to be talked to")
  T.eq(#world.hidden, 1, "and hides exactly one")
  T.eq(world.hidden[1], 5, "KURT2, who is off the map until he studies")
  T.eq(world.npcs[1].cellX, 5, "and the granddaughter is still at home")
  T.eq(world.npcs[1].cellY, 3, "at (5,3), not at the bench")

  -- A FINISHED save: the shrine cleared EVENT_FOREST_IS_RESTLESS, so the
  -- callback runs its normal ladder again and KURT1 is home.  She must not be
  -- saying "Grandpa's gone…" from a doorway he is standing in -- that state is
  -- one the cart's own twin conversation answers, and the press falls through
  -- to it.
  world = houseWorld("caught", (today + 1) % 7)
  T.eq(world.appeared[1], 2, "a finished save has KURT1 home again")
  world.faced = world.npcs[1]
  local textsBefore = #world.texts
  local _, twinVanilla = press(world)
  T.eq(twinVanilla, 1, "and the granddaughter reaches the engine's own body")
  T.eq(#world.texts, textsBefore, "with nothing of the mod's said over it")

  -- and the default state puts KURT1 back at the door
  world = houseWorld(nil)
  T.eq(#world.appeared, 1, "with no quest running KURT1 is on the map")
  T.eq(world.appeared[1], 2, "at the door end")
  T.eq(world.npcs[1].cellX, 5, "and the granddaughter is back home")
end

-- ---- Kurt's exit effects ----------------------------------------------------

do
  local save = newSave()
  save.modData.celebi_event = { stage = "given", given_day = -1 }
  local world = kurtWorld(save)
  local kurt = world.faced
  press(world)
  -- .NotMakingBalls, in its own order.  `pause 20` and the fade come first:
  -- the sequence used to play SFX_FLY up front and then hold the walk until it
  -- had finished, which put the whoosh a whole sound ahead of the animation.
  musicFades = {}
  T.eq(#world.emotes, 0, "the '!' waits for the cart's `pause 20`")
  T.eq(#musicFades, 0, "and the fade has not started yet")
  tick(world, 1)
  T.eq(#musicFades, 1, "`special FadeOutMusic`")
  tick(world, 20 * 2 + 1)
  T.eq(#world.emotes, 1, "then Kurt gets the '!' emote")
  T.eq(world.emotes[1].emote, 0, "EMOTE_SHOCK")
  T.eq(world.emotes[1].frames, 30, "for 30 frames, not the player's 20")
  T.eq(world.emotes[1].object, kurt.def.index + 1,
    "on the Kurt the player actually talked to")
  -- The "!" is SILENT: nothing in Script_showemote plays a sound, so there is no
  -- cue on it and SFX_FLY is the first sound of the whole exit.
  -- (An earlier build rang SFX_BUMP here as an addition.)
  T.eq(#world.sfx, 0, "the '!' rings NO cue -- the cart's showemote is silent")
  T.eq(world.sfx[1], nil, "and SFX_FLY has NOT been played yet")
  -- `pause 0`: the bubble's 30 units, i.e. 60 frames, and the run starts as
  -- they run out -- `playsound SFX_FLY` sits immediately BEFORE the movement.
  tick(world, 30 * 2 - 1)
  T.eq(#world.sfx, 0, "nothing is cued one frame short of the emote's hold")
  tick(world, 1)
  T.eq(#world.sfx, 0, "nor on its last frame")
  tick(world, 1)
  T.eq(world.sfx[1], "Sfx_Fly", "then SFX_FLY, as the movement starts")
  tick(world, 1)
  T.check(kurt.moving, "with the walk itself, not a sound before it")
  -- `playsound SFX_EXIT_BUILDING` / `disappear` / `waitsfx` /
  -- `special RestartMapMusic`.  The cue is held busy here, so BOTH the vanish
  -- and the map theme are seen to wait for it -- which is the order the cart
  -- writes, and the reason the tune never lands on top of the exit sound.
  sfxBusy = true
  local guard = 0
  while #world.hidden == 0 and guard < 200 do
    guard = guard + 1
    tick(world, 1)
  end
  T.eq(world.sfx[#world.sfx], "Sfx_ExitBuilding",
    "it ends with SFX_EXIT_BUILDING")
  T.eq(kurt.stepFrames, 8, "he runs at the cart's big_step cadence")
  T.eq(#world.hidden, 0, "and does NOT vanish while the cue is still playing")
  T.eq(world.musicRestored, nil, "nor does the map theme come back over it")
  sfxBusy = false
  tick(world, 2)   -- one tick to spend the row, one to run what is behind it
  T.eq(#world.hidden, 1, "once it has finished he is gone")
  T.eq(world.musicRestored, 1, "and the map music comes back behind him")
end

-- ---- Kurt's way out, over a map that says no ---------------------------------

-- `applymovement` refuses a step the cart cannot take (CanObjectMoveInDirection,
-- engine/overworld/npc_movement.asm:1); the port's scripted step does not.  So
-- the route is computed from the map, and this is the map: 16x8 like
-- KURTS_HOUSE, the bottom row a wall except the two door tiles at (3,7) and
-- (4,7), and the bench at (14,3).
do
  local function houseMap()
    local walls = {}
    local function wall(x, y) walls[y * 1024 + x] = true end
    for x = 0, 15 do wall(x, 0) end
    for x = 0, 15 do
      if x ~= 3 and x ~= 4 then wall(x, 7) end
    end
    for y = 0, 7 do wall(0, y) wall(15, y) end
    local DELTA = { down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 },
                    up = { 0, -1 } }
    return {
      id = KURT, def = { objects = {}, bgEvents = {} },
      warps = { { x = 3, y = 7 }, { x = 4, y = 7 } },
      isWall = walls,
      inBounds = function(_, x, y)
        return x >= 0 and y >= 0 and x <= 15 and y <= 7
      end,
      objectStepPermitted = function(_, x, y, dir)
        local d = DELTA[dir]
        return not walls[(y + d[2]) * 1024 + (x + d[1])]
      end,
    }
  end

  -- Walk one exit out, recording every tile he was sent across: a step is a
  -- `moving` that starts, so each one is one entry.  The collapsed list is the
  -- SHAPE of the walk -- a leg per direction -- and the full one is the route.
  local function walkOut(startX, startY)
    local save = newSave()
    save.modData.celebi_event = { stage = "given", given_day = -1 }
    local world = kurtWorld(save)
    world.map = houseMap()
    local kurt = world.faced
    kurt.cellX, kurt.cellY = startX, startY
    -- Every direction he is actually SENT in, which is the route: the step's
    -- own `moving` is not observable between ticks, but the call is.
    local full, shape = {}, {}
    local inner = kurt.scriptStep
    kurt.scriptStep = function(self, dir)
      local started = inner(self, dir)
      if started then
        full[#full + 1] = dir
        if shape[#shape] ~= dir then shape[#shape + 1] = dir end
      end
      return started
    end
    press(world)
    local guard = 0
    while #world.hidden == 0 and guard < 400 do
      guard = guard + 1
      tick(world, 1)
    end
    return world, full, shape
  end

  -- KURT1 at (3,2) is the cart's own case: five `big_step DOWN` and he is on
  -- the door tile.
  local world, dirs, shape = walkOut(3, 2)
  T.eq(#dirs, 5, "KURT1 at the door end walks the cart's own five tiles")
  T.eq(table.concat(shape, ","), "down",
    "straight down (" .. table.concat(shape, ",") .. ")")
  T.eq(#world.hidden, 1, "and leaves the house")
  T.eq(world.musicRestored, 1, "with the map music handed back behind him")

  -- KURT2 at the bench (14,3) is the case the cart never has to write, and the
  -- one that used to walk him into the wall: down out of the bench, then left
  -- across the room, then out of the door.
  world, dirs, shape = walkOut(14, 3)
  T.eq(table.concat(shape, ","), "down,left,down",
    "KURT2 walks down and then left to the door ("
    .. table.concat(shape, ",") .. ")")
  T.eq(#dirs, 14, "fourteen tiles from the bench to the door ("
    .. #dirs .. ")")
  -- and the route really is on the floor: every step is replayed against the
  -- map's own collision and has to land somewhere a walk into a wall would not.
  local map, x, y, walk = houseMap(), 14, 3, {}
  local DELTA = { down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 },
                  up = { 0, -1 } }
  for i = 1, #dirs do
    local d = DELTA[dirs[i]]
    walk[#walk + 1] = dirs[i]
    local nx, ny = x + d[1], y + d[2]
    T.check(not map.isWall[ny * 1024 + nx],
      "step " .. i .. " (" .. dirs[i] .. ") does not walk into a wall")
    x, y = nx, ny
  end
  T.eq(x, 4, "and the last step lands on the door tile (" .. x .. "," .. y .. ")")
  T.eq(y, 7, "which is the warp out of the house")
  T.eq(#world.hidden, 1, "and then he is gone")
end

-- ---- only ever one Kurt outside ---------------------------------------------

do
  local save = newSave()
  save.modData.celebi_event = { stage = "left" }
  local world = newWorld(AZALEA, save, {})
  press(world)
  Runtime.emit("map.entered", { mapId = AZALEA })
  T.eq(#world.npcs, 1, "Kurt appears outside his house")
  T.eq(world.npcs[1].cellX, 6, "at the cart's (6,5)")
  T.eq(world.npcs[1].cellY, 5, "at the cart's (6,5)")
  Runtime.emit("map.entered", { mapId = AZALEA })
  Runtime.emit("map.entered", { mapId = AZALEA })
  T.eq(#world.npcs, 1, "and re-entering does not put a second one there")
  -- the scene hands the ball back, so he must not survive it
  save.modData.celebi_event.stage = "restless"
  Runtime.emit("map.entered", { mapId = AZALEA })
  T.eq(#world.npcs, 0, "and he is gone once the scene is over")
end

-- ---- nothing went wrong quietly ---------------------------------------------

-- Every cutscene runs inside a pcall, and the mod reports a failure through
-- mod.log:error ("cutscene aborted: ...") rather than throwing at the engine.
-- A silent abort is exactly the shape of "the animation just stopped", so the
-- whole run is asserted against it at the end.
local wholeRun = modLogSince(0)
T.eq(#wholeRun.error, 0, "no cutscene aborted, and nothing else was reported ("
  .. tostring(wholeRun.error[1]) .. ")")

-- ---- Gold, Silver and Crystal ----------------------------------------------
--
-- The mod RUNS on all three Gen 2 carts.  What the cart changes is one thing:
-- whether the GS BALL has to be registered.  Crystal's own item list already
-- names it, and `content.items:register` refuses a duplicate id
-- (Registry.lua:103), so registering there would fail the whole mod rather than
-- run it.
--
-- One scenario per cart.  The decision is the CAPABILITY -- "does this ROM
-- already carry the GS BALL?" -- and NOT the version id, which is the shape
-- `modkit gen2check` asks for: MK409 flags a version-string comparison, so the
-- last scenario checks that a GS item list still registers with the engine
-- saying "crystal".
--
-- The entry chunk is called directly rather than through the loader: `mod.game`
-- is nil under the headless loader (Loader:_game returns nil for generation 2
-- with nothing injected, which is what Game2 does at src/core/Game2.lua:1124),
-- and the cart is what the entry is asking about.  The loader's own gate is a
-- separate question, answered by the manifest's `games: ["gen2"]` -- ModTargets
-- expands that token to gold, silver and crystal, which is what the boot matches
-- on.  `/.probe/faithful_boot_probe.lua` drives the whole thing with the game
-- injected, the way Game2 does.

do
  local entry = assert(loadfile(MOD_DIR .. "/main.lua"))()

  -- The version id is a module-level on GameVersion, so it is put back.  All of
  -- `fn`'s returns are forwarded -- `drive` answers four things now.
  local function asVersion(id, fn)
    local prev = GameVersion.get()
    GameVersion.set(id)
    local results = { fn() }
    GameVersion.set(prev)
    -- LuaJIT spells it `unpack`; 5.2+ moved it to `table.unpack`
    return (table.unpack or unpack)(results)
  end

  local function drive(game)
    local registered, logged, options, handlers = 0, 0, 0, 0
    entry({
      id = "celebi_event",
      game = game,
      log = { info = function() logged = logged + 1 end,
              warn = function() end, error = function() end },
      save = { get = function() return nil end, set = function() end },
      options = { define = function() options = options + 1 end,
                  get = function() return false end },
      events = { on = function() handlers = handlers + 1 end,
                 emit = function() end },
      content = { items = { register = function() registered = registered + 1 end } },
      world = nil,
    })
    return registered, logged, options, handlers
  end

  -- The two GS carts: an item list with a placeholder where Crystal names
  -- GS_BALL.  Gold's and Silver's are the same list -- the engine derives
  -- tools/rom_manifest_silver.json from Gold's and constants.itemOrder is
  -- byte-identical between them -- so one scenario shape covers both, and the
  -- version id is what differs.
  local gsCart = { data = { items = { RAGECANDYBAR = {} } } }
  local reg, logged, opts, handlers = asVersion("gold",
    function() return drive(gsCart) end)
  T.eq(reg, 1, "on Gold the GS BALL is registered")
  T.eq(logged, 0, "and nothing is reported")
  T.eq(opts, 1, "with the options defined")
  T.check(handlers > 0, "and the event handlers installed")

  reg, logged, opts, handlers = asVersion("silver",
    function() return drive(gsCart) end)
  T.eq(reg, 1, "on Silver the GS BALL is registered too")
  T.eq(logged, 0, "and nothing is reported there either")
  T.eq(opts, 1, "with the options defined")
  T.check(handlers > 0, "and the event handlers installed")

  -- Crystal: the mod RUNS -- this is not a stand-down any more -- but the
  -- cart's own item list already names GS_BALL (constants.itemOrder[114] is
  -- "GS_BALL" on Crystal, "ITEM_73"/"ITEM_74" on the GS carts), so a second
  -- registration would be refused by the registry and fail the whole mod.
  reg, logged, opts, handlers = asVersion("crystal", function()
    return drive({ data = { items = { GS_BALL = { id = "GS_BALL" } } } })
  end)
  T.eq(reg, 0, "a Crystal-shaped item list registers no second GS BALL")
  T.eq(logged, 1, "and says why")
  T.eq(opts, 1, "but the mod still runs there -- the options ARE defined")
  T.check(handlers > 0, "and the event handlers ARE installed")

  -- ...and the decision is the CAPABILITY, not the cart: a GS item list is
  -- registered even with the engine saying "crystal", which is the shape
  -- `modkit gen2check` asks for (MK409 flags a version-string test).
  reg, logged, opts = asVersion("crystal", function() return drive(gsCart) end)
  T.eq(reg, 1, "a GS item list still registers, whatever the version id says")
  T.eq(logged, 0, "and nothing is reported on that answer")
  T.eq(opts, 1, "with the options defined")
end

-- ---- the in-game options ---------------------------------------------------

do
  -- The label is what the player reads under MODS, so it is checked as written
  -- rather than by eye.  `skip_kurt_wait` is a debug switch in the code's own
  -- words, but the option is not labelled as one.
  local entry = assert(loadfile(MOD_DIR .. "/main.lua"))()
  local labels = {}
  entry({
    id = "celebi_event",
    game = { data = { items = { RAGECANDYBAR = {} } } },
    log = { info = function() end, warn = function() end, error = function() end },
    save = { get = function() return nil end, set = function() end },
    options = {
      -- `mod.options:define(rows)` is a colon call, so the rows are the SECOND
      -- argument and the first is the options facade itself.
      define = function(_, rows)
        for _, row in ipairs(rows) do labels[#labels + 1] = row.label end
      end,
      get = function() return false end,
    },
    events = { on = function() end, emit = function() end },
    content = { items = { register = function() end } },
    world = nil,
  })
  T.eq(#labels, 2, "the mod defines two options")
  for _, label in ipairs(labels) do
    T.check(not label:find("DEBUG", 1, true),
      ("no option label is marked DEBUG (%q)"):format(label))
  end
  T.check(#labels >= 2 and labels[2] == "Skip KURT's 24-hour wait",
    "and the wait switch reads as a plain label")
end

run.release()
T.finish("celebi_event")

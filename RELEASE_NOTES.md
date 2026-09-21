<!-- This file IS the release body. .github/workflows/release.yml publishes it verbatim, and the game launcher renders that body in its "What's New?" modal (src/mods/ModUpdate.lua's cleanBody, drawn by LauncherView's buildTextModal). Rewrite it for each version, and keep the first line short: the launcher also shows it as the one-line preview on the update row (ModUpdate.previewLine, 90 characters). Markdown is stripped rather than rendered, so headings, dashes and plain lines are all that survive -- no tables, no nested lists, and avoid paired underscores or asterisks, which the cleaner removes as emphasis markers. -->

v1.5.0: Celebi descends facing the way the cart draws it.

## What's new

- Fixed: Celebi's descent sprite was drawn horizontally
  mirrored for the whole animation, so it faced away from
  the player exactly where the cart faces it.
- The cart's CELEBI_LEFT frameset is the unflipped one, and
  this mod mirrored on the opposite side. It mirrors on the
  right one now.
- Present in every version, 1.4.8 included, so this is a fix
  rather than a change of mind. The sheet, the timing, the
  160 iterations and the battle are all untouched.

## The quest, in full

- The GOLDENROD POKeMON CENTER receptionist, KURT studying the
  ball at his bench, the hand-back outside his house in AZALEA
  TOWN, and Celebi's descent at the ILEX FOREST shrine.
- Two switches under MODS: reach the event without the HALL OF
  FAME, and skip KURT's 24-hour wait.
- Celebi's descent sprite is included and draws on Gold, Silver
  and Crystal alike.

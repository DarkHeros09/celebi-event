<!-- This file IS the release body. .github/workflows/release.yml publishes it verbatim, and the game launcher renders that body in its "What's New?" modal (src/mods/ModUpdate.lua's cleanBody, drawn by LauncherView's buildTextModal). Rewrite it for each version, and keep the first line short: the launcher also shows it as the one-line preview on the update row (ModUpdate.previewLine, 90 characters). Markdown is stripped rather than rendered, so headings, dashes and plain lines are all that survive -- no tables, no nested lists, and avoid paired underscores or asterisks, which the cleaner removes as emphasis markers. -->

v1.4.8: KURT's exit and the GS BALL hand-back are one scene now.

## What's new

- The world stays locked from the moment KURT runs out of his
  house until the GS BALL is back in your bag. There is no longer
  a window where you get control back in between.
- The hand-back starts on the doorstep. Leave the house and the
  mod walks you down onto the cart's own trigger tile, over to
  KURT, and plays the three lines -- so the scene always runs
  from the right spot, whichever way you were facing inside.
- Walking out and turning away no longer strands the scene: it
  used to wait on a tile you might never step on.

## The quest, in full

- The GOLDENROD POKeMON CENTER receptionist, KURT studying the
  ball at his bench, the hand-back outside his house in AZALEA
  TOWN, and Celebi's descent at the ILEX FOREST shrine.
- Two switches under MODS: reach the event without the HALL OF
  FAME, and skip KURT's 24-hour wait.
- Celebi's descent sprite is included and draws on Gold, Silver
  and Crystal alike.

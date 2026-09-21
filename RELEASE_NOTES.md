<!-- This file IS the release body. .github/workflows/release.yml publishes it verbatim, and the game launcher renders that body in its "What's New?" modal (src/mods/ModUpdate.lua's cleanBody, drawn by LauncherView's buildTextModal). Rewrite it for each version, and keep the first line short: the launcher also shows it as the one-line preview on the update row (ModUpdate.previewLine, 90 characters). Markdown is stripped rather than rendered, so headings, dashes and plain lines are all that survive -- no tables, no nested lists, and avoid paired underscores or asterisks, which the cleaner removes as emphasis markers. -->

v1.4.9: runs alongside Wilds of Kanto now.

## What's new

- Fixed: with Wilds of Kanto installed, the GOLDENROD POKeMON
  CENTER receptionist appeared at the stairs and would not
  move, so her scene never finished and the world stayed
  locked.
- Wilds of Kanto takes over the engine's per-frame step while
  it loads, and that removed this mod's own tick. The tick is
  now restored automatically, whichever mod loads last.
- The scene itself is unchanged: the same lines, the same
  movements and the same tiles.

## The quest, in full

- The GOLDENROD POKeMON CENTER receptionist, KURT studying the
  ball at his bench, the hand-back outside his house in AZALEA
  TOWN, and Celebi's descent at the ILEX FOREST shrine.
- Two switches under MODS: reach the event without the HALL OF
  FAME, and skip KURT's 24-hour wait.
- Celebi's descent sprite is included and draws on Gold, Silver
  and Crystal alike.

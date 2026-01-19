## Changelog

## v1.6.3

Midnight compatibility hardening.

Fix potential Lua error when formatting item quality colors (convert RGB floats to integers before %02x).

Add defensive tooltip hook fallback if TooltipDataProcessor or Enum.TooltipDataType is unavailable.

No functional or visual behavior changes.

## v1.6.2

- Remove alpha-hiding during scale settle (could leave frame invisible in edge cases).
- Add short preview pulse after restore so you can always spot the frame even when locked.
- Minor safety tweaks & logs.

## v1.6.1

- Fix rare Lua error when scale events fired before the frame existed (attempt to index upvalue 'frame').
- Create frame on demand in all paths; guard settings UI sync when frame may be nil.

## v1.6.0

- New scale-settle restore: wait until UI scale stops changing (or matches saved target) before placing the frame — prevents visible jumps with UI scaling addons.
- Save the effective scale at drop time and target that scale on restore.
- Keep persistent debug logging (/idtooltip debug on|off).
- One clean restore + optional fade logic (later removed in 1.6.2).

## v1.5.1

- Fix Lua syntax error (} else {) introduced in 1.5.0.
- Keep center-based save + BL restore pipeline.

## v1.5.0

- Switch to center-based, pixel-snapped saving and absolute BOTTOMLEFT restoring for maximum stability across reloads, scales, and resolutions.
- Persist debug setting across reloads; add /idtooltip restore for manual testing.
- Backward-compatible: convert old bottom-left % saves to center % once.

## v1.4.0

- Add robust late restore scheduling:
- Run on PLAYER_ENTERING_WORLD, next frame, and +0.05s to catch initial layout.
- Mark frame UserPlaced (SetUserPlaced(true)) to prevent layout nudges.
- Add /idtooltip debug on|off with precise save/restore logs.

## v1.3.0

- Make save/restore scale-safe using effective (physical pixel) coords.
- Defer first restore to next frame to avoid drift after /reload.

## v1.2.1

- Fix Retail Settings checkbox template usage (replaced SettingsCheckBoxTemplate .Text access with UICheckButtonTemplate + explicit label).
- Name the width slider so its Low/High/Text regions exist and update properly.

## v1.2.0

- Move to Dragonflight Settings UI (canvas category) for Retail.
- Add options parity with slash commands: Locked, Show/Hide, Reset, Width slider.
- Improve “unlocked edit mode”: when unlocked, frame stays visible, ignores tooltips, and can be dragged freely.

## v1.1.0

Add unlocked “edit mode” toggle via right-click (lock/unlock) with quick tooltip confirmation.

Add /idtooltip show|hide|reset commands.

Save and restore position across sessions.

## v1.0.4

- published to wago.io

## v1.0.3

- updated for 11.2

## v1.0.2

- commented out debug lines


## v1.0.1

- Corrected typo in TOC


## v1.0.0

- Initial release
- Shows Item and Spell IDs in a movable frame
- Item ID text reflects item quality color
- Position saving and restoring added
- Slash commands: /idtooltip show, hide, reset
- Right-click frame to lock/unlock

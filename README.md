# DruidMonro

World of Warcraft addon for Druids. Copy the `DruidMonro` folder into `World of Warcraft\_retail_\Interface\AddOns\`.

Open the configuration with `/druidm` (or `/druidmonro`), or via **Game Menu > Options > AddOns > DruidMonro**.

## Settings window
The settings are one window with a sidebar listing every feature: **General**, **Bear Form text**,
**Moonfire indicator**, **Moonfire count**, **Ability trackers**, **Rage panel** and **Absorb shield**. Each feature page groups its options in a titled panel; the panel
title is the feature's **on/off checkbox**, and its options are dimmed while the feature is off. A dot next to each
sidebar entry shows at a glance whether that feature is on (green) or off (grey). **Unlock to move** and
**Reset all** stay at the bottom of the sidebar on every page.

## Features

### 1. Not in Bear Form text
Shows a text on screen whenever you are a Druid and not in Bear Form.

- **Only show in combat** - on by default; turn it off to show the text all the time.
- **Text** - any string you like.
- **Font** - built-in fonts, plus every font registered with LibSharedMedia if an addon provides it.
- **Color** - color picker.
- **Font size** and **outline**.

### 2. Moonfire proc indicator
Glows the Moonfire count icon (see below) while Moonfire is procced (Guardian's Galactic Guardian). It is the same icon,
so size and position are set on the Moonfire count page. If no counted mobs are in combat, the icon still appears for the
proc, without the counter. Detected through the spell-activation overlay for Moonfire, with the Galactic Guardian aura as a
fallback.

- **Glow effect** - None, Pulse, Pixel border, or Blizzard proc (falls back to Pulse if the client lacks that art).

### 3. Moonfire count
Shows the Moonfire icon with a counter such as `3/5`: how many of the mobs you are fighting currently carry **your**
Moonfire. The text turns green when every mob is covered. Shown only in combat while at least one hostile mob is in combat.

- **Icon size**, **font size**, **text color** and **location** (drag it).
- Only mobs that have a **nameplate** are counted, so enemy nameplates must be enabled and the mobs within nameplate
  range (about 40 yards).
- The client may hide aura details on enemy units in combat (Midnight "secret" values); mobs whose Moonfire cannot be read
  are counted as not having it.

### 4. Ability trackers
Has its own page, with the tracker list on the left and the selected tracker's settings on the right. Each tracker shows a text while its ability has no charge or is on
cooldown (e.g. "NO CHARGE", "NO KICK"). Create up to 10 independent trackers, each with its own:

- **Ability** - spell name (of a spell you know) or spell ID.
- **Text**, **font**, **color**, **font size**, **outline**.
- **Location** - drag it. Trackers can be enabled/disabled or removed individually.

Trackers hide automatically if you do not know the spell (wrong spec/talent). Short cooldowns (the global cooldown)
are ignored.

### 5. Rage panel
A rage bar shown while you are in Bear Form.

- **Width** (50 to 600) and **height** (8 to 100).
- **Color** - color picker for the bar.
- **Show rage number** and **Only show in combat**.
- **Glow when rage is full**: a pulsing golden border around the bar while rage is at maximum (always shown while previewing/unlocked).
- **Location** - drag it.

### 6. Absorb shield
Shows the Power Word: Shield icon with the **total absorb on you** as a full number (e.g. `315081`) while
Frenzied Regeneration is active. Absorbs from other sources are included in the number.

- **Icon size** and **font size**, **location** (drag it).
- **Also show for absorbs from other sources** - show the icon whenever you have any absorb, not only during Frenzied Regeneration.
- If the client hides the absorb value (Midnight "secret" values), the icon still shows for Frenzied Regeneration but the number is blank.

### Turning features on and off
Each feature panel has an enable checkbox as its title (Not in Bear Form text, Moonfire proc indicator, Ability
trackers, Rage panel, Absorb shield), and the minimap button has **Show minimap button** on the General page. A disabled feature is hidden
completely, including in the unlock/preview mode. Individual trackers can still be toggled on their own.

### Positioning
Press **Unlock to move** in the sidebar (or `/druidm unlock`) to show every element regardless of game state and drag
them. While the panel is open, all elements are also previewed so you can see font, color and glow changes live.

### Minimap button
A minimap button (bear icon) gives quick access: **left-click** opens the configuration, **right-click** toggles
unlock/lock, **drag** moves it around the minimap. It can be hidden from the General page or with `/druidm minimap`.

## Commands

| Command | Effect |
| --- | --- |
| `/druidm` | open the configuration panel |
| `/druidm unlock` | toggle unlock/lock for dragging |
| `/druidm minimap` | show or hide the minimap button |
| `/druidm reset` | reset everything to defaults |

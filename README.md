# DruidMonro

World of Warcraft addon for Druids. Copy the `DruidMonro` folder into `World of Warcraft\_retail_\Interface\AddOns\`.

Open the configuration with `/druidm` (or `/druidmonro`), or via **Game Menu > Options > AddOns > DruidMonro**.

## Settings window
The settings are one window with a sidebar listing every feature: **General**, **Bear Form text**,
**Moonfire indicator**, **Ability trackers**, **Rage panel**, **Absorb shield** and **Voice reminders**. Each feature page groups its options in a titled panel; the panel
title is the feature's **on/off checkbox**, and its options are dimmed while the feature is off. A dot next to each
sidebar entry shows at a glance whether that feature is on (green) or off (grey). **Unlock to move** and
**Reset all** stay at the bottom of the sidebar on every page.

## Features

### 1. Not in Bear Form text
Shows a text on screen whenever you are a Druid and not in Bear Form.

- **Only show in combat** - on by default; turn it off to show the text all the time.
- **Only show in dungeons** - off by default; when on, the text shows only inside 5-player dungeons (not raids or the open world).
- **Text** - any string you like.
- **Font** - built-in fonts, plus every font registered with LibSharedMedia if an addon provides it.
- **Color** - color picker.
- **Font size** and **outline**.

### 2. Moonfire proc indicator
Shows a Moonfire icon while Moonfire is procced (Guardian's Galactic Guardian). Detected through the spell-activation
overlay for Moonfire, with the Galactic Guardian aura as a fallback.

- **Glow effect** - None, Pulse, Pixel border, or Blizzard proc (falls back to Pulse if the client lacks that art).
- **Size** - 24 to 200.
- **Location** - drag it.

### 3. Ability trackers
Has its own page, with the tracker list on the left and the selected tracker's settings on the right. Each tracker shows a text while its ability has no charge or is on
cooldown (e.g. "NO CHARGE", "NO KICK"). Create up to 10 independent trackers, each with its own:

- **Ability** - spell name (of a spell you know) or spell ID.
- **Text**, **font**, **color**, **font size**, **outline**.
- **Location** - drag it. Trackers can be enabled/disabled or removed individually.

Trackers hide automatically if you do not know the spell (wrong spec/talent). Short cooldowns (the global cooldown)
are ignored.

### 4. Rage panel
A rage bar shown while you are in Bear Form.

- **Width** (50 to 600) and **height** (8 to 100).
- **Color** - color picker for the bar.
- **Show rage number** and **Only show in combat**.
- **Glow when rage is full**: a pulsing golden border around the bar while rage is at maximum (always shown while previewing/unlocked).
- **Location** - drag it.

### 5. Absorb shield
Shows the Power Word: Shield icon with the **total absorb on you** as a full number (e.g. `315081`) while you have any
absorb - Frenzied Regeneration's and any other source's are included in the number. It hides itself when the absorb is gone.

- **Icon size** and **font size**, **location** (drag it).
- **Only while Frenzied Regeneration is active** - off by default. It relies on reading your Frenzied Regeneration buff,
  which the client may hide in Mythic+ and other restricted content; leave it off there.
- The icon and number also work when the client hides the absorb value (Midnight "secret" values, e.g. in Mythic+): they are
  passed straight to the display without the addon reading them.
- `/druidm absorbdebug` prints what the client lets the addon read.

### 6. Voice reminders
Spoken callouts through the game's built-in text-to-speech (the same engine and voice handling as MonroMDTTrack's boss
callouts), so no sound files are needed.

- **Trinket** - pick any **on-use trinket** on your character (equipped or in your bags) from the dropdown. Both options
  below work only while that trinket is equipped.
  - **Say "Trinket ready"** each time its cooldown ends. Lockouts of 30s or less are ignored, so equipping a trinket or
    using your other on-use trinket does not trigger it.
  - **Glow on action bars while ready** - the trinket's button on the default Blizzard action bars (placed directly or
    through a macro such as `/use 13`) shows the proc glow whenever the trinket can be used. Previewed while the
    settings are open. Bars from other addons (Bartender, ElvUI, Dominos) are not supported.
- **Heart of the Wild ready** - says "Heart of the Wild ready" when Heart of the Wild comes off cooldown (only while talented).
- **Apex proc** - says "Apex" when Wild Guardian (the Guardian apex talent) awakens a guardian spirit, i.e. when you gain
  the Answered Calling buff. A new spirit that only refreshes the buff is announced too.
- **Voice** - pick an installed Windows speech voice, or **Automatic**: the voice chosen in MonroMDTTrack if any,
  otherwise the best installed one (Windows 11 "Natural" voices first). **Test** speaks a sample and prints why if it fails.
- Speech rate and volume follow the game's Text to Speech settings. Add more voices under Windows
  **Settings > Time & Language > Speech**, then `/reload`.
- If the client hides cooldowns (Midnight restricted content), a successful use restarts the longest cooldown seen for
  that trinket/spell so the reminder still fires.

### Turning features on and off
Each feature panel has an enable checkbox as its title (Not in Bear Form text, Moonfire proc indicator, Ability
trackers, Rage panel, Absorb shield, Heart of the Wild ready, Apex proc), and the minimap button has **Show minimap button** on the General page. A disabled feature is hidden
completely, including in the unlock/preview mode. Individual trackers can still be toggled on their own, and the trinket's voice and glow have their own checkboxes.

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
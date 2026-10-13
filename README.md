# DruidMonro

World of Warcraft addon for Druids. Copy the `DruidMonro` folder into `World of Warcraft\_retail_\Interface\AddOns\`.

Open the configuration with `/druidm` (or `/druidmonro`), or via **Game Menu > Options > AddOns > DruidMonro**.

## Features

### 1. Not in Bear Form text
Shows a text on screen whenever you are a Druid and not in Bear Form.

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
Found under **DruidMonro > Ability trackers**. Each tracker shows a text while its ability has no charge or is on
cooldown (e.g. "NO CHARGE", "NO KICK"). Create up to 10 independent trackers, each with its own:

- **Ability** - spell name (of a spell you know) or spell ID.
- **Text**, **font**, **color**, **font size**, **outline**.
- **Location** - drag it. Trackers can be enabled/disabled or removed individually.

Trackers hide automatically if you do not know the spell (wrong spec/talent). Short cooldowns (the global cooldown)
are ignored.

### Positioning
Press **Unlock to move** in the panel (or `/druidm unlock`) to show every element regardless of game state and drag
them. While the panel is open, all elements are also previewed so you can see font, color and glow changes live.

## Commands

| Command | Effect |
| --- | --- |
| `/druidm` | open the configuration panel |
| `/druidm unlock` | toggle unlock/lock for dragging |
| `/druidm reset` | reset everything to defaults |

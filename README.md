# DruidMonro

World of Warcraft addon for Druids. Copy the `DruidMonro` folder into `World of Warcraft\_retail_\Interface\AddOns\`.

It also has a runic power bar for Death Knights (see below). It works on other classes too: the Druid-only features (Bear Form text, Moonfire indicator, Rage panel, Enrage panel,
Heart of the Wild reminder and Apex proc) stay off and disappear from the settings window, while the class-independent ones keep
working - **Ability trackers**, **Ability glow**, the **Absorb shield** icon, the **trinket** voice reminder and action-bar glow, the voice
selection and the minimap button. (The "Only while Frenzied Regeneration is active" absorb option is Druid-only too.)

Open the configuration with `/druidm` (or `/druidmonro`), or via **Game Menu > Options > AddOns > DruidMonro**.

## Settings window
The settings are one window with a sidebar listing every feature: **General**, **Bear Form text**,
**Moonfire indicator**, **Ability trackers**, **Ability glow**, **Rage panel**, **Enrage panel**, **Absorb shield** and **Voice reminders**. Each feature page groups its options in a titled panel; the panel
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

In combat the client hides cooldowns and charges from addons or reports them as ready, so a tracker does not rely on
reading them there: a successful cast (matched by ID or by name, so form-specific versions such as Wild Charge's count)
starts the addon's own timer - the longest cooldown seen, or the spell's base cooldown - and charge abilities count their
charges down and recharge them the same way. Out of combat the client's reading takes over again; in combat only a
reading that shows the ability still on cooldown is believed, never one that says "ready". Several casts of the same ability within a second (Charge reports two, with different spell
IDs) count as one use. `/druidm trackerdebug` prints, per tracker, what the client reports, what the addon believes and
the last casts it saw.

### 4. Ability glow
Works on every class. The **Ability glow** page keeps a list of abilities for the class you are playing (each class has its
own list, so an alt of another class starts empty) with no limit on its size. Type a spell name (of a spell you know) or
spell ID and press Enter to add it; each row has a checkbox to switch that ability off without removing it, and a
**Remove** button. The status column shows live whether the ability is **ready**, **on cooldown** or **not known**.

While an ability can be used, every action-bar button that casts it glows with the same Blizzard proc glow as the trinket,
and the glow stops while it is on cooldown or out of charges (a charge ability glows while it has at least one charge).
Buttons are found whether the spell is placed directly or through a `/cast` macro, on the default Blizzard bars,
**ButtonForge**, and LibActionButton bars (**Bartender4**, **ElvUI**). Abilities you do not know (wrong spec or talent)
never glow. While the settings are open every enabled ability is previewed as glowing. The panel title is the on/off
switch for the whole page.

Cooldowns are followed exactly like the ability trackers do (the addon's own timer from your casts when the client hides
cooldowns in combat), and an ability can be in both lists. `/druidm glowdebug` lists, per ability, its state and which
buttons hold it.

### 5. Rage panel
A rage bar shown while you are in Bear Form.

- **Width** (50 to 600) and **height** (8 to 100).
- **Color** - color picker for the bar.
- **Show rage number** and **Only show in combat**.
- **Glow when rage is full**: a pulsing golden border around the bar while rage is at maximum (always shown while previewing/unlocked).
- **Location** - drag it.

#### Runic power bar (Death Knight)
Death Knight only, shown in the sidebar as **Runic power bar**. The same kind of bar as the rage panel, for runic power, with a
white **split line** at 75 (of 100) and a pulsing icy-blue **glow** while runic power is at or above that line.

- **Split line and glow at** (10 to 100, default 75) moves the line and the glow threshold together.
- **Width**, **height**, **color**, **Show runic power number**, **Only show in combat** and **Glow when at or above the split line**
  work like the rage panel's. Unlike the rage panel it is not tied to a form, so it is shown whenever you are a Death Knight.
- **Location** - drag it.

### 6. Enrage panel
Druid only. A small panel that appears while an enemy carries an enrage you can Soothe and lists those mobs, the one
enraged longest first, so you know which one to cast it on.

- Each row shows the mob's **raid marker** (the Soothe icon when it has none), its **name**, its **health %** and how many
  **seconds** it has been enraged; the mob's health also fills the row behind the text. The header counts the enraged mobs.
- **Say "Soothe"** when a mob enrages, through the same voice as the voice reminders. Several mobs enraging together are one
  callout. **Test** speaks it.
- **Mark the mob's nameplate** puts a pulsing Soothe icon next to the enraged mob's nameplate, which is how you tell identical
  mobs apart. It is the one part that works in combat inside a dungeon (see below). It never assigns or changes raid markers, and it sits to the **right** of the nameplate by default so it stays
  clear of raid markers (usually drawn above or at the left); **Marker position** moves it to the left, above or below.
  Its size is adjustable, and every enraged mob gets one, also the ones that do not fit in the list.
- **Panel width**, **Mobs listed** (1 to 6) and **location** (drag it). Previewed with sample mobs while the settings are
  open or unlocked.
- Mobs are found through their **enemy nameplates**, so those must be turned on and the mob within nameplate range. The
  panel needs Soothe in your spellbook; the settings page says whether it is found.
- **The marker is drawn by the game, not by the addon.** Every enemy nameplate gets an aura container, the same engine
  mechanism Plater, EllesmereUI and MiniAuras use for enemy buffs. Its filter is evaluated by the game, so it keeps working
  in combat inside a dungeon, where addons are not allowed to read an enemy's buffs. It shows the dispellable buff's own icon
  with an orange pulsing border. **Marker shows** picks the filter: *Enrages I can Soothe* (default, the buffs your group can
  dispel) or *Any dispellable buff* (Magic ones too), the fallback if the first shows nothing.
- **The list and the voice need the addon to know which mob is enraged.** It tries four ways, from the most direct:
  1. **The buff's dispel type, read as a colour** (the technique the Plater "Purge & Soothe" mod uses): the colour goes through
     a curve that is opaque for Enrage and transparent for everything else. Readable out of combat and in the open world;
     a secret value inside a dungeon in combat.
  2. **The spell looked up by ID** (`GetUnitAuraBySpellID`) for the 11 Season 2 enrage spells. It answers even when the
     buff's details are hidden, but only for spells the client classes as readable.
  3. **A Season 2 enrage spell seen in a `UNIT_AURA` payload**, when the payload is not hidden.
  4. **The marker's size.** A marker that holds an icon is wider than an empty one.
  Which of the last three the client allows in dungeon combat is not known in advance. If none does, the list and voice stay
  off there and the marker still does the job.
- **Diagnostics.** While `enrageRecord` is on (the default for now), every couple of seconds in combat the addon notes what
  each query returned on each hostile nameplate (hidden or not, the marker's size, each spell's secrecy class) into its saved
  settings. The game writes it out on `/reload` or logout. `/druidm enragelog` shows how much is recorded; `clear`, `on` and
  `off` control it. Hidden values are never stored.
- `/druidm enragedebug` prints, per enemy nameplate, how many buffs it has, the colour each buff gives (or "hidden"), the
  buff's spell ID and name where the client lets the addon read them, and the marker container's size, which is the first
  thing to check when a mob is missing.
- Every Season 2 Mythic+ mob with an enrage is listed in [docs/midnight-s2-enrages.md](docs/midnight-s2-enrages.md), to use as a
  test list in game.
- It is a display, not a button: targeting and casting are protected actions an addon cannot do for you in combat, so use
  your normal Soothe key or macro (`[@mouseover]` works well) on the marked mob.

### 7. Absorb shield
Shows the Power Word: Shield icon with the **total absorb on you** as a full number (e.g. `315081`) while you have any
absorb - Frenzied Regeneration's and any other source's are included in the number. It hides itself when the absorb is gone.

- **Icon size** and **font size**, **location** (drag it).
- **Only while Frenzied Regeneration is active** - off by default. It relies on reading your Frenzied Regeneration buff,
  which the client may hide in Mythic+ and other restricted content; leave it off there.
- The icon and number also work when the client hides the absorb value (Midnight "secret" values, e.g. in Mythic+): they are
  passed straight to the display without the addon reading them.
- `/druidm absorbdebug` prints what the client lets the addon read.

### 8. Voice reminders
Spoken callouts through the game's built-in text-to-speech (the same engine and voice handling as MonroMDTTrack's boss
callouts), so no sound files are needed.

- **Trinket** - pick any **on-use trinket** on your character (equipped or in your bags) from the dropdown. Both options
  below work only while that trinket is equipped.
  - **Say "Trinket ready"** each time its cooldown ends. Lockouts of 30s or less are ignored, so equipping a trinket or
    using your other on-use trinket does not trigger it.
  - **Glow on action bars while ready** - the trinket's button (placed directly or through a macro such as `/use 13`)
    shows the proc glow whenever the trinket can be used. Works on the default Blizzard bars, **ButtonForge**, and
    LibActionButton bars (**Bartender4**, **ElvUI**); not on other bar addons. Previewed while the settings are open.
    `/druidm glowdebug` prints why it is or is not glowing and which buttons hold the trinket.
- **Heart of the Wild ready** - says "Heart of the Wild ready" when Heart of the Wild comes off cooldown (only while talented).
- **Apex proc** - says "Apex" when Wild Guardian (the Guardian apex talent) awakens a guardian spirit, i.e. when you gain
  the Answered Calling buff (1308647). Since patch 12.1 addons cannot see buffs appear, so the addon registers a
  recorded clip (`Sounds/Apex.ogg`, Zira voice) with `C_UnitAuras.AddAuraSound` and the game plays it itself; **Test**
  plays the clip. Registration is not allowed in combat inside instanced PvE, so it happens on login/loading screens
  and is retried when combat ends. `/druidm spy` prints your casts and new buffs, and says whether the sound is registered.
- **Voice** - pick an installed Windows speech voice, or **Automatic**: the voice chosen in MonroMDTTrack if any,
  otherwise the best installed one (Windows 11 "Natural" voices first). **Test** speaks a sample and prints why if it fails.
- Speech rate and volume follow the game's Text to Speech settings. Add more voices under Windows
  **Settings > Time & Language > Speech**, then `/reload`.
- In combat the client can hide a cooldown or report it as ready, so a successful cast also starts the addon's own timer
  (the longest cooldown seen, or the spell's base cooldown). After a cast, a "ready" reading is only trusted once the
  client has shown that cooldown running.

### Turning features on and off
Each feature panel has an enable checkbox as its title (Not in Bear Form text, Moonfire proc indicator, Ability
trackers, Ability glow, Rage panel, Enrage panel, Absorb shield, Heart of the Wild ready, Apex proc), and the minimap button has **Show minimap button** on the General page. A disabled feature is hidden
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
| `/druidm glowdebug` | show why the trinket and the Glow page's abilities are or are not glowing |
| `/druidm spy` | print your casts and new buffs (run again to stop) |
| `/druidm cddebug` | show what the trinket / Heart of the Wild voice reminders see right now |
| `/druidm trackerdebug` | show what the client reports for each ability tracker and what the addon makes of it |
| `/druidm enragedebug` | show what the client lets the enrage panel read on each enemy nameplate |
| `/druidm enragelog [clear\|on\|off]` | the enrage panel's combat diagnostics, saved on `/reload` |
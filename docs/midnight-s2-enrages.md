# Midnight Season 2: mobs with an enrage you can Soothe

The Season 2 Mythic+ pool (patch 12.1, open since 2026-08-18) has eight dungeons: Altar of Fangs, Murder Row, Den of
Nalorakk, The Blinding Vale, Voidscar Arena, Kings' Rest, Temple of Sethraliss and Ruby Life Pools.

**Five of them have enrages, 21 mobs in all, using 11 different abilities. The other three have none.** Every one of these
buffs has dispel type **Enrage** on Wowhead, which is what Soothe removes. Compiled 2026-10-18.

## Altar of Fangs

| Mob | NPC ID | Enrage | Spell ID |
| --- | --- | --- | --- |
| Ravenous Descendant | 261553 | Ravenous | [1306308](https://www.wowhead.com/spell=1306308) |

## Murder Row

| Mob | NPC ID | Enrage | Spell ID |
| --- | --- | --- | --- |
| Wrathguard Flayer | 235267 | Fel Rage | [1214922](https://www.wowhead.com/spell=1214922) |
| Warehouse Worker | 236893 | Back to Work! | [1216970](https://www.wowhead.com/spell=1216970) |
| Keen Taskmaster | 236897 | Back to Work! | [1216970](https://www.wowhead.com/spell=1216970) |
| Rowdy Patron | 236525 | Unsatisfied Customer | [1213658](https://www.wowhead.com/spell=1213658) |

## Den of Nalorakk

| Mob | NPC ID | Enrage | Spell ID |
| --- | --- | --- | --- |
| Territorial Matriarch | 241808 | Mother's Wrath | [1238053](https://www.wowhead.com/spell=1238053) |
| Curious Yearling | 241809 | Mother's Wrath | [1238053](https://www.wowhead.com/spell=1238053) |
| Bonded Beasttamer | 245145 | Bestial Wrath | [1246865](https://www.wowhead.com/spell=1246865) |
| Loyal Saberfang | 245190 | Bestial Wrath | [1246865](https://www.wowhead.com/spell=1246865) |

## Voidscar Arena

| Mob | NPC ID | Enrage | Spell ID |
| --- | --- | --- | --- |
| Feral Saberon | 243988 | Feral Rage | [1249661](https://www.wowhead.com/spell=1249661) |
| Sycophantic Tarasek | 243983 | Feral Rage | [1249661](https://www.wowhead.com/spell=1249661) |
| Longtooth Tuskarr | 243985 | Feral Rage, **Bolster** | 1249661, [1310319](https://www.wowhead.com/spell=1310319) |
| Chitigoth | 244260 | Feral Rage | [1249661](https://www.wowhead.com/spell=1249661) |
| Raging Raptor | 249608 | Feral Rage | [1249661](https://www.wowhead.com/spell=1249661) |
| Protective Turtle | 249603 | Feral Rage | [1249661](https://www.wowhead.com/spell=1249661) |
| Brutok | 244309 | Feral Rage | [1249661](https://www.wowhead.com/spell=1249661) |
| Abducted Drakonid | 249461 | Feral Rage | [1249661](https://www.wowhead.com/spell=1249661) |
| Dominated Brawler | 238883 | Bloodsurge | [1254826](https://www.wowhead.com/spell=1254826) |

## Kings' Rest

| Mob | NPC ID | Enrage | Spell ID |
| --- | --- | --- | --- |
| Shadow-Borne Champion | 134158 | Ancestral Fury (+150% physical damage) | [269976](https://www.wowhead.com/spell=269976) |
| Skeletal Hunting Raptor | 137487 | Bestial Berserk | [1297763](https://www.wowhead.com/spell=1297763) |
| Queen Patlaa | 137486 | Bestial Berserk | [1297763](https://www.wowhead.com/spell=1297763) |

## No Soothe-able enrage found

The Blinding Vale, Temple of Sethraliss and Ruby Life Pools. No source lists one, and the buffs that look like candidates
are not enrages: Temple of Sethraliss's "Frenzy" is boss Aspix's, and the Blinding Vale spells checked have no dispel type.
No Season 2 affix enrages mobs either (Lindormi's Guidance, Xal'atath's Bargains and Guile, Fortified, Tyrannical).
Boss hard-enrage timers cannot be dispelled.

## How this was compiled

- **MythicDungeonTools** (installed): per-mob spell lists with an `enrage` flag, which gives every row above.
- **ExwindTools** (installed): its `DispelEnrage_List` holds the same 11 spell IDs.
- **Wowhead spell pages**: each of the 11 spells shows dispel type Enrage, and gives the English names.
- **[Gerrit Alex's Season 2 dungeon debuff list](https://gerritalex.de/blog/midnight-s2-debuffs)** agrees for every dungeon,
  except that it omits *Unsatisfied Customer* (a work-in-progress page); Wowhead, MDT and Exwind all have it.
- **DBM** (Kings' Rest trash) independently warns "RemoveEnrage" for Ancestral Fury.

Not enumerated spell by spell: the three "none" dungeons are based on those sources plus Method's ability trackers, not on
opening every spell on Wowhead. If the panel ever lights up on a mob not listed here, `/mtr enragedebug` will name the
buff when the client allows it (spell ID and name), and it can be added.

## What this means for the enrage panel

The marker asks the game for the buffs your group can dispel, and the panel reads each buff's dispel type, so neither depends
on spell names or IDs: all 11 abilities above, and any enrage added in a later patch, are covered by the same check. The names
are unique across the pool (no two dungeons share one), but they cannot be used for detection in combat: the client hides an
enemy buff's spell ID and name there. The list is the test matrix instead: in game, pull one mob from each dungeon above and
check that its nameplate gets the marker (and, where the client allows reading, that it appears in the panel).

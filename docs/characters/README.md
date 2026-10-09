# Fighters

Design notes for every fighter. The numbers come from `tools/build_movesets.gd`, the
source of truth for move data and stats: change values there and re-run it, then update
the page here.

| Fighter | Archetype | HP | CPU style | Signature mechanic |
|---|---|---|---|---|
| [Kenji](kenji.md) | Balanced | 1000 | Zoner | Fireball and invincible uppercut |
| [Rhea](rhea.md) | Rushdown | 960 | Rushdown | Fastest walk and dash, low slide |
| [Brutus](brutus.md) | Power | 1100 | Punisher | Ground-pound shockwave, cross-ring charge |
| [Valka](valka.md) | Grappler | 1050 | Grappler | Command grabs |
| [Jin](jin.md) | Kicker | 980 | Footsies | Longest reach, overhead axe kick |
| [Mira](mira.md) | Brawler | 1000 | Brawler | Focus: powers up with Lakas Stance |
| [Lian](lian.md) | Counter | 980 | Counter | Reversal stance: catches strikes and throws |

## Shared base moves

Every fighter has the same base set, adjusted by their tuning (startup frames, damage,
knockback, hitstop, reach). Kenji's values without his ×1.05 damage:

| Input | Move | Startup / active / recovery | Damage | Level | Notes |
|---|---|---|---|---|---|
| LP | Jab | 4 / 2 / 8 | 30 | High | Cancels into LP, HP, 2LP |
| HP | Straight | 9 / 3 / 18 | 80 | High | |
| LK | Mid Kick | 7 / 3 / 14 | 50 | Mid | Cancels into HP |
| HK | Roundhouse | 13 / 4 / 22 | 110 | High | |
| 2LP | Crouching Jab | 5 / 2 / 9 | 25 | Mid | Cancels into 2LP, 2LK |
| 2LK | Low Kick | 6 / 3 / 13 | 35 | Low | |
| 2HP | Uppercut | 8 / 4 / 24 | 90 | Mid | Launcher |
| 2HK | Sweep | 9 / 4 / 26 | 80 | Low | Knockdown |
| j.LP / j.HP | Jump Jab / Jump Hammer | 4 / 8 / 6, 7 / 5 / 10 | 40 / 75 | Overhead | |
| j.LK / j.HK | Jump Kick / Flying Kick | 5 / 8 / 6, 8 / 6 / 10 | 45 / 85 | Overhead | |
| LP+LK | Throw | 5 startup | 120 (per fighter) | Unblockable | Tech with LP+LK within 10f |

Each fighter adds two or three signature normals, two or three specials and a super
(236236). Specials cancel from connected normals; the super cancels from specials.

## Making a fighter

1. Design: a page here with the concept, look, stats, moves, mechanic and CPU style.
   Keep fighters original: our own names, looks and move names.
2. Animations: new strikes in `tools/build_fight_animations.gd`, then measure the strike
   limb at the impact time for the hitbox.
3. Data: an entry in `tools/build_movesets.gd` (with `create` visuals for a new fighter),
   then run it.
4. Look: a body texture if needed, hair (`tools/build_hair.gd` for new cuts) and an
   outfit in `tools/build_outfits.gd` (run it with `-- <id>`).
5. CPU: a personality in `AIController.PERSONALITIES`.
6. Presentation: voice takes (`assets/audio/voice/fighters/<id>_<kind>_N.ogg`), a routine
   in `FighterShowcase.ROUTINES`, a portrait (`tools/render_portraits.gd -- <id>`), credits.
7. Tests in `tests/sim_test.gd`, and a frame-rate check.

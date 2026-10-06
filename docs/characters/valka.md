# Valka: The Grappler

A towering pro wrestler. She walks opponents down, spins straight through fireballs,
and grabs anyone who just blocks.

## Look

- Female base body, scaled up 6%, long platinum hair.
- Navy wrestling singlet with gold edging, knee pads, wrestling boots.
- Alternate costume (mirror matches): crimson singlet with silver edging, red hair.

## Stats

| HP | Walk | Dash | Throw | Damage | Startup |
|---|---|---|---|---|---|
| 1050 | 1.8 | 5.0 | 150 | ×1.1 | +1 frame |

Knockback ×1.1, hitstop +1, weight 1.15.

## Moves

| Input | Move | What it does |
|---|---|---|
| 6HP | Shoulder Tackle | Lunging shoulder charge. |
| 6LK | Knee Lift | Clinch and knee to the chest. Launches. |
| 63214P | Valkyrie Slam | Command grab (150 damage, 0.95 m range): unblockable and can't be teched, but a whiff is very punishable. |
| 623P | Spinning Lariat | Three spinning hits that pass through fireballs; the last one launches. |
| 236236P | Thunder Valkyrie (super) | Super command grab (240 damage, 1.15 m range), invincible start, finished with a gold shockwave slam. |

Plus the shared base moves (see the [roster overview](README.md)).

## Command grabs

On their first active frame, `FightManager._resolve_throws` grabs a throwable opponent
in range. Valka becomes a held throw that deals the move's damage, and the defender
can't tech. Grabs can't catch opponents in blockstun, in the air or knocked down.

## Game plan

Walk forward behind a solid guard; once the opponent respects her strikes, Valkyrie
Slam them as they come out of blockstun. Spinning Lariat answers fireballs and jump-ins.

## Presentation

- Victory: double-biceps flex, or the fist pump.
- Voice: "Female Hurt Grunts & Groans" by AuraVoice, other takes pitched to 0.86.
- Character select routine: walks in, Spinning Lariat, reaches for the grab, Knee Lift
  into Shoulder Tackle, flex.

## CPU style: Grappler

Walks the opponent down to about 0.8 m, command-grabs when close and right after
blockstun, lariats through fireballs and jump-ins, and super-grabs on punishes.

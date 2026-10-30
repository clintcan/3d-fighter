# Aelia: The Knight

The eighth fighter, added after v0.9.1, and the first built from an imported model.

An armoured knight who fights without her sword. She walks forward behind gauntlet and
plate, and her heaviest moves carry super armour: a strike that lands while she winds up
hurts, but it doesn't stop her, and she hits back. The way to beat her is to throw her,
go through the armour with a second hit, or wait out her slow, punishable moves.

## Look

- Her own model: "Aelia Character Preview" by Abinady10 (Blend Swap 30219, CC-BY,
  credited in `assets/CREDITS.md` and the in-game credits).
- Short spiky red hair with a white headband, green plate armour with gold trim over chain
  mail, a plate skirt, armoured boots with spurs, a bandaged thigh.
- The armour is satin painted metal (`tools/build_aelia.gd` `LOOKS`; the original glossy
  colours read as plastic).
- Alternate costume (mirror matches): crimson plate, pale blonde hair
  (`CharacterData.alt_material_colors`).

## Stats

| HP | Walk | Dash | Throw | Damage |
|---|---|---|---|---|
| 1050 | 1.7 | 5.0 | 140 | ×1.05 |

Base moves are one frame slower (the jabs stay at 4), with ×1.1 knockback.

## Moves

| Input | Move | What it does |
|---|---|---|
| 6HP | Gauntlet Drive | Armoured straight with a step (14 startup). Big push: splats near a wall. |
| 6LK | Spur Rake | Quick low kick with the spurs. Cancels into Shield Rush. |
| 236P | Shield Rush | Armoured shoulder charge (14 startup, travels 6 m/s). −15 on block. |
| 623P | Rising Gauntlet | Rising uppercut that launches. Armoured, not invincible: beats a single meaty hit, loses to a throw or a second hit. |
| 214P | Hammerfall | Slow two-fisted overhead with a shockwave. Armoured, knocks down. |
| 236236P | Emerald Oath (super) | Five gauntlet punches while advancing, then the Hammerfall with a shockwave. |

Plus the shared base moves (jab, straight, kicks, crouching moves, jump attacks, throw).

## Super armour

Her signature mechanic, `MoveData.armor_hits`:

- In `Fighter.receive_hit`, a strike (body hit or projectile) that lands during an
  armoured move's startup frames, while `armor_used < armor_hits`, is absorbed:
  she takes its damage, but gets no hitstun, knockback or combo, and the move carries on.
  The result is `HitResult.ARMORED` (an emerald flash, a metal clank, "ARMOR" on the HUD;
  meter as for a block).
- Throws resolve before hits, so they go through. Supers break armour. Each armoured move
  absorbs one strike, so the second hit of a multi-hit move lands.
- `armor_used` is in `Fighter.SIM_FIELDS` (rollback, replays).

## Balance

The balance sim (24 Hard CPU matches per pairing, dojo) has her at 53% overall: she beats
the fighters who poke with single strikes (Jin 75%, Lian 96%), loses to rushdown and
pressure that throws or hits twice (Rhea 23%, Mira 25%, Kenji 31%), and is even with the
heavies (Brutus 65%, Valka 58%). Armour through the active frames as well made her 72%;
it now covers the startup only, with Shield Rush 90 damage / 24 recovery and Rising
Gauntlet +22 landing frames. (Lian's 4% here isn't Aelia's doing: v0.9.1 has Lian at
6-16% against everyone in the same sim.)

## Animations

- `fight/intro_oath`: right fist to the heart and a bow of the head, then the guard.
- `fight/victory_oath`: the oath held with the chin up (also her portrait pose: her short
  forearms put the guard's glove in front of her eyes).
- Everything else is the shared clips: her model is on the game skeleton.

## CPU: Knight

Prefers about 1.4 m. Walks forward, charges with Shield Rush, uses Hammerfall up close and
Gauntlet Drive at mid range. Against a single strike it sees in time, it sometimes answers
with an armoured move instead of blocking (`AIController._try_armor`, `armor` 0.35; never
against a multi-hit move, a super or a grab). Every CPU throws an armoured move up close
instead of striking into it.

## The imported model

How a model that isn't the Quaternius base becomes a fighter:

1. `tools/build_aelia.gd -- --dump-rest <file>` writes the game skeleton's rest joints.
2. `tools/aelia_blender.py` (Blender 5, scripts in the .blend disabled), run on the original
   file kept in `tools/aelia/aelia_source.blend` (LFS; `.gdignore` so Godot never imports
   it), clears her rig's
   constraints and turns her arms, legs and fingers from her A-pose into the game's
   T-pose (each segment aimed at the game bone's direction, the palms twisted to match);
   the upright torso, shoulders and head stay as modelled. It bakes the pose, merges her
   weights into the game's bone names, decimates the rivets, hair and armour (107k → 40k
   triangles), splits off the eyes and exports glTF to `assets/characters/aelia/source/`.
3. `tools/build_aelia.gd` builds `aelia.scn`: a copy of the game skeleton with every rest
   rotation unchanged and the joints moved to hers, new skin binds, and the material
   looks. The animations set rotations (and the pelvis position), not bone lengths, so
   every clip plays on her proportions.

Her own head has no expression shapes, so her face stays as made (no expressions, gaze
or voice-driven mouth). Her voice is Rhea's takes pitched to 0.9.

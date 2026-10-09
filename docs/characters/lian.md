# Lian: The Counter Master

The seventh fighter, added after v0.7.0.

A Wing Chun master. She keeps to the centre line, rattles off chain punches and palm
strikes at close range, and waits for the opponent to commit: a careless strike gets
caught and turned into a throw. The style's founding legend is a woman, Yim Wing-chun,
and its ideas (economy of motion, sticking to and redirecting an attack) suit a counter
fighter.

## Look

- Female base body, the light skin texture.
- Black hair pulled back sleek into a bun, with a red lacquered hairpin (`Hair_Bun`, cut
  from `Hair_Long` by `tools/build_hair.gd`, bun and pin generated on the Head bone).
- Jade short-sleeved kung fu jacket with a standing collar and a cream placket, hem and
  cuffs; loose black pants; black cloth shoes with pale soles.
- Alternate costume (mirror matches): cream jacket with black trim, deep red pants.

## Stats

| HP | Walk | Dash | Throw | Damage |
|---|---|---|---|---|
| 980 | 2.0 | 6.2 | 115 | ×1.0 |

## Moves

| Input | Move | What it does |
|---|---|---|
| 6LP | Chain Punch | Three quick straight punches down the centre line (14 each). Chains into the straight or Double Palm. |
| 6HP | Double Palm | Two-handed palm strike with a step in. Big pushback. |
| 214P | Still Water | Reversal stance (3 frames to start, catches for 14). A high, mid or overhead strike that touches her (jump-ins included) is caught, and she throws the attacker for 120: unblockable, can't be teched. Lows, throws and fireballs beat it, and a stance that catches nothing is very punishable. |
| 214K | Willow Step | Glides forward in the stance, through fireballs. No hitbox. |
| 236P | Inch Palm | Short-range power palm. Knocks down; punishable on block. |
| 236236P | Thousand Hands (super) | Ten chain punches while advancing, ending in an Inch Palm with a shockwave. |

Plus the shared base moves (jab, straight, kicks, crouching moves, jump attacks, throw).

## Reversal

Her signature mechanic, `MoveData.reversal`:

- `FightManager._resolve_hits` checks a connecting body hitbox against the defender's
  `Fighter.reverses(move)`: a reversal move in its active frames catches anything but a
  low. The strike never lands; the defender performs a command grab on the attacker
  (`on_command_grab` / `on_grabbed_by(..., false)`), with the stance's damage. The throw
  plays `fight/reversal_throw` (trap, draw past, palm).
- Projectiles never reach the check, and a throw beats the stance because it resolves
  before hits.
- It needs no new simulation state, so rollback and replays need nothing extra.
- `FightManager.reversal_landed` drives the effects (a jade flash and ring, a clap) and
  the HUD calls out REVERSAL.

## CPU style: Counter

Keeps about 1.3 m away, waits a lot, and uses Still Water:

- against attacks it sees early enough. It sees them with its general reaction delay,
  not the faster blocking one, so only slow attacks can be reversed on sight;
- against jump-ins, while the jumper comes down;
- now and then as a read up close.

Willow Step takes it through fireballs. Every CPU respects a reversal: it never strikes
into a stance it sees (it throws, goes low or waits), and against a fighter with one it
favours lows and throws.

## Balance notes

Balance simulator (`tools/balance_sim.gd -- 10 2 lian`, Hard, 20 matches per pairing):

- **First version:** 61% overall. Her CPU reversed on the 4-frame blocking reaction and
  caught nearly every slow attack (Brutus won 10%).
- **Tuning:** catch window 18 → 14 frames, recovery 16 → 20, throw damage 140 → 120.
  Reversals now use the general reaction delay, and other CPUs are wary of the stance.
- **Result:** about 41–42% overall. She beats Brutus and Mira and loses to Jin, Rhea and
  Valka, whose long kicks, speed and grabs are what a counter fighter struggles with. The
  runs are noisy (about ±11% per pairing).

A fix found along the way: specials whose motion starts with 2 (236, 214) used to set the
crouching hurtbox, so highs whiffed over every fireball and charge startup. Only crouching
normals crouch now.

## Presentation

- Victory: the fist-in-palm salute and bow, or the fist pump.
- Voice: Valka's takes from the "Female Hurt Grunts & Groans" recording (AuraVoice),
  pitched up about 10%.
- Character select routine: Chain Punch → Double Palm → Still Water and the reversal throw
  → Inch Palm → the super → salute.

## Originality

Lian is an original character. Her name, look, move names and the reversal mechanic are
our own.

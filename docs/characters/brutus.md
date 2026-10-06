# Brutus: The Power Fighter

A brawler built like a wall. Slow to move and slow to start, but every hit lands hard,
he takes the most punishment, and one read can turn a round.

## Look

- Male base body, scaled up 8%, buzz cut and a full beard.
- Olive tank top, denim work pants, leather boots.
- Alternate costume (mirror matches): grey top, lighter denim, brown boots, grey hair.

## Stats

| HP | Walk | Dash | Throw | Damage | Startup |
|---|---|---|---|---|---|
| 1100 | 1.5 | 4.5 | 160 | ×1.25 | +2 frames |

Knockback ×1.25 and hitstop +2, so his hits feel heavy; weight 1.3, so he barely moves
when hit.

## Moves

| Input | Move | What it does |
|---|---|---|
| 6HP | Overhead Smash | Slow (20f) overhead that knocks down. Must be blocked standing. |
| 6HK | Heavy Boot | Front kick with huge pushback. |
| 236P | Bull Charge | Shoulder charge across the ring at 8 m/s until it connects. Huge pushback. |
| 214P | Earthquake | Double-fist ground pound: a shockwave along the floor that hits low and knocks down. |
| 236236P | Titan Rush (super) | Four-hit charge into an overhead slam. |

Plus the shared base moves (see the [roster overview](README.md)).

## Game plan

Wait for a mistake, then make it hurt: Bull Charge punishes whiffs from across the
ring, Earthquake and Overhead Smash make a crouching or standing guard wrong.

## Presentation

- Victory: double-biceps flex, or the fist pump.
- Voice: "Male Grunt/Yelling sounds" by HaelDB, voice 3, pitched down to 0.9.
- Character select routine: waits with folded arms, then Earthquake with its shockwave
  ring, Bull Charge, Overhead Smash and a flex.

## CPU style: Punisher

Prefers 1.6 m, −0.2 aggression, +0.15 block and +0.2 punish chance; waits a lot, uses
Earthquake up close and punishes whiffs from range with Bull Charge (far punish 0.85).

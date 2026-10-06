# Jin: The Kicker

A Tae Kwon Do black belt. He controls the space at kick range with long legs and a
patient game, and punishes anyone who steps in carelessly.

## Look

- Male base body, scaled up 2%, darker skin (`assets/characters/jin/T_Jin_Body.png`),
  black buzz cut.
- White V-neck dobok with the black collar and belt of a black belt.
- Alternate costume (mirror matches): black dobok with a red collar, brown hair.

## Stats

| HP | Walk | Dash | Throw | Damage | Startup |
|---|---|---|---|---|---|
| 980 | 2.2 | 6.5 | 110 | ×0.95 | ±0 |

Knockback ×1.05. His base moves reach 12% further (`reach` 1.12 scales their hitboxes).

## Moves

| Input | Move | What it does |
|---|---|---|
| 6HK | Axe Kick | Overhead from kick range (16f). Must be blocked standing. |
| 6LK | Push Kick | Lunging front kick with big pushback. |
| 236K | Spinning Back Kick | Steps in as he turns; hits from about 2.2 m. Slightly unsafe. |
| 623K | Tornado Kick | Invincible rising spin kick (frames 1–6), two hits, launches. |
| 236236K | Hurricane Kicks (super) | Seven rapid kicks into an Axe Kick finisher that knocks down. |

Plus the shared base moves (see the [roster overview](README.md)).

## Game plan

Footsies: sit just outside the opponent's range, poke with long kicks, whiff-punish
with Spinning Back Kick, and break a crouching guard with the Axe Kick.

## Presentation

- Victory: the point, or the fist pump.
- Voice: "Male Grunt/Yelling sounds" by HaelDB, voice 2.
- Character select routine: Push Kick → Spinning Back Kick → Axe Kick → Tornado Kick →
  point.

## CPU style: Footsies

Prefers 1.9 m, pokes a lot, punishes whiffs from beyond normal reach (far punish 0.6)
and prefers the invincible Tornado Kick as an anti-air.

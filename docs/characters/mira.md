# Mira Santos: The Brawler

The sixth fighter, added after v0.5.1.

A Manila street fighter who mixes boxing with Sikaran, the Filipino kicking art. She wins
with fast punch strings, a flip kick and a dive kick, and she gets stronger the longer
the opponent lets her power up.

## Look

- Female base body, warm medium-brown skin (`assets/characters/mira/T_Mira_Body.png`).
- Dark brown A-line bob, chin length at the front (`Hair_Bob`, cut from `Hair_Long` by
  `tools/build_hair.gd`).
- Charcoal sleeveless zip-up with a mustard zip and hem band.
- Black track pants with mustard stripes down the outside of each leg.
- Black fingerless gloves and white leather sneakers.
- Alternate costume (mirror matches): white top with red trim and stripes, dark grey
  pants, red sneakers.

## Stats

| HP | Walk | Dash | Throw | Damage |
|---|---|---|---|---|
| 950 | 2.3 | 7.0 | 115 | ×0.95 |

## Moves

| Input | Move | What it does |
|---|---|---|
| 6LP | Tapik | Quick backfist that chains into itself (like the jab). |
| 6HK | Sipa Flip | Somersault flip kick. Launches. |
| j.2K | Lawin Drop | Steep dive kick from a jump. Overhead; extra landing lag if it misses. |
| 236P | Bagyo Rush | Travelling punch flurry, 3 hits. Each Focus level adds a hit and 15% damage. |
| 623K | Lawin Rise | Rising flip kick with an invincible start. Launches. Each Focus level adds height and 15% damage. |
| 214P | Lakas Stance | 33-frame power-up, punishable if she misses it. Raises Focus by 1 (max 3). |
| 236236P | Huling Hagupit (super) | 8-hit rush into a palm-strike knockdown. At Focus 3 the finisher becomes a shockwave strike with about 30% more damage. |

Plus the shared base moves (jab, straight, kicks, crouching moves, jump attacks, throw)
with her tuning.

## Focus

Her signature mechanic, shown as three pips next to her SUPER meter.

- Lakas Stance raises Focus by one level, up to 3.
- A normal that connects can cancel into Lakas Stance, so she can power up inside combos.
- Each level strengthens Bagyo Rush and Lawin Rise. At level 3 the super ends in the
  shockwave finisher.
- Focus resets when she's knocked down or K.O.'d, and the super uses it up. Opponents
  are pushed to knock her down before she reaches level 3.
- Focus is simulation state (`Fighter.focus`, in `SIM_FIELDS`), so rollback and replays
  stay exact.

## Presentation

- Victory: fist pump or the point.
- Voice: the "Female Hurt Grunts & Groans" recording (AuraVoice), other takes pitched to 1.07.
- Character select routine: Tapik ×3 → Sipa Flip → Lakas Stance ×3 → Bagyo Rush → the
  super at full Focus → fist pump.

## CPU style: Brawler

Keeps about 1 m from the opponent, uses Lakas Stance at range and while the opponent is
knocked down, and spends level 3 on the super.

## Detailed textures

Mira was the first fighter with the higher-detail materials (`CharacterData.detailed_textures`);
every fighter has them now.

- The fabric weave textures the cloth colour, not just its surface.
- 2K fabric normal and roughness maps (CC0, Poly Haven), VRAM-compressed with mipmaps.
- The cloth darkens a little toward every hem and opening, with a stitch line along
  each hem.
- A tiling skin pore normal map, visible in close-ups.

The frame rate is checked before and after on the integrated GPU (target: about 70 FPS
at 720p).

## Originality

Mira was designed as an original character in the same archetype as other martial-arts
brawlers. Her name, look, move names and the Focus mechanic are our own.

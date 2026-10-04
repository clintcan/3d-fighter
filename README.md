# 3D Fighter

[![tests](https://github.com/clintcan/3d-fighter/actions/workflows/tests.yml/badge.svg)](https://github.com/clintcan/3d-fighter/actions/workflows/tests.yml)

A one-on-one 3D fighting game inspired by Street Fighter and Tekken, built in **Godot 4**.
Its signature is a **dynamic action camera** that orbits and dollies in on every big hit.

![3D Fighter key art](assets/ui/splash.png)

## Features

- **5 fighters**, each with normals, motion-input specials, a super and a distinct CPU personality:
  - **Kenji**: zoner;
  - **Rhea**: rushdown;
  - **Brutus**: punisher;
  - **Valka**: grappler with an unblockable command grab;
  - **Jin**: Tae Kwon Do kicker who controls kick range.
- **5 stages**: Boxing Ring, Dojo, Rooftop, Temple, Beach. Each has its own music.
- **Modes**: Vs CPU, Arcade (ladder, scoring, shadow boss), local 2-player Versus, **Online** (rollback netcode, LAN discovery or join by IP), and Training (frame data, input display, record/playback).
- **Fighting-game systems**: super meter with cinematic super freezes, counter hits, combos, juggles, throws and throw breaks, high/mid/low blocking, and Tekken-style sidesteps.
- **Engine**: a deterministic 60 Hz simulation (verified identical on Windows and Linux) with a headless regression test suite.

## Screenshots

| | |
|---|---|
| ![Jin's Tornado Kick on the beach](docs/screenshots/beach.jpg) | ![Jin's Hurricane Kicks super](docs/screenshots/jin_super.jpg) |
| ![Temple stage](docs/screenshots/temple.jpg) | ![Super flash](docs/screenshots/super.jpg) |
| ![Earthquake in the dojo](docs/screenshots/dojo.jpg) | ![Ki Blast on the rooftop](docs/screenshots/rooftop.jpg) |
| ![Character select](docs/screenshots/character_select.jpg) | ![Stage select](docs/screenshots/stage_select.jpg) |

## Controls

| | Keyboard (P1) | Gamepad |
|---|---|---|
| Move / jump / crouch | W A S D | Left stick / D-pad |
| Light / Heavy Punch | U / I | X / Y |
| Light / Heavy Kick | J / K | A / B |
| Sidestep | L | RB |
| Pause & move list | Esc | Start |

- **Specials** use motion inputs (for example ↓↘→ + P), and a full super meter enables ↓↘→↓↘→ + P/K. Each fighter's moves are listed in the pause menu.
- **Player 2** uses the arrow keys with numpad 4/5 (punches), 1/2 (kicks) and 6 (sidestep), or a second gamepad.
- **Online:** one player hosts; on the same network the other picks the game from the list, or joins by address (UDP port 7777; forward it on the host's router to play over the internet). Both players need the same build. Connections are encrypted, and both screens show a 6-digit security code to compare.
- **Remapping:** every key and gamepad button can be changed per player in **Options → Controls**, which shows a controller diagram. The triggers can be bound too.

## Run from source

Requires **Godot 4.7** with a Vulkan-capable GPU.

```bash
godot -e --path .   # open in the editor
godot --path .      # run the game
```

## Tests

```bash
godot_console --headless --path . -s res://tests/sim_test.gd   # exit code 1 on failure
```

## Build releases

This needs the Godot 4.7.2 export templates for Windows, macOS and Linux, plus Python 3.

```bash
python tools/build_release.py all                     # Windows + macOS + Linux -> dist/
python tools/build_release.py windows linux           # any subset
python tools/build_release.py all --test              # run the tests first, stop on failure
python tools/build_release.py all --version 0.3.0 --test --notarize   # full release
```

The script produces three archives:

| Output | Contents |
|---|---|
| `dist/3DFighter-v<ver>-windows.zip` | Single exe plus README; smoke-tested |
| `dist/3DFighter-v<ver>-macos.zip` | Universal `.app`, signed with Developer ID; `--notarize` notarizes and staples it |
| `dist/3DFighter-v<ver>-linux.tar.gz` | x86_64 binary plus README; smoke-tested in WSL when available |

Mac signing reads its credentials from `%USERPROFILE%\AppleDeveloper`, which stays outside the repo. Use `--no-sign` for a local unsigned build.

## Project layout

```
scripts/   gameplay (fighter, AI, camera, FX, UI, arcade, training)
scenes/    menus, fight scene, generated stages
data/      characters and moves (generated; edit tools/build_movesets.gd)
tools/     generators (stages, animations, movesets, key art) and build_release.py
tests/     headless simulation tests
```


## Credits

All third-party assets are CC0, credited in [assets/CREDITS.md](assets/CREDITS.md):

- **Characters and animations:** [Quaternius](https://quaternius.com).
- **Skies and textures:** [Poly Haven](https://polyhaven.com).
- **Sounds and announcer:** [Kenney](https://kenney.nl).
- **Music and voices:** [OpenGameArt](https://opengameart.org) artists.

Made with [Godot Engine](https://godotengine.org).

## License

© 2026 Clint Christopher Canada.

- **Code:** [MIT License](LICENSE).
- **Original assets** (stages, generated animations, portraits, key art, synthesized sounds): [CC BY 4.0](LICENSE-ASSETS.md).
- **Third-party assets:** keep their own licenses (all CC0); see [assets/CREDITS.md](assets/CREDITS.md).

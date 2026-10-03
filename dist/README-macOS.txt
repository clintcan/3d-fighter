3D FIGHTER  -  v0.2.0 (prototype)  -  macOS
===========================================

A one-on-one 3D fighting game inspired by Street Fighter and Tekken, with a
dynamic action camera that moves in on the fighter taking the hits.

HOW TO PLAY
-----------
1. Unzip, and (optionally) drag 3DFighter.app into your Applications folder.
2. Double-click to play. The app is signed and notarized by Apple, so it opens
   like any other app (macOS may ask once to confirm it was downloaded from
   the internet; click "Open").

Requirements: macOS 11 Big Sur or newer, Apple Silicon (M1 or later) or an
Intel Mac with Metal-capable graphics. Runs natively on both.

CONTROLS            Keyboard          Gamepad
--------            --------          -------
Move / jump / crouch  W A S D         Left stick / D-pad
Light Punch           U               X
Heavy Punch           I               Y
Light Kick            J               A
Heavy Kick            K               B
Sidestep              L               RB
Pause / move list     Esc             Start

VERSUS (2 PLAYERS) - choose "Versus" in the main menu
Player 2 keyboard: Arrows move, Numpad 4 / 5 punch, Numpad 1 / 2 kick,
Numpad 6 sidestep (no numpad: [ ] punch, ; ' kick, / sidestep).
Gamepad 1 is Player 1 and Gamepad 2 is Player 2 (swap in Options).
On the character select screen each player picks in turn with
Light Punch (select) and Heavy Punch (back).

STAGES: after picking fighters, choose the Boxing Ring, the Dojo, the Rooftop
or Random.

ARCADE - choose "Arcade" in the main menu
Fight your way up a ladder of CPU opponents to the final boss: your own
shadow, who starts every round with a full super meter. Score points for
damage, time left, health left and perfect rounds; lose and you can
continue (the stage restarts). Clear it to see your results, your best
score for that fighter, and the credits.

TRAINING - choose "Training" in the main menu
Pick your fighter, then the training dummy. Endless health, no timer.
Tab (gamepad Back): training menu - dummy stance (stand / crouch / jump /
  CPU / playback), guard (none / block all / after first hit / random),
  health refill, frame data, input history, hitboxes.
Backspace (gamepad L3): reset positions.
F6: record the dummy - you control it for up to 10 seconds; F6 again to stop.
F7: play the recording back on a loop (on / off).
Frame data shows each attack's startup, active and recovery frames and
the measured frame advantage on hit or block.

Block: hold back (standing) or down-back (crouching).
Dash: tap forward twice. Backdash: tap back twice.
Throw: Light Punch + Light Kick together, up close.
Signature moves: forward + Heavy Punch (and see the move list in the pause menu).

SPECIAL MOVES (P = either punch, K = either kick; written facing right)
  Kenji   down, down-forward, forward + P ... Ki Blast (fireball)
          forward, down, down-forward + P ... Rising Dragon (invincible uppercut)
  Rhea    down, down-forward, forward + K ... Gale Slide (low slide)
          forward, down, down-forward + K ... Crescent Rise (rising kick)
  Brutus  down, down-forward, forward + P ... Bull Charge
          down, down-back, back + P ......... Earthquake (low ground pound)
Normal attacks that connect can be cancelled into a special.

SUPER: landing and taking hits fills the SUPER meter (bottom corners).
When it's full, do down, down-forward, forward twice + P (Kenji, Brutus)
or + K (Rhea) for the character's super. Sidestep dodges fireballs.

Options (main menu): music / effects / announcer volume, action camera
(Off / Subtle / Full), CPU difficulty (Easy / Normal / Hard), fullscreen.
On older Intel Macs, setting the Action Camera to "Subtle" can help performance.

CREDITS
-------
Made with Godot Engine (MIT License) - https://godotengine.org

All third-party assets are CC0 (public domain), credited with thanks:
- Characters & animations: Quaternius - Universal Base Characters,
  Universal Animation Library 1 & 2 - https://quaternius.com
- Stage lighting & textures: Poly Haven - "Basement Boxing Ring" HDRI by
  Sergej Majboroda; Terlenka, Fabric Leather 02, Concrete Floor Worn 001
  - https://polyhaven.com; Dojo: Tatami Mat, Hinoki Planks, Japanese Cedar
  Planks (Charlotte Baglioni, Rico Cilliers), Dark Wood (Dario Barresi,
  Dimitrios Savva, Rico Cilliers), White Plaster 02 (Rob Tuytel);
  Rooftop skyline: "Shanghai Bund" HDRI by Greg Zaal
- Music: "Heavy Battle 2" and "Space Battle" by MintoDog; "Determination" by
  HydroGene (dojo); "Midnight Drive" by congusbongus (rooftop)
  - https://opengameart.org
- Fighter voices: "Male Grunt/Yelling sounds" by HaelDB, "Female Hurt Grunts &
  Groans" by AuraVoice - https://opengameart.org
- Sound effects & announcer: Kenney - Impact Sounds, Interface Sounds,
  Voiceover Pack: Fighter - https://kenney.nl

Ring, arena, crowd, additional fight animations, portraits and swing sounds
were created for this project.

3D FIGHTER  -  v0.3.1 (prototype)
=================================

A one-on-one 3D fighting game inspired by Street Fighter and Tekken, with a
dynamic action camera that moves in on the fighter taking the hits.

HOW TO PLAY
-----------
Unzip anywhere and run 3DFighter.exe. No installation needed.
(Windows may show a SmartScreen warning for unsigned indie games:
 click "More info" -> "Run anyway".)

Requirements: Windows 10/11 64-bit, a GPU with Vulkan support.

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

STAGES: after picking fighters, choose the Boxing Ring, the Dojo, the Rooftop,
the Temple, the Beach or Random.

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
  Valka   forward, half-circle to back + P .. Valkyrie Slam (command grab:
                                              unblockable, can't be broken)
          forward, down, down-forward + P ... Spinning Lariat (through fireballs)
  Jin     down, down-forward, forward + K ... Spinning Back Kick
          forward, down, down-forward + K ... Tornado Kick (invincible anti-air)
          forward + Heavy Kick .............. Axe Kick (overhead)
Normal attacks that connect can be cancelled into a special.

SUPER: landing and taking hits fills the SUPER meter (bottom corners).
When it's full, do down, down-forward, forward twice + P (Kenji, Brutus)
or + K (Rhea, Jin) for the character's super. Valka's super is a command grab. Sidestep dodges fireballs.

Remap any key or gamepad button (triggers too) in Options -> Controls.

Options (main menu): music / effects / announcer volume, action camera
(Off / Subtle / Full), CPU difficulty (Easy / Normal / Hard), fullscreen.

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
  Rooftop skyline: "Shanghai Bund" HDRI by Greg Zaal; Temple: "Belfast Sunset"
  sky (Greg Zaal, Dimitrios Savva, Jarod Guest), Monastery Stone Floor (Amal
  Kumar), Japanese Stone Wall, Gravel Floor 03, Grey Roof Tiles; Beach:
  "Kloofendal 48d Partly Cloudy" sky (Greg Zaal, Jarod Guest), Coast Sand
  01, Thatch Roof Angled (Rob Tuytel, Dimitrios Savva), Palm Tree Bark
  (Dimitrios Savva, Rico Cilliers), Bamboo Wall (Amal Kumar)
- Music: "Heavy Battle 2" and "Space Battle" by MintoDog; "Determination" by
  HydroGene (dojo); "Midnight Drive" by congusbongus (rooftop); "Boss_Koto"
  by G_P (temple); "Funky House" by Of Far Different Nature (beach)
  - https://opengameart.org
- Fighter voices: "Male Grunt/Yelling sounds" by HaelDB, "Female Hurt Grunts &
  Groans" by AuraVoice - https://opengameart.org
- Sound effects & announcer: Kenney - Impact Sounds, Interface Sounds,
  Voiceover Pack: Fighter - https://kenney.nl

Stages, crowds, additional fight and special-move animations, portraits,
key art and synthesized sounds were created for this project.

LICENSE: code (c) 2026 Clint Christopher Canada, MIT License. Original
assets (c) 2026 Clint Christopher Canada, CC BY 4.0
(https://creativecommons.org/licenses/by/4.0/). Third-party assets: CC0.

3D FIGHTER  -  v0.6.0 (prototype)
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
the Temple, the Beach, the Night Market or Random.

ARCADE - choose "Arcade" in the main menu
Fight your way up a ladder of CPU opponents to the final boss: your own
shadow, who starts every round with a full super meter. Score points for
damage, time left, health left and perfect rounds; lose and you can
continue (the stage restarts). Clear it to see your results, your best
score for that fighter, and the credits.

ONLINE - choose "Online" in the main menu
One player chooses Host Game. On the same network the other player sees
the game under "Games on your network" and picks it; otherwise they type
the host's address and choose Join. The host is asked to accept each
player who tries to join. Both pick a fighter, the host picks the stage, and you fight
with rollback netcode (the game hides network lag by predicting your
opponent's input and correcting it instantly when it arrives).
- Same network: the host's address is shown on the Host screen
  (e.g. 192.168.1.20).
- Over the internet, the easy way: Online -> Internet Lobby. Press Connect
  (the server address is filled in), then Open a Room, or pick a room from
  the list, or type a friend's 6-letter room code. No port forwarding: the
  game connects you directly when it can and through the server's relay
  when it can't. Tick "Hide my IP address" to always use the relay.
  Rooms that allow spectators have a Watch button: spectators see the match
  live with a 3-second delay and can send reactions with keys 1-6.
- Over the internet without the lobby: the host forwards UDP port 7777 on
  their router and shares their public IP address.
- Allow the game through your firewall if asked.
- Both players need the same version of the game.
- The connection is encrypted. Both screens show a 6-digit security code
  (character select, and in the leave prompt): if the codes match, nobody
  is listening in; if they differ, leave the match.
- Esc during an online match asks before leaving (an online match can't
  pause). The bar at the bottom shows ping, rollback and connection quality.

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
  Mira    down, down-forward, forward + P ... Bagyo Rush (punch flurry)
          forward, down, down-forward + K ... Lawin Rise (rising flip kick)
          down, down-back, back + P ......... Lakas Stance (+1 Focus)
          down + K in the air ............... Lawin Drop (dive kick)
Normal attacks that connect can be cancelled into a special.

FOCUS (Mira): each Lakas Stance adds a Focus level, up to 3 (the pips by
her SUPER meter). Every level makes Bagyo Rush and Lawin Rise stronger, and
at level 3 her super ends in a shockwave strike. She loses it all when
she's knocked down.

SUPER: landing and taking hits fills the SUPER meter (bottom corners).
When it's full, do down, down-forward, forward twice + P (Kenji, Brutus, Mira)
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
  (Dimitrios Savva, Rico Cilliers), Bamboo Wall (Amal Kumar); Night Market:
  "Qwantani Dusk 2" sky (Greg Zaal, Jarod Guest), Asphalt 02 (Rob Tuytel),
  Brick Pavement and Rusty Corrugated Iron (Charlotte Baglioni), Painted
  Plaster Wall and Wood Planks (Amal Kumar), Painted Metal Shutter (Dario
  Barresi, Rico Cilliers, Charlotte Baglioni); outfit fabrics:
  Cotton Jersey and Bi Stretch (colormass, Rico Cilliers), Denim Fabric 06
  (Greg Zaal, Rico Cilliers)
- Music: "Heavy Battle 2", "Space Battle" and "Jazzy Battle Theme" (night
  market) by MintoDog; "Determination" by HydroGene (dojo); "Midnight
  Drive" by congusbongus (rooftop); "Boss_Koto" by G_P (temple); "Funky
  House" by Of Far Different Nature (beach)
  - https://opengameart.org
- Fighter voices: "Male Grunt/Yelling sounds" by HaelDB, "Female Hurt Grunts &
  Groans" by AuraVoice - https://opengameart.org
- Sound effects & announcer: Kenney - Impact Sounds, Interface Sounds,
  Voiceover Pack: Fighter - https://kenney.nl
- Ambient sound: "AMB Rain Loop 1" by kresiek-the-furry, "High traffic road
  sounds" by ignasd, "Background voices" by pauliuw, "Crowd Shouting/Speaking
  Ambience" by starninjas, "Applause in a large hall or church" by expl0it3r,
  "Beach Ocean Waves" by qubodup (recorded by jasinski), "Park ambiences" by
  thimras, "Fire Crackling" by antumdeluge, "Solo Seagull Sound Effects" by
  rango-mango - https://opengameart.org

Stages (including the jeepneys), crowds, fighter outfits, additional fight
and special-move animations, portraits, key art and logo, and synthesized
sounds were created for this project. The logo is lettered with the
"Permanent Marker" font by Font Diner (Apache 2.0).

LICENSE: code (c) 2026 Clint Christopher Canada, MIT License. Original
assets (c) 2026 Clint Christopher Canada, CC BY 4.0
(https://creativecommons.org/licenses/by/4.0/). Third-party assets: CC0.

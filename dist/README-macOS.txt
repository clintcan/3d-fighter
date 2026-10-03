3D FIGHTER  -  v0.1.0 (prototype)  -  macOS
===========================================

A one-on-one 3D fighting game inspired by Street Fighter and Tekken, with a
dynamic action camera that moves in on the fighter taking the hits.

HOW TO PLAY
-----------
1. Unzip, and (optionally) drag 3DFighter.app into your Applications folder.
2. The first time you open it, macOS will warn that it can't verify the app.
   It isn't notarized by Apple (that needs a paid Apple Developer account),
   but it is safe. To open it:

   macOS 15 Sequoia and newer:
     - Double-click 3DFighter.app, then click "Done" on the warning.
     - Open System Settings > Privacy & Security, scroll down, and click
       "Open Anyway" next to the 3DFighter message. Confirm with your password.

   macOS 14 Sonoma and older:
     - Right-click (or Control-click) 3DFighter.app, choose "Open",
       then click "Open" in the dialog.

   You only need to do this once.

   If macOS says the app "is damaged and can't be opened", open Terminal and
   run (adjust the path if you didn't move it to Applications):

     xattr -cr /Applications/3DFighter.app

   then open it again.

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

Block: hold back (standing) or down-back (crouching).
Dash: tap forward twice. Backdash: tap back twice.
Throw: Light Punch + Light Kick together, up close.
Signature moves: forward + Heavy Punch (and see the move list in the pause menu).

Options (main menu): music / effects / announcer volume, action camera
(Off / Subtle / Full), CPU difficulty (Easy / Normal / Hard), fullscreen.
On older Intel Macs, setting the Action Camera to "Subtle" can help performance.

CREDITS
-------
Made with Godot Engine (MIT License) - https://godotengine.org

All third-party assets are CC0 (public domain), credited with thanks:
- Characters & animations: Quaternius - Universal Base Characters,
  Universal Animation Library 1 & 2 - https://quaternius.com
- Arena lighting & textures: Poly Haven - "Basement Boxing Ring" HDRI by
  Sergej Majboroda; Terlenka, Fabric Leather 02, Concrete Floor Worn 001
  - https://polyhaven.com
- Music: "Heavy Battle 2" and "Space Battle" by MintoDog - https://opengameart.org
- Sound effects & announcer: Kenney - Impact Sounds, Interface Sounds,
  Voiceover Pack: Fighter - https://kenney.nl

Ring, arena, crowd, additional fight animations, portraits and swing sounds
were created for this project.

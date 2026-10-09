"""Loudness envelopes of the fighter voice clips, for the voice-driven mouth.

FighterModel.speak() opens a fighter's jaw with the loudness of the shout that is
playing. Godot can't read the samples of an Ogg Vorbis stream, so this script decodes
every clip in assets/audio/voice/fighters/ with ffmpeg and writes, per clip, its loudness
60 times a second (0-100, relative to the clip's loud part) to
assets/audio/voice/fighters/mouth.json, keyed by file name without the extension.

Needs ffmpeg on PATH and numpy. Re-run after adding or changing voice clips:
    python tools/build_voice_envelopes.py
"""

import json
import pathlib
import subprocess

import numpy as np

ROOT = pathlib.Path(__file__).resolve().parent.parent
VOICE_DIR = ROOT / "assets" / "audio" / "voice" / "fighters"
OUT = VOICE_DIR / "mouth.json"
RATE = 12000
FPS = 60
GATE = 0.12  # below this share of the loud level the mouth closes (breaths, room noise)
RELEASE = 0.75  # per frame: how much of the last value a falling envelope keeps


def envelope(path: pathlib.Path) -> list[int]:
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(path), "-ac", "1", "-ar", str(RATE), "-f", "f32le", "-"],
        check=True, capture_output=True).stdout
    samples = np.frombuffer(raw, dtype=np.float32)
    hop = RATE // FPS
    frames = len(samples) // hop + 1
    padded = np.zeros(frames * hop, dtype=np.float32)
    padded[:len(samples)] = samples
    rms = np.sqrt(np.mean(padded.reshape(frames, hop) ** 2, axis=1))
    loud = np.percentile(rms, 95)
    if loud <= 0.0:
        return [0] * frames
    level = np.clip(rms / loud, 0.0, 1.0)
    level = np.clip((level - GATE) / (1.0 - GATE), 0.0, 1.0) ** 0.7  # a little open at moderate levels
    out = []
    last = 0.0
    for value in level:
        last = max(value, last * RELEASE)  # opens at once, closes over a few frames
        out.append(int(round(last * 100)))
    return out


def main() -> None:
    envelopes = {}
    for clip in sorted(VOICE_DIR.glob("*.ogg")):
        envelopes[clip.stem] = envelope(clip)
        print(f"{clip.stem:20s} {len(envelopes[clip.stem]) / FPS:5.2f} s")
    OUT.write_text(json.dumps(envelopes, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"{len(envelopes)} clips -> {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Restore Zen's original intro melody, with a softer ending only.

The original score determines the normalization gain, preserving the opening
samples exactly. Only the last chord and final fade differ from that version.
"""
from array import array
from math import exp, pi, sin
from pathlib import Path
import random
import re
import sys
import wave

ROOT = Path(__file__).resolve().parents[1]
timing_source = (ROOT / "zen/Components/OnboardingIntroArtwork.swift").read_text()
timing = {name: float(value) for name, value in re.findall(r"static let (\w+) = ([0-9.]+)\s*$", timing_source, re.M)}
RATE = 48_000
DURATION = 5.0
HANDOFF = timing["handoff"]
ENDING = HANDOFF + timing["handoffFade"]
frames = int(RATE * DURATION)
left = [0.0] * frames
right = [0.0] * frames
random.seed(7)


def tone(start, frequency, duration, gain, pan=0.0, attack_duration=0.025, output=None):
    channels = (left, right) if output is None else output
    for offset in range(int(duration * RATE)):
        index = int(start * RATE) + offset
        if index >= frames:
            break
        time = offset / RATE
        attack = min(1, time / attack_duration)
        tail = max(0, 1 - time / duration) ** 2
        envelope = attack * tail * exp(-time * 1.6)
        phase = 2 * pi * frequency * time
        sample = gain * envelope * (sin(phase) + 0.18 * sin(phase * 2.004) + 0.06 * sin(phase * 3.01))
        channels[0][index] += sample * (1 - pan * 0.35)
        channels[1][index] += sample * (1 + pan * 0.35)


# Original pad, note sequence, attacks, levels, stereo positions, and breath.
for index in range(frames):
    time = index / RATE
    envelope = min(1, time / 0.65) * min(1, max(0, (DURATION - time) / 1.1))
    for frequency in [146.832, 220.0, 369.994]:
        left[index] += 0.016 * envelope * sin(2 * pi * frequency * time)
        right[index] += 0.016 * envelope * sin(2 * pi * frequency * 1.001 * time)

for start, notes, gain in [
    (0.08, [293.665], 0.12),
    (timing["expansion"], [440.0, 587.330], 0.10),
    (timing["logo"], [587.330, 739.989], 0.105),
    (timing["dissolve"], [880.0], 0.075),
]:
    for voice, frequency in enumerate(notes):
        tone(start, frequency, min(1.6, DURATION - start), gain, (-1 if voice % 2 else 1) * 0.45)

filtered = 0.0
for index in range(int(1.25 * RATE)):
    time = index / RATE
    filtered = filtered * 0.985 + random.uniform(-1, 1) * 0.015
    envelope = sin(pi * time / 1.25) ** 2
    sample = filtered * envelope * 0.13
    left[index] += sample
    right[index] += sample * 0.9

# Measure the unmodified original, including its old high ending, so changing
# the finish cannot renormalize the earlier melody to a different volume.
reference_left, reference_right = left[:], right[:]
for voice, frequency in enumerate([587.330, 880.0, 1174.659]):
    tone(HANDOFF, frequency, DURATION - HANDOFF, 0.085,
         (-1 if voice % 2 else 1) * 0.45, output=(reference_left, reference_right))
peak = max(max(abs(value) for value in reference_left), max(abs(value) for value in reference_right))
normalization = 0.58 / max(peak, 0.001)

# Preserve the bell timbre but resolve an octave lower, more quietly, after the
# panel's fade. A slower attack keeps the last chord from punctuating the UI.
for voice, frequency in enumerate([293.665, 440.0, 587.330]):
    tone(ENDING, frequency, DURATION - ENDING, 0.045,
         (-1 if voice % 2 else 1) * 0.45, attack_duration=0.065)

for index in range(round(4.55 * RATE), frames):
    progress = min(1, max(0, (index / RATE - 4.55) / (DURATION - 4.55)))
    fade = 1 - progress * progress * (3 - 2 * progress)
    left[index] *= fade
    right[index] *= fade

samples = array("h")
for first, second in zip(left, right):
    samples.extend((round(first * normalization * 32767), round(second * normalization * 32767)))
if sys.byteorder != "little":
    samples.byteswap()

destination = ROOT / "zen/Resources/OnboardingIntro.wav"
destination.parent.mkdir(parents=True, exist_ok=True)
with wave.open(str(destination), "wb") as output:
    output.setnchannels(2)
    output.setsampwidth(2)
    output.setframerate(RATE)
    output.writeframes(samples.tobytes())
print(f"Restored original melody; softer final chord at {ENDING:.2f}s, fade to {DURATION:.1f}s")

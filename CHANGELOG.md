# CHANGELOG — Reach

## 2026-11-05 — First build

Built from nothing in one session on Ivan's ask for a camera-based "touchscreen". The
first decision was the honest one: the camera cannot see the glass, so this is a pointer
driven by hand pose plus a click driven by the sound of a tap, not contact detection.
Prior art checked on GitHub: every hand-mouse project is Python, OpenCV, and MediaPipe;
Project Sistine (3.4k stars) is the only one that detects real contact, and it needs a
mirror. Nothing native, nothing menu bar, so this is new.

Why Vision over MediaPipe: it ships with macOS, runs on the Neural Engine, and the app
has zero dependencies to break. Why One Euro over a moving average: it is the standard
for pointer smoothing because it adapts, calm when still and responsive when moving.

Why the microphone: Ivan asked for every available input. There is no public IMU on
Apple Silicon Macs, so the mics are the only other sensor that can say anything about a
touch. A tap on glass is a sharp broadband transient, easy to hear against speech.

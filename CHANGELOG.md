# CHANGELOG — Reach

## 2026-11-05, later — Measure before tuning

Ivan said "tune it" before the app had ever been switched on, so there was no signal to
tune from. Instead of guessing new numbers, the app now writes every signal the
thresholds judge to `~/Library/Logs/Reach/signals <date>.csv` (pinch ratio, confidence,
raised, audio onset, tap decisions), and the panel shows the live pinch ratio and last tap
strength. Thresholds get set from that file after a real run.

Two false-trigger traps closed on sight. A typing hand reads as a pinch to the pose model
and a keystroke sounds like a screen tap, so: the pointer only follows a hand whose index
tip is above its wrist in the frame (raised, not resting on the keyboard), and neither a
pinch nor a tap counts within 0.3 s of a physical keystroke. The keystroke clock comes
from `CGEventSource.secondsSinceLastEventType`, which needs no permission.

Hand size for the pinch ratio is now the longest of three palm edges rather than one,
because a palm turned edge-on foreshortens any single edge and inflated the ratio.

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
